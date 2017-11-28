require 'sinatra'
require 'oj'
require 'rsolr'
require 'countries'
require 'builder'
require_relative 'helpers/helpers'

before do
  content_type :json
  headers 'Access-Control-Allow-Origin' => '*', 
          'Access-Control-Allow-Methods' => ['OPTIONS', 'POST', 'GET'],
          'Access-Control-Allow-Headers' => 'Content-Type'
end

configure { set :server, :puma }
set :protection, false

Oj.default_options = { :mode => :compat }

ISO3166.configure do |config|
  config.locales = [:en, :pt]
end

solr = RSolr.connect url: 'http://localhost:8983/solr/articles', read_timeout: 240, open_timeout: 240

get '/items' do
  caller = params[:caller]
  articles_query_params = {
    "sort": "pub_date desc",
    "rows": params[:rows] ? params[:rows] : 10,
    "start": params[:start] ? params[:start] : 0
  }

  response = solr.select params: common_query_params.merge(articles_query_params)
  response = items_formatter(response, caller)
  Oj.dump(response)
end

get '/atom' do
  content_type :xml
  caller = nil
  sources_to_show = params[:sourcesToShow]
  sources_to_hide = params[:sourcesToHide]
  hide_source_string = "-source_name:("
  if (sources_to_hide)
    sources_to_hide_array = []
    sources_to_hide.split(",").each do |s|
      sources_to_hide_array << "\"" + s + "\""
    end
    hide_source_string << sources_to_hide_array.join(",")
    hide_source_string << ")"
  end
  date_string = nil
  #date_today = Time.now.strftime("%Y-%m-%d")
  if params[:week]
    date_string = "date_only:[#{params[:day]} TO #{plus_one_week}]"
  else
    date_string = "date_only:#{params[:day]}"
  end
  atom_params = {
    "defType": "edismax",
    "qf": "summary title",
    "q": params[:q] && params[:q] != '' ? "#{params[:q]}" : '*:*',
    # "q": '*:*',
    "fl": 'title,summary,url,source_name,pub_date,id',
    "sort": "pub_date desc",
    "fq": [
      "source_type:national",
      sources_to_hide ? hide_source_string : "",
      # "-source_name:(\"O Jogo\", \"Maisfutebol\", \"Record\", \"O Jogo\", \"A Bola\", \"SAPO Desporto\", \"SAPO Notícias\", \"Diário Digital\")",
      params[:day] ? date_string : "date_only:\"#{Time.now.strftime("%Y-%m-%d")}\""
    ],
    "rows": params[:rows] ? params[:rows] : 100,
    "start": params[:start] ? params[:start] : 0
  }
  articles_query_params = {
    "sort": "pub_date desc",
    "rows": params[:rows] ? params[:rows] : 100,
    "start": params[:start] ? params[:start] : 0,
  }
  response = solr.select params: common_query_params.merge(atom_params)
  response = items_formatter(response, caller)

  xml_title_search_q = params[:q] ? " - Pesquisa por #{params[:q]}" : ""

  builder do |xml|
    xml.instruct! :xml, :version => '1.0'
    xml.rss :version => "2.0" do
      xml.channel do
        xml.title "News Clusters #{xml_title_search_q}"
        xml.description "News Clusters Atom Feed."
        xml.link "http://clusters.tiagodevezas.pt"

        response.each do |doc|
          xml.item do
            xml.title doc['title']
            xml.link doc['url']
            xml.description doc['summary']
            xml.pubDate doc['pub_date']
            xml.guid doc['url']
          end
        end
      end
    end
  end
  # response = items_formatter(response, caller)
  # response
  # Oj.dump(response)
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
  sources_to_show = params[:sourcesToShow]
  sources_to_hide = params[:sourcesToHide]
  current_day = Date.parse(params[:day])
  plus_one_week = current_day + 7
  lingo_params = params[:lingo] ? format_algo_params(params[:lingo]) : nil
  hide_source_string = "-source_name:("
  if (sources_to_hide)
    sources_to_hide_array = []
    sources_to_hide.each do |s|
      sources_to_hide_array << "\"" + s + "\""
    end
    hide_source_string << sources_to_hide_array.join(",")
    hide_source_string << ")"
  end
  date_string = nil
  #date_today = Time.now.strftime("%Y-%m-%d")
  if params[:week]
    date_string = "date_only:[#{params[:day]} TO #{plus_one_week}]"
  else
    date_string = "date_only:#{params[:day]}"
  end
  clustering_params = {
    "defType": "edismax",
    "qf": "summary title",
    "q": params[:q] && params[:q] != '' ? "#{params[:q]}" : '*:*',
    # "q": '*:*',
    "fl": 'title,summary,url,source_name,pub_date,id',
    "sort": "pub_date desc",
    "fq": [
      "source_type:national",
      sources_to_hide ? hide_source_string : "",
      # "-source_name:(\"O Jogo\", \"Maisfutebol\", \"Record\", \"O Jogo\", \"A Bola\", \"SAPO Desporto\", \"SAPO Notícias\", \"Diário Digital\")",
      params[:day] ? date_string : "date_only:\"#{Time.now.strftime("%Y-%m-%d")}\"",
      "summary:['' TO *]"
    ],
    'rows': "10000000"
  }
  lingo_params = {
    'clustering.engine': 'lingo',
    # Clusters
    'LingoClusteringAlgorithm.desiredClusterCountBase': 5 || lingo_params["desiredClusterCountBase"],
    'LingoClusteringAlgorithm.clusterMergingThreshold': 0.1,
    'LingoClusteringAlgorithm.scoreWeight': 0.0 || lingo_params["scoreWeight"],
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
    'TermDocumentMatrixBuilder.maxWordDf': 0.01 || lingo_params["maxWordDf"],
    'TermDocumentMatrixBuilder.termWeighting': 'org.carrot2.text.vsm.LogTfIdfTermWeighting',
    # Phrase extraction
    'PhraseExtractor.dfThreshold': 1 || lingo_params["PhraseExtractor.dfThreshold"],
    # Preprocessing
    'DocumentAssigner.exactPhraseAssignment': false,
    'DocumentAssigner.minClusterSize': 2 || lingo_params["minClusterSize"],
    'CaseNormalizer.dfThreshold': 1 || lingo_params["CaseNormalizer.dfThreshold"]
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
  response = nil
  if !params[:algorithm]
    response = solr.get 'clustering', params: clustering_params.merge(lingo_params)
    response = cluster_formatter(response, lingo_params)
  else
    response = solr.select params: clustering_params
    response = items_formatter(response, nil)
    response = get_news_and_clusters(response)
    # puts clusters
  end
  Oj.dump(response)
end
