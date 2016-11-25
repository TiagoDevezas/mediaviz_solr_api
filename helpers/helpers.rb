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

end