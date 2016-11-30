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

  response = solr.select params: common_query_params.merge(groups_query_params)
  response = totals_formatter(response, groups_query_params[:"facet.pivot"], params)
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