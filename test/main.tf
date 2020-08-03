provider "vsphere" {
  version              = "< 1.16.0"
  allow_unverified_ssl = "true"
}

provider "random" {
  version = "~> 2.2.1"
}

provider "local" {
  version = "~> 1.1"
}

provider "null" {
  version = "~> 2.1.2"
}

provider "tls" {
  version = "~> 2.1.1"
}

#Get from ENV
data "external" "get_vcenter_details" {
  program = ["/bin/bash", "./scripts/get_vcenter_details.sh"]
}

locals {
  vcenter         = data.external.get_vcenter_details.result["vcenter"]
  vcenteruser     = data.external.get_vcenter_details.result["vcenteruser"]
  vcenterpassword = data.external.get_vcenter_details.result["vcenterpassword"]
}

resource "random_string" "random-dir" {
  length  = 8
  special = false
}

resource "tls_private_key" "generate" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "null_resource" "create-temp-random-dir" {
  provisioner "local-exec" {
    command = format("mkdir -p  /tmp/%s", random_string.random-dir.result)
  }
}

data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

module "folder" {
  source = "../modules/folder"

  path          = var.clustername
  datacenter_id = data.vsphere_datacenter.dc.id
}

module "resource_pool" {
  source = "../modules/resource_pool"
  
  name            = var.clustername
  datacenter_id   = data.vsphere_datacenter.dc.id
  vsphere_cluster = var.vsphere_cluster
}

module "deployVM_infranode" {
  source = "../modules/vmware_infravm_provision"
  
  #######
  vsphere_datacenter                 = var.vsphere_datacenter
  vsphere_resource_pool              = var.vsphere_resource_pool
  vm_ipv4_private_address            = var.infra_private_ipv4_address
  vm_private_ipv4_prefix_length      = var.infra_private_ipv4_prefix_length
  vm_vcpu                            = var.infranode_vcpu
  vm_name                            = var.infranode_hostname
  vm_memory                          = var.infranode_memory
  vm_template                        = var.infranode_vm_template
  vm_os_password                     = var.infranode_vm_os_password
  vm_os_user                         = var.infranode_vm_os_user
  vm_domain                          = var.vm_domain_name
  vm_folder                          = var.vm_folder
  proxy_server                       = var.proxy_server
  vm_private_ssh_key                 = length(var.infra_private_ssh_key) == 0 ? tls_private_key.generate.private_key_pem : base64decode(var.infra_private_ssh_key)
  vm_public_ssh_key                  = length(var.infra_public_ssh_key) == 0 ? tls_private_key.generate.public_key_openssh : var.infra_public_ssh_key
  vm_private_network_interface_label = var.vm_private_network_interface_label
  vm_ipv4_gateway                    = var.infranode_vm_ipv4_gateway
  vm_ipv4_address                    = var.infranode_ip
  vm_ipv4_prefix_length              = var.infranode_vm_ipv4_prefix_length
  vm_private_adapter_type            = var.vm_private_adapter_type
  vm_disk1_size                      = var.infranode_vm_disk1_size
  vm_disk1_datastore                 = var.infranode_vm_disk1_datastore
  vm_disk1_keep_on_remove            = var.infranode_vm_disk1_keep_on_remove
  vm_disk2_enable                    = var.infranode_vm_disk2_enable
  vm_disk2_size                      = var.infranode_vm_disk2_size
  vm_disk2_datastore                 = var.infranode_vm_disk2_datastore
  vm_disk2_keep_on_remove            = var.infranode_vm_disk2_keep_on_remove
  vm_dns_servers                     = var.vm_dns_servers
  vm_dns_suffixes                    = var.vm_dns_suffixes
  vm_clone_timeout                   = var.vm_clone_timeout
  random                             = random_string.random-dir.result

  #######
  bastion_host        = var.bastion_host
  bastion_user        = var.bastion_user
  bastion_private_key = var.bastion_private_key
  bastion_port        = var.bastion_port
  bastion_host_key    = var.bastion_host_key
  bastion_password    = var.bastion_password
}

module "NFSServer-Setup" {
  source = "../modules/config_nfs_server"

  vm_ipv4_address     = var.infranode_ip
  vm_os_private_key = length(var.infra_private_ssh_key) == 0 ? tls_private_key.generate.private_key_pem : base64decode(var.infra_private_ssh_key)
  vm_os_user        = var.infranode_vm_os_user
  vm_os_password    = var.infranode_vm_os_password
  nfs_drive         = "/dev/sdb"
  nfs_link_folders  = var.nfs_link_folders
  enable_nfs        = var.enable_nfs

  #######
  bastion_host        = var.bastion_host
  bastion_user        = var.bastion_user
  bastion_private_key = var.bastion_private_key
  bastion_port        = var.bastion_port
  bastion_host_key    = var.bastion_host_key
  bastion_password    = var.bastion_password
  dependsOn           = module.deployVM_infranode.dependsOn
}

module "HTTPServer-Setup" {
  source = "../modules/config_apache_web_server"
  
  vm_ipv4_address     = var.infranode_ip
  vm_os_private_key   = length(var.infra_private_ssh_key) == 0 ? tls_private_key.generate.private_key_pem : base64decode(var.infra_private_ssh_key)
  vm_os_user          = var.infranode_vm_os_user
  vm_os_password      = var.infranode_vm_os_password
  bastion_host        = var.bastion_host
  bastion_user        = var.bastion_user
  bastion_private_key = var.bastion_private_key
  bastion_port        = var.bastion_port
  bastion_host_key    = var.bastion_host_key
  bastion_password    = var.bastion_password
  dependsOn           = module.NFSServer-Setup.dependsOn
}

module "HAProxy-install" {
  source = "../modules/config_lb_server"
  
  vm_ipv4_address     = var.infranode_ip
  vm_os_private_key   = length(var.infra_private_ssh_key) == 0 ? tls_private_key.generate.private_key_pem : base64decode(var.infra_private_ssh_key)
  vm_os_user          = var.infranode_vm_os_user
  vm_os_password      = var.infranode_vm_os_password
  bastion_host        = var.bastion_host
  bastion_user        = var.bastion_user
  bastion_private_key = var.bastion_private_key
  bastion_port        = var.bastion_port
  bastion_host_key    = var.bastion_host_key
  bastion_password    = var.bastion_password
  install             = "true"
  dependsOn           = module.HTTPServer-Setup.dependsOn
}

module "vmware_ign_config" {
  source = "../modules/vmware_ign_config"
  
  vm_ipv4_address          = var.infranode_ip
  vm_os_private_key_base64 = length(var.infra_private_ssh_key) == 0 ? base64encode(tls_private_key.generate.private_key_pem) : var.infra_private_ssh_key
  vm_os_user               = var.infranode_vm_os_user
  vm_os_password           = var.infranode_vm_os_password
  bastion_host             = var.bastion_host
  bastion_user             = var.bastion_user
  bastion_private_key      = var.bastion_private_key
  bastion_port             = var.bastion_port
  bastion_host_key         = var.bastion_host_key
  bastion_password         = var.bastion_password
  dependsOn                = module.HAProxy-install.dependsOn
  ocversion                = var.ocversion
  domain                   = var.ocp_cluster_domain
  clustername              = var.clustername
  controlnodes             = var.control_plane_count
  computenodes             = var.compute_count
  vcenter                  = local.vcenter
  vcenteruser              = local.vcenteruser
  vcenterpassword          = local.vcenterpassword
  vcenterdatacenter        = var.vsphere_datacenter
  vmwaredatastore          = var.infranode_vm_disk1_datastore
  pullsecret               = var.pullsecret
  proxy_server             = var.proxy_server
  vm_ipv4_private_address  = var.infra_private_ipv4_address
}

module "prepare_dns" {
  source = "../modules/config_dns"
  
  dns_server_ip  = var.infranode_ip
  vm_os_user     = var.infranode_vm_os_user
  vm_os_password = var.infranode_vm_os_password
  private_key    = length(var.infra_private_ssh_key) == 0 ? tls_private_key.generate.private_key_pem : base64decode(var.infra_private_ssh_key)
  action         = "setup"
  domain_name    = var.ocp_cluster_domain
  cluster_name   = var.clustername
  cluster_ip     = var.infra_private_ipv4_address
  dhcp_ip_range_start = var.dhcp_ip_range_start
  dhcp_ip_range_end   = var.dhcp_ip_range_end
  dhcp_netmask        = var.dhcp_netmask

  ## Access to optional bastion host
  bastion_host        = var.bastion_host
  bastion_user        = var.bastion_user
  bastion_private_key = var.bastion_private_key
  bastion_port        = var.bastion_port
  bastion_host_key    = var.bastion_host_key
  bastion_password    = var.bastion_password
  dependsOn           = module.vmware_ign_config.dependsOn
}

module "prepare_dhcp" {
  source = "../modules/config_dns"
  
  dns_server_ip       = var.infranode_ip
  vm_os_user          = var.infranode_vm_os_user
  vm_os_password      = var.infranode_vm_os_password
  private_key         = length(var.infra_private_ssh_key) == 0 ? tls_private_key.generate.private_key_pem : base64decode(var.infra_private_ssh_key)
  action              = "dhcp"
  dhcp_interface      = module.vmware_ign_config.private_interface
  dhcp_router_ip      = var.infra_private_ipv4_address
  dhcp_ip_range_start = var.dhcp_ip_range_start
  dhcp_ip_range_end   = var.dhcp_ip_range_end
  dhcp_netmask        = var.dhcp_netmask
  dhcp_lease_time     = var.dhcp_lease_time

  ## Access to optional bastion host
  bastion_host        = var.bastion_host
  bastion_user        = var.bastion_user
  bastion_private_key = var.bastion_private_key
  bastion_port        = var.bastion_port
  bastion_host_key    = var.bastion_host_key
  bastion_password    = var.bastion_password
  dependsOn           = module.prepare_dns.dependsOn
}



