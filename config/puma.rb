environment "production"

bind 'unix:///home/tiagodevezas/Projects/SolrAPI/tmp/solr_api.sock'
pidfile "/home/tiagodevezas/Projects/SolrAPI/tmp/puma/puma.pid"
state_path "/home/tiagodevezas/Projects/SolrAPI/tmp/puma/puma.state"
activate_control_app
