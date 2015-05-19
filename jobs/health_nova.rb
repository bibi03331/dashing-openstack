require 'bundler/setup'
require 'yaml'

# common config file
dashing_config = './config.yaml'
config = YAML.load_file(dashing_config)
environments = config['openstack']

SCHEDULER.every '5s' do

  node_down = Hash.new

  cmd_get_status = "/home/openstack/dashing-openstack/jobs/get_compute_status.sh " + environments['id_admin']
  resp_data = `#{cmd_get_status}`
  resp = JSON.parse(resp_data)

  services = resp['services']
  index = 0
  services.each do |service|
    if service['binary'] == 'nova-compute' and service['status'] == 'enabled' and service['state'] != 'up'
      node_down[index] = service['host']
      index = index + 1
    end
  end

  if index == 1
    status = 'warn'
    text_affich = 'Warning : ' + node_down[0] + ' down'
  elsif index > 1
    status = 'err'
    text_affich = 'Erreur critique des hyperviseurs'
  else
    status = 'ok'
    text_affich = 'Normal'
  end

  send_event('statusNova', { status: status, text: text_affich } )

end
