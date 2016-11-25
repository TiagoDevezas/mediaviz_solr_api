helpers do
  def common_query_params
    {
      "defType": "edismax",
      "qf": params[:field] ? params[:field] : "summary title",
      "q": params[:q] ? "#{params[:q]}" : '*:*',
      "fq": [
        params[:source_type] ? "source_type:#{params[:source_type]}" : nil,
        params[:source_name] ? "source_name:#{params[:source_name]}" : nil,
        params[:source_acronym] ? "source_acronym:#{params[:source_acronym]}" : nil,
        params[:since] ? "date_only:[#{params[:since]} TO *]" : nil,
        params[:until] ? "date_only:[* TO #{params[:until]}]" : nil,
        params[:since] && params[:until] ? "date_only:[#{params[:since]} TO #{params[:until]}]" : nil,
        params[:by] && params[:by] == 'hour' ? "hour:[0 TO 23]" : nil,
        params[:by] && params[:by] == 'weekday' ? "weekday:[1 TO 7]" : nil,
        params[:by] && params[:by] == 'month' ? "month:[1 TO 12]" : nil
      ]
    }
  end

  def sources_formatter response_hash, pivot_fields
    formatted = []
    response = response_hash['facet_counts']['facet_pivot'][pivot_fields]
    response.each do |obj|
      formatted << Hash[
        name: obj['value'],
        type: obj['pivot'][0]['value'],
        acronym: obj["pivot"][0]["pivot"][0]["value"]
      ]
    end 
    formatted
  end

  def totals_formatter response_hash, pivot_fields, params
    formatted = []
    pivot_fields = pivot_fields.split('}')[1]
    response = response_hash['facet_counts']['facet_pivot'][pivot_fields]
    response.each do |obj|
      formatted << Hash[
        time: obj['value'],
        articles: obj['count'],
        twitter_shares: obj['stats'] ? obj['stats']['stats_fields']['twitter_shares']['sum'].to_i : 0,
        facebook_shares: obj['stats'] ? obj['stats']['stats_fields']['facebook_shares']['sum'].to_i : 0,
        total_shares: obj['stats'] ? obj['stats']['stats_fields']['facebook_shares']['sum'].to_i + obj['stats']['stats_fields']['twitter_shares']['sum'].to_i : 0
      ]
    end
    if params[:since]
      since_index = formatted.index { |h| h[:time] == params[:since].to_s} || nil
      formatted = since_index ? formatted[since_index..-1] : formatted
    end
    if params[:until]
      until_index = formatted.index { |h| h[:time] == params[:until].to_s} || nil
      formatted = until_index ? formatted[0..until_index] : formatted
    end
    formatted
  end

  def items_formatter response_hash
    response_hash['response']['docs']
  end

end