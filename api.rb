require 'sinatra'
# require 'sinatra/json'
require 'oj'
require 'rsolr'
require_relative 'helpers/helpers'

Oj.default_options = {:mode => :strict }

solr = RSolr.connect url: 'http://localhost:8983/solr/articles'

get '/articles' do
  content_type :json

  articles_query_params = {
    "sort": "pub_date desc"
  }

  response = solr.select params: common_query_params.merge(articles_query_params)
  Oj.dump(response)
end

get '/groups' do
  content_type :json

  groups_query_params = {
    "fl": "null",
    "stats": true,
    "facet": true,
    "facet.pivot": params[:by] ? "{!stats=t1}#{params[:by]}" : "{!stats=t1}date_only",
    "stats.field": [
      "{!tag=t1 sum=true}facebook_shares",
      "{!tag=t1 sum=true}twitter_shares"
    ],
    "facet.sort": params[:by] ? "#{params[:by]} asc" : "date_only asc",
    "facet.limit": -1,
    "facet.pivot.mincount": (params[:since] || params[:until]) && !params[:by] ? 1 : 0
  }

  response = solr.select params: common_query_params.merge(groups_query_params)
  Oj.dump(response)
end