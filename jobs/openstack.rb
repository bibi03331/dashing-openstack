SCHEDULER.every '10s' do

  require 'bundler/setup'
  require 'json'
  require 'pp'

  def get_tenant_data(id, neutron_quotas=false)
    tenant_data = Hash.new

    cmd_get_limits = "/home/openstack/dashing-openstack/jobs/get_compute_limits.sh " + id
    resp_data = `#{cmd_get_limits}`
    resp = JSON.parse(resp_data)

    limits = resp['limits']['absolute']
    tenant_data['instances_used'] = limits['totalInstancesUsed']
    tenant_data['instances_max'] = limits['maxTotalInstances']
    tenant_data['cores_used'] = limits['totalCoresUsed']
    tenant_data['cores_max'] = limits['maxTotalCores']
    tenant_data['ram_used'] = limits['totalRAMUsed'] == nil ? 0 : limits['totalRAMUsed'] / 1024
    tenant_data['ram_max'] = limits['maxTotalRAM'] == nil ? 0 : limits['maxTotalRAM'] / 1024
    tenant_data['floatingips_used'] = limits['totalFloatingIpsUsed']
    tenant_data['floatingips_max'] = limits['maxTotalFloatingIps']
    tenant_data['securitygroups_used'] = limits['totalSecurityGroupsUsed']
    tenant_data['securitygroups_max'] = limits['maxTotalSecurityGroups']
    tenant_data['keypairs_used'] = limits['totalKeypairsUsed']
    tenant_data['keypairs_max'] = limits['maxTotalKeypairs']

    cmd_get_quotas = "/home/openstack/dashing-openstack/jobs/get_compute_quotas.sh " + id
    resp_data = `#{cmd_get_quotas}`
    resp = JSON.parse(resp_data)

    quotas = resp['quota_set']
    tenant_data['instances_quota'] = quotas['instances']
    tenant_data['cores_quota'] = quotas['cores']
    tenant_data['ram_quota'] = quotas['ram'] == nil ? 0 : quotas['ram'] / 1024
    tenant_data['floatingips_quota'] = quotas['floating_ips']
    tenant_data['securitygroups_quota'] = quotas['security_groups']
    tenant_data['keypairs_quota'] = quotas['key_pairs']


    cmd_get_quotas = "/home/openstack/dashing-openstack/jobs/get_storage_limits.sh " + id
    resp_data = `#{cmd_get_quotas}`
    resp = JSON.parse(resp_data)

    storage = resp['limits']['absolute']
    tenant_data['storage_quota'] = storage['maxTotalVolumeGigabytes']
    tenant_data['storage_used'] = storage['totalGigabytesUsed']

    # floating ips
    # ( need to ask neutron, compute/limits gives wrong values )
    if neutron_quotas
      resp = network.request(:list_quotas) do |params|
        params.tenant_id=id
      end
      tenant_data['floatingips_quota'] = resp.body['quota']['floatingip'].to_i

      resp = network.request(:list_floatingips) do |params|
        params.tenant_id=id
      end
      tenant_data['floatingips_used'] = resp.body['floatingips'].length
      tenant_data['floatingips_max'] = tenant_data['floatingips_quota']
    end

    return tenant_data
  end

  def get_hypervisor_data(id)
    data = Hash.new

    cmd_get_hypervisor = "/home/openstack/dashing-openstack/jobs/get_compute_hypervisor.sh " + id
    resp_data = `#{cmd_get_hypervisor}`
    resp = JSON.parse(resp_data)

    hypervisors = resp['hypervisors']
    hypervisors.each do |hypervisor|
      name = hypervisor['hypervisor_hostname']
      data[name] = Hash.new
      data[name]['vcpus_used'] = hypervisor['vcpus_used']
      data[name]['vcpus_total'] = hypervisor['vcpus']
      data[name]['ram_used'] = hypervisor['memory_mb_used'] * 1024 * 1024
      data[name]['ram_total'] = hypervisor['memory_mb'] * 1024 * 1024
      data[name]['running_vms'] = hypervisor['running_vms']
    end

    return data
  end

  def convert_num(num)

    if num >= 1024**6
      "#{(num / (1024**6)).ceil} EB"
    elsif num >= 1024**5
      "#{(num / (1024**5)).ceil} PB"
    elsif num >= 1024**4
      "#{(num / (1024**4)).ceil} TB"
    elsif num >= 1024**3
      "#{(num / (1024**3)).ceil} GB"
    elsif num >= 1024**2
      "#{(num / (1024**2)).ceil} MB"
    elsif num >= 1024
      "#{(num / 1024).ceil }KB"
    else
      "#{num}B"
    end
  
  end

  # common config file
  dashing_config = './config.yaml'
  config = YAML.load_file(dashing_config)
  environments = config['openstack']

  tenant_stats = Hash.new

  cmd_get_tenants = "/home/openstack/dashing-openstack/jobs/get_compute_tenants.sh"
  resp_data = `#{cmd_get_tenants}`
  resp = JSON.parse(resp_data)

  tenants = resp['tenants']
  tenants.each do |tenant|
    tenant_stats[tenant['name']] = get_tenant_data(tenant['id'], config['openstack']['neutron_quotas'])
  end
  
  # populate the tenant widgets
  {
    'cores' => 'Projets : VCPUs', 'instances' => 'Projets : Instances', 'ram' => 'Projets : RAM', 'storage' => 'Projets : Stockage',
  }.each do | metric, title |
    data = Array.new
    sorted_tenants = tenant_stats.sort_by {|k, v| v["#{metric}_used"]}.reverse
    for tenant in sorted_tenants[0..5] do
      data.push({
        name: tenant[0], progress: (tenant[1]["#{metric}_used"] * 100.0) / tenant[1]["#{metric}_quota"],
        value: tenant[1]["#{metric}_used"], max: tenant[1]["#{metric}_quota"]
      })
    end
    if sorted_tenants.length > 5
      other = { 'used' => 0.0, 'quota' => 0.0 }
      for tenant in sorted_tenants[5, sorted_tenants.length] do
        other['used'] += tenant[1]["#{metric}_used"].to_f
        other['quota'] += tenant[1]["#{metric}_quota"].to_f
      end
      data.push({
        name: 'Autres', progress: (other['used'] * 100.0) / other['quota'], value: other['used'], max: other['quota']
      })
    end
    send_event("#{metric}-tenant", { title: title, progress_items: data})
  end

  # retrieve the hypervisor information
  hypervisors_stats = get_hypervisor_data(environments['id_admin'])

  # populate the hypervisor widgets
  {
    'vcpus' => ['VCPUs du cluster', false], 'ram' => ['RAM du cluster', true],
  }.each do |metric, title|
    total = 0
    sum = 0

    overcommit = config['openstack']["#{metric}_allocation_ratio"].to_f
    sumLight = 0
    hypervisors_stats.each do |name, metrics|
        total += metrics["#{metric}_total"].to_i * overcommit
        # account for reserve resources per hypervisor
        total -= config['openstack']["reserved_#{metric}_per_node"].to_i
        sum += metrics["#{metric}_used"].to_i
	sumLight = (sum / 1024) / 1024
    end
    # account for reserve resources for node failure
    total -= config['openstack']["reserved_#{metric}"].to_i

    send_event("#{metric}-hypervisor", { title: title[0], 
                                         value: Filesize.from("#{sum} KB").pretty.split(' ').first.to_i,
					 min: 0,
					 max: Filesize.from("#{total.to_i} KB").pretty.split(' ').first.to_f,
                                         moreinfo: "#{title[1] ? convert_num(sum) : sum} out of #{title[1] ? convert_num(total.to_i) : total.to_i}", 
    })
  end

end
