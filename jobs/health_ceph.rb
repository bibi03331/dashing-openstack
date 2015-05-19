require 'bundler/setup'
require 'yaml'

# common config file
dashing_config = './config.yaml'
config = YAML.load_file(dashing_config)
environments = config['ceph']

SCHEDULER.every '5s' do

  cmd_get_status = "ceph health"
  result = `#{cmd_get_status}`

  if result =~ /.*HEALTH_WARN.*/m
    status = 'warn'
    text_affich = 'Warning'
  elsif result =~ /.*HEALTH_ERR.*/m
    status = 'err'
    text_affich = 'Erreur'
  else
    status = 'ok'
    text_affich = 'Normal'
  end

  send_event('statusCeph', { status: status, text: text_affich } )

end
