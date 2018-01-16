require 'json'
require 'murmurhash3'

$stopwords = "a as à às ao aos o os e é és em de des da das do dos um uns uma umas num nuns numa numas que no nos na nas com como por para até aí cada este estes esta estas se".split(' ')
# $buckets = {}
# $clusters = []

# $shingle_size = 3
# $hash_functions = 200
# $num_rows = 3
# $min_cluster_size = 3

def get_shingles text, size
  text = prepare_text(text)
  shingles = text.each_cons(size).to_a.map { |shingle| shingle.join(' ') }
end

def prepare_text text
  text = text.downcase
  text = text.gsub(/[,"'\:]/, "")
  text = text.gsub(/ -/, "").gsub(/- /, "")
  text = text.gsub(/\s+/, " ")
  text = text.gsub(/^\s\s*/, "").gsub(/\s\s*$/, "")
  words = text.split(' ')
  words = words - $stopwords
end

def get_minhash_signatures shingles, hash_functions
  signature = []

  hash_functions.times do |i|
    minhash = Float::INFINITY

    shingles.each do |shingle|
      hash = MurmurHash3::V32.str_hash(shingle, (i + 1) * 2)
      minhash = hash < minhash ? hash : minhash
    end

    signature << minhash

  end

  signature = signature.uniq

end

def get_band_signature signature, num_rows, doc_id
  signature.each_slice(num_rows).map do |sig|
    hash = MurmurHash3::V32.str_hash(sig.join(''), 32)
    if !$buckets[hash]
      $buckets[hash] = []
    end 
    $buckets[hash] << doc_id
  end
end

def get_related buckets
  related = {}
  buckets.each do |key, value|
    if value.length > 1
      related[key] = value
    end
  end
  unique_related = related.values
  unique_related = unique_related.uniq
  get_clusters(unique_related)
end

def get_clusters doc_id_arr
  # From https://stackoverflow.com/a/29314633
  return doc_id_arr if doc_id_arr.empty?
  rest = doc_id_arr.dup
  groups = []
  group = []
  while rest.any?
    group = rest.shift if group.empty?
    if i = rest.each_index.find { |i| (rest[i] & group).any? }
      group |= rest[i]
      rest.delete_at(i) 
      groups << group if rest.empty?
    else
      groups << group
      group = []
    end
  end
  $clusters = groups
  $clusters = $min_cluster_size ? $clusters.reject { |cluster| cluster.size < $min_cluster_size } : $clusters
  $clusters = $clusters ? $clusters.sort_by { |cluster| -cluster.size } : []
  # puts $clusters
end

def jaccard_similarity arr_a, arr_b
  intersection = (arr_a & arr_b).size
  union = (arr_a | arr_b).size

  jaccard_s = intersection.to_f / union
end

def get_news_and_clusters items, params

  $buckets = {}
  $clusters = []

  $shingle_size = params['shingle_size'] ? params['shingle_size'].to_i : 3
  $hash_functions = params['hash_functions'] ? params['hash_functions'].to_i : 200
  $num_rows = params['num_rows'] ? params['num_rows'].to_i : 3
  $min_cluster_size = params['min_cluster_size'] ? params['min_cluster_size'].to_i : 3

  items.each do |item|
    next if item['title'].empty? || item['summary'].empty?
    shingles = get_shingles(item['title'] + " " + item['summary'], $shingle_size)
    sigs = get_minhash_signatures(shingles, $hash_functions)
    get_band_signature(sigs, $num_rows, item['id'])
  end
  get_related($buckets)
  
  clusters_with_title = []
  $clusters.each_with_index do |cluster, i|
    new_cluster = cluster.map do |id|
      item = items.select { |item| item['id'] == id }
    end
    cluster_obj = {}
    cluster_obj['cluster'] = "cluster_#{i}"
    cluster_obj['items'] = new_cluster.flatten.uniq.sort { |a,b| b['pub_date'] <=> a['pub_date'] }
    cluster_obj['latest_date'] = cluster_obj['items'][0]['pub_date']
    cluster_obj['score'] = cluster_obj['items'].size
    clusters_with_title << cluster_obj
  end

  payload = Hash[clusters: clusters_with_title]

end
