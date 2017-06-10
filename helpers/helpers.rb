helpers do
  def common_query_params
    {
      "defType": "edismax",
      "qf": params[:field] ? params[:field] : "summary title",
      "q": params[:q] && params[:q] != '' ? "#{params[:q]}" : '*:*',
      "fq": [
        params[:source_type] ? "source_type:#{params[:source_type]}" : nil,
        params[:source_name] ? "source_name:\"#{params[:source_name]}\"" : nil,
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

  def totals_formatter response_hash, response_all_hash, pivot_fields, params
    formatted = []
    formatted_all_counts = []
    pivot_fields = pivot_fields.split('}')[1]
    total_source_count = response_hash['response']['numFound']
    response = response_hash['facet_counts']['facet_pivot'][pivot_fields]
    response_all = response_all_hash ? response_all_hash['facet_counts']['facet_pivot'][pivot_fields] : nil
    if response_all
      response_all.each do |obj|
        formatted_all_counts << obj['count']
      end
    end
    i = 0
    response.each do |obj|
      formatted << Hash[
        time: obj['value'],
        articles: obj['count'],
        twitter_shares: obj['stats'] ? obj['stats']['stats_fields']['twitter_shares']['sum'].to_i : 0,
        facebook_shares: obj['stats'] ? obj['stats']['stats_fields']['facebook_shares']['sum'].to_i : 0,
        total_shares: obj['stats'] ? obj['stats']['stats_fields']['facebook_shares']['sum'].to_i + obj['stats']['stats_fields']['twitter_shares']['sum'].to_i : 0,
        percent_of_source: obj['count'] > 0 && total_source_count.to_f > 0 ? ((obj['count'] / total_source_count.to_f) * 100).round(2) : 0,
        percent_of_day: obj['count'] > 0 && formatted_all_counts[i].to_f > 0 ? ((obj['count'] / formatted_all_counts[i].to_f) * 100 ).round(2) : 0
      ]
      i += 1
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

  def places_formatter response, places_list
    places = []
    counts = response.values
    i = 0
    places_list.each do |place|
      place[:count] = counts[i]
      places << place 
      i += 1
    end
    places
  end

  def get_places_list_for map_type, lang
    places = []
    if map_type == 'pt'
      ISO3166::Country.find_country_by_name('Portugal').subdivisions.each do |k, v|
        places << { fips: convert_to_fips(k), name: v[0] }
      end
    else
      countries = ISO3166::Country.all
      countries.each do |c|
        country = ISO3166::Country.find_country_by_alpha2(c.alpha2)
        country_name = country.translation(lang) ? country.translation(lang) : country.name
        alpha2_code = country.alpha2
        alpha3_code = country.alpha3
        country_code = country.country_code
        places << Hash[
            name: country_name,
            alpha2: alpha2_code,
            alpha3: alpha3_code,
            country_code: country_code
          ]
      end
    end
    places
  end

  def generate_places_query places_list
    query_array = []
    base_query = "{!type=edismax qf=\"title summary\"}"
    places_list.each do |place|
      query_array << "#{base_query}\"#{place[:name]}\""
    end
    query_array
  end

  def convert_to_fips(code)
    code = code.to_s
    one_to_eight = (1..8).to_a.map { |el| '0' + el.to_s }
    twelve_to_eighteen = (12..18).to_a.map { |el| el.to_s }
    if code == "20"
      return "PO23"
    end
    if code == "30"
      return "PO10"
    end
    if code == "09"
      return "PO11"
    end
    if code == "10" || code == "11"
      return "PO" + (code.to_i + 3).to_s
    end
    if one_to_eight.include?(code)
      return "PO0" + (code.to_i + 1).to_s
    end
    if twelve_to_eighteen.include?(code)
      return "PO" + (code.to_i + 4).to_s
    end
  end

  def cluster_formatter response_hash, lingo_params
    clustered = []
    sources = response_hash["response"]["docs"].collect { |doc| doc["source_name"] }.uniq.sort
    documents = response_hash["response"]["docs"]
    clusters = response_hash["clusters"]
    clusters.each do |cluster|
      if cluster["score"] > 3
        items_and_date = get_items(cluster["docs"], 5, documents)
        items = items_and_date[:items]
        latest_date = items_and_date[:latest_date]
        clustered << Hash[
          labels: cluster["labels"],
          score: cluster["score"],
          items: items,
          latest_date: latest_date
        ]
      end
    end
    # clustered.size > 25 ? clustered.slice(0, 25) : clustered
    Hash[sources: sources, algorithm_params: lingo_params, clusters: clustered.sort_by! { |cluster| cluster[:score] }.reverse]
  end

  def get_cluster_latest_date cluster, documents
    # puts cluster["docs"][0]
    first_item = documents.find { |doc| doc["id"] == cluster["docs"][0] }["pub_date"]
    latest_date = first_item
  end

  def get_items doc_ids_array, num_docs, all_documents
    item_array = []
    # random_items = doc_ids_array[0..num_docs]
    random_items = doc_ids_array.sample(num_docs)
    random_items.each do |item|
      item_array.push all_documents.find { |doc| doc["id"] == item }
    end
    item_array_sorted = item_array.sort_by { |k| k["pub_date"] }.reverse
    latest_date = item_array_sorted[0]["pub_date"]
    items_and_date = Hash[items: item_array_sorted, latest_date: latest_date]
    # puts items_and_date[:items]
    # item_array_sorted
  end

end