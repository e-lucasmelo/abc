#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

if [ $host_temp = "compute" ]; then

echo "Instalando os pacotes do Neutron..."
sudo apt install neutron-openvswitch-agent -y &>/dev/null

echo "Configurando o arquivo /etc/neutron/neutron.conf..."
sudo bash -c "cat <<EOF > /etc/neutron/neutron.conf
[DEFAULT]
core_plugin = ml2
transport_url = rabbit://openstack:$senha@${controller[0]}

[agent]
root_helper = \"sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf\"

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF"

echo "Configurando o arquivo /etc/neutron/plugins/ml2/openvswitch_agent.ini..."
sudo bash -c "cat <<EOF > /etc/neutron/plugins/ml2/openvswitch_agent.ini
[ovs]
bridge_mappings = provider:br-provider
local_ip = ${host_array[1]}

[agent]
tunnel_types = vxlan
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = openvswitch
EOF"

echo "configurando a bridge para a interface de provider..."
sudo ovs-vsctl add-br br-provider
sudo ovs-vsctl add-port br-provider $interfaceProvider
echo "reiniciando serviços nova e neutron"
sudo service nova-compute restart
sudo service neutron-openvswitch-agent restart
echo "faça a configuração do host block."
echo "Se não for utilizar o host block, volte e faça a configuração de update do host controller"
fi

if [ $host_temp = "controller" ]; then
echo "Configurando o banco de dados MySQL para o Neutron..."
sudo mysql <<EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$senha';
FLUSH PRIVILEGES;
EOF

echo "Carregando variáveis de ambiente do OpenStack..."
source "$SCRIPT_DIR/admin-openrc"

echo "Criando usuário Neutron e atribuindo permissões..."
openstack user create --domain default --password "$senha" neutron
openstack role add --project service --user neutron admin
openstack role add --project service --user neutron service

echo "Criando serviço Neutron..."
openstack service create --name neutron --description "OpenStack Networking" network

echo "Criando endpoint Neutron..."
openstack endpoint create --region RegionOne network public http://${controller[0]}:9696
openstack endpoint create --region RegionOne network internal http://${controller[0]}:9696
openstack endpoint create --region RegionOne network admin http://${controller[0]}:9696

echo "Instalando os pacotes do Neutron..."
sudo apt install neutron-server neutron-plugin-ml2 neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent -y &>/dev/null

echo "Configurando o arquivo /etc/neutron/neutron.conf..."
sudo bash -c "cat <<EOF > /etc/neutron/neutron.conf
[DEFAULT]
core_plugin = ml2
service_plugins = router,vpnaas
transport_url = rabbit://openstack:$senha@${controller[0]}
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[agent]
root_helper = \"sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf\"

[database]
connection = mysql+pymysql://neutron:$senha@${controller[0]}/neutron

[keystone_authtoken]
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = neutron
password = $senha

[nova]
auth_url = http://${controller[0]}:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = nova
password = $senha

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF"


echo "Configurando o arquivo /etc/neutron/plugins/ml2/ml2_conf.ini..."
sudo bash -c 'cat <<EOF > /etc/neutron/plugins/ml2/ml2_conf.ini
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = openvswitch,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[ml2_type_vxlan]
vni_ranges = 1:1000
EOF'

echo "Configurando o arquivo /etc/neutron/plugins/ml2/openvswitch_agent.ini..."
sudo bash -c "cat <<EOF > /etc/neutron/plugins/ml2/openvswitch_agent.ini
[ovs]
bridge_mappings = provider:br-provider
local_ip = ${controller[1]}
[agent]
tunnel_types = vxlan
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = openvswitch
EOF"

echo "Configurando o arquivo /etc/neutron/l3_agent.ini..."
sudo bash -c 'cat <<EOF > /etc/neutron/l3_agent.ini
[DEFAULT]
interface_driver = openvswitch
[AGENT]
extensions = vpnaas
[vpnagent]
vpn_device_driver = neutron_vpnaas.services.vpn.device_drivers.strongswan_ipsec.StrongSwanDriver
EOF'

echo "Configurando o arquivo /etc/neutron/dhcp_agent.ini..."
sudo bash -c 'cat <<EOF > /etc/neutron/dhcp_agent.ini
[DEFAULT]
interface_driver = openvswitch
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
EOF'

echo "Configurando o arquivo /etc/neutron/metadata_agent.ini..."
sudo bash -c "cat <<EOF > /etc/neutron/metadata_agent.ini
[DEFAULT]
nova_metadata_host = ${controller[0]}
metadata_proxy_shared_secret = $senha
EOF"

sudo ovs-vsctl add-br br-provider
sudo ovs-vsctl add-port br-provider $interfaceProvider

echo "instalando pacotes para a VPN..."
sudo apt install python3-neutron-vpnaas neutron-vpnaas-common python3-neutron-vpnaas-dashboard python3-pip gettext -y &>/dev/null

sudo bash -c "cat <<EOF > /etc/neutron/neutron_vpnaas.conf
[service_providers]
service_provider = VPN:strongswan:neutron_vpnaas.services.vpn.service_drivers.ipsec.IPsecVPNDriver:default
EOF"

sudo bash -c "cat <<EOF > /etc/neutron/vpn_agent.ini
[DEFAULT]
interface_driver = openvswitch
vpn_device_driver = neutron_vpnaas.services.vpn.device_drivers.ipsec.IPsecDriver
state_path = /var/lib/neutron
debug = True
log_file = /var/log/neutron/vpn-agent.log
periodic_interval = 10
EOF"

echo "Sincronizando o banco de dados Neutron e arquivos de conf..."
sudo -u neutron /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" &>/dev/null

echo "Reiniciando o serviço do NOVA API..."
sudo service nova-api restart

echo "Reiniciando os serviços do Neutron..."
sudo service neutron-server restart
sudo service neutron-openvswitch-agent restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-l3-agent restart
fi