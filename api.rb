require 'sinatra'
require 'oj'
require 'rsolr'
require 'countries'
require_relative 'helpers/helpers'

before do
  content_type :json
  headers 'Access-Control-Allow-Origin' => '*', 
          'Access-Control-Allow-Methods' => ['OPTIONS', 'POST', 'GET'],
          'Access-Control-Allow-Headers' => 'Content-Type'
end

configure { set :server, :puma }
set :protection, false

Oj.default_options = {:mode => :compat }

ISO3166.configure do |config|
  config.locales = [:en, :pt]
end

solr = RSolr.connect url: 'http://localhost:8983/solr/articles'

get '/items' do
  articles_query_params = {
    "sort": "pub_date desc",
    "rows": params[:limit] ? params[:limit] : 10,
    "start": params[:offset] ? params[:offset] : 0
  }

  response = solr.select params: common_query_params.merge(articles_query_params)
  response = items_formatter(response)
  Oj.dump(response)
end

get '/totals' do
  groups_query_params = {
    "fl": "null",
    "stats": true,
    "facet": true,
    "facet.pivot": params[:by] && params[:by] != 'day' ? "{!stats=t1}#{params[:by]}" : "{!stats=t1}date_only",
    "stats.field": [
      "{!tag=t1 sum=true}facebook_shares",
      "{!tag=t1 sum=true}twitter_shares"
    ],
    "facet.sort": params[:by] ? "#{params[:by]} asc" : "date_only asc",
    "facet.limit": -1,
    "facet.pivot.mincount": 0
    # "facet.pivot.mincount": (params[:since] || params[:until]) && params[:by] != 'day' ? 1 : 0
  }

  alt_query_params = common_query_params
  alt_query_params[:q] = '*:*'

  response = solr.select params: common_query_params.merge(groups_query_params)
  response_all = nil
  if params[:q]
    response_all = solr.select params: alt_query_params.merge(groups_query_params)
  end
  response = totals_formatter(response, response_all, groups_query_params[:"facet.pivot"], params)
  Oj.dump(response)
end

get '/sources' do
  sources_query_params = {
    "q": "*:*",
    "fl": "null",
    "facet": true,
    "facet.pivot": "source_name,source_type,source_acronym",
    "facet.limit": -1
  }
  response = solr.select params: sources_query_params
  response = sources_formatter(response, sources_query_params[:"facet.pivot"])
  Oj.dump(response)
end

get '/places' do
  map_type = !params[:map] || params[:map].downcase == 'portugal' ? 'pt' : 'world'
  lang = lang = params[:lang] || 'pt'

  places_list = get_places_list_for(map_type, lang)

  places_query_params = {
    "facet": true,
    "fl": "null",
    "facet.query": generate_places_query(places_list)
  }
  response = solr.post 'select', data: common_query_params.merge(places_query_params)
  response = response["facet_counts"]["facet_queries"]
  response = places_formatter(response, places_list)
  Oj.dump(response)
end

get '/clusters' do
  clustering_params = {
    "defType": "edismax",
    "qf": "summary title",
    "q": '*:*',
    "fl": 'title,summary,url,source_name,pub_date,id',
    "sort": "pub_date desc",
    "fq": [
      "source_type:national",
      "-source_name:(\"O Jogo\", \"Maisfutebol\", \"Record\", \"O Jogo\", \"A Bola\", \"SAPO Desporto\", \"SAPO Notícias\", \"Diário Digital\")",
      params[:day] ? "date_only:\"#{params[:day]}\"" : "date_only:\"#{Time.now.strftime("%Y-%m-%d")}\"",
      "summary:['' TO *]"
    ],
    'rows': "10000000"
  }
  lingo_params = {
    'clustering.engine': 'lingo',
    # Clusters
    'LingoClusteringAlgorithm.desiredClusterCountBase': 15,
    'LingoClusteringAlgorithm.clusterMergingThreshold': 0.3,
    'LingoClusteringAlgorithm.scoreWeight': 0.0,
    # Labels
    'LingoClusteringAlgorithm.labelAssigner': 'org.carrot2.clustering.lingo.UniqueLabelAssigner',
    'LingoClusteringAlgorithm.phraseLabelBoost': 10.0,
    'LingoClusteringAlgorithm.phraseLengthPenaltyStart': 8,
    'LingoClusteringAlgorithm.phraseLengthPenaltyStop': 8,
    'TermDocumentMatrixBuilder.titleWordsBoost': 10.0,
    'CompleteLabelFilter.labelOverrideThreshold': 0.0,
    # Matrix model
    'TermDocumentMatrixReducer.factorizationFactory': 'org.carrot2.matrix.factorization.NonnegativeMatrixFactorizationEDFactory',
    'TermDocumentMatrixBuilder.maximumMatrixSize': 375000,
    'TermDocumentMatrixBuilder.maxWordDf': 0.01,
    'TermDocumentMatrixBuilder.termWeighting': 'org.carrot2.text.vsm.LogTfIdfTermWeighting',
    # Phrase extraction
    'PhraseExtractor.dfThreshold': 1,
    # Preprocessing
    'DocumentAssigner.exactPhraseAssignment': false,
    'DocumentAssigner.minClusterSize': 2,
    'CaseNormalizer.dfThreshold': 1
  }

  stc_params = {
    'clustering.engine': 'stc',
    # Base clusters
    'STCClusteringAlgorithm.documentCountBoost': 1.0,
    'STCClusteringAlgorithm.maxBaseClusters': 300,
    'STCClusteringAlgorithm.minBaseClusterSize': 2,
    'STCClusteringAlgorithm.optimalPhraseLength': 3,
    'STCClusteringAlgorithm.optimalPhraseLengthDev': 2.0,
    'STCClusteringAlgorithm.singleTermBoost': 0.5,
    # Clusters
    'STCClusteringAlgorithm.mergeStemEquivalentBaseClusters': true,
    'STCClusteringAlgorithm.scoreWeight': 1.0,
    # Labels
    'STCClusteringAlgorithm.maxPhraseOverlap': 0.6,
    'STCClusteringAlgorithm.maxPhrases': 3,
    'STCClusteringAlgorithm.maxDescPhraseLength': 4,
    'STCClusteringAlgorithm.mostGeneralPhraseCoverage': 0.5,
    # Merging and output
    'STCClusteringAlgorithm.mergeThreshold': 0.6,
    'STCClusteringAlgorithm.maxClusters': 15,
    # Preprocessing
    'CaseNormalizer.dfThreshold': 1,
    # Word filtering
    'STCClusteringAlgorithm.ignoreWordIfInHigherDocsPercent': 0.9,
    'STCClusteringAlgorithm.ignoreWordIfInFewerDocs': 2
  }

  kmeans_params = {
    'clustering.engine': 'kmeans',
    # Clusters
    'BisectingKMeansClusteringAlgorithm.clusterCount': 45,
    'BisectingKMeansClusteringAlgorithm.labelCount': 3,
    # K-means
    'BisectingKMeansClusteringAlgorithm.maxIterations': 15,
    'BisectingKMeansClusteringAlgorithm.partitionCount': 2,
    'BisectingKMeansClusteringAlgorithm.useDimensionalityReduction': true,
    # Labels
    'TermDocumentMatrixBuilder.titleWordsBoost': 2.0,
    # Matrix model
    'TermDocumentMatrixReducer.factorizationFactory': 'org.carrot2.matrix.factorization.NonnegativeMatrixFactorizationEDFactory',
    'TermDocumentMatrixBuilder.maximumMatrixSize': 37500,
    'TermDocumentMatrixBuilder.maxWordDf': 0.9,
    'TermDocumentMatrixBuilder.termWeighting': 'org.carrot2.text.vsm.LogTfIdfTermWeighting',
    # Preprocessing
    'CaseNormalizer.dfThreshold': 1,
  }

  response = solr.get 'clustering', params: clustering_params.merge(lingo_params)
  response = cluster_formatter(response, lingo_params)
  Oj.dump(response)
end