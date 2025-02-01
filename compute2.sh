#!/bin/bash


# Atualizar e atualizar o sistema
echo "Atualizando o sistema..."
sudo apt update &>/dev/null && sudo apt upgrade -y &>/dev/null

# Definir o nome do host como 'compute2'
echo "Definindo o hostname como 'compute2'..."
sudo hostnamectl set-hostname compute2

# Editar o arquivo /etc/hosts
echo "Adicionando entradas no /etc/hosts..."
sudo bash -c 'cat <<EOF > /etc/hosts
127.0.0.1	localhost
192.168.1.10	controller
192.168.1.21	compute1
192.168.1.22	compute2
192.168.1.23	compute3
192.168.1.24	compute4
192.168.1.31	storage1
192.168.1.32	storage2
192.168.1.33	storage3
EOF'

# Configurar o fuso horário para America/Sao_Paulo
echo "Configurando o fuso horário para America/Sao_Paulo..."
sudo timedatectl set-timezone America/Sao_Paulo

# Editar o arquivo de configuração de rede /etc/netplan/50-cloud-init.yaml
echo "Configurando rede no /etc/netplan/50-cloud-init.yaml..."
sudo bash -c 'cat <<EOF > /etc/netplan/50-cloud-init.yaml
network:
    ethernets:
        enp0s3:
            addresses:
            - 192.168.1.22/24
            nameservers:
                addresses:
                - 181.213.132.2
                - 181.213.132.3
                search: []
            routes:
            -   to: default
                via: 192.168.1.1
                metric: 100
            -   to: 181.213.132.2
                via: 192.168.1.1
                metric: 100
            -   to: 181.213.132.3
                via: 192.168.1.1
                metric: 100
            dhcp6: false
            accept-ra: no
        enp0s8:
            dhcp4: false
            dhcp6: false
            accept-ra: no
        enp0s9:
            dhcp4: true
            dhcp6: false
            accept-ra: no
    version: 2
EOF'

# Desabilitar configuração de rede no /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
echo "Desabilitando a configuração de rede no /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg..."
sudo bash -c 'cat <<EOF > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network: {config: disabled}
EOF'

# Aplicar as configurações do Netplan
echo "Aplicando configurações do Netplan..."
sudo netplan apply

# Instalar o Chrony e configurar o servidor NTP
echo "Instalando o Chrony..."
sudo apt install chrony -y &>/dev/null

# Configurar o arquivo de configuração do Chrony
echo "Configurando o arquivo /etc/chrony/chrony.conf..."
sudo bash -c 'cat <<EOF > /etc/chrony/chrony.conf
server controller iburst
confdir /etc/chrony/conf.d
sourcedir /run/chrony-dhcp
sourcedir /etc/chrony/sources.d
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
leapsectz right/UTC
EOF'

# Reiniciar o serviço Chrony
echo "Reiniciando o serviço Chrony..."
sudo service chrony restart

# Verificar as fontes do Chrony
echo "Verificando fontes do Chrony..."
sudo chronyc sources

# Adicionar o repositório do OpenStack Caracal
echo "Adicionando o repositório do OpenStack Caracal..."
sudo add-apt-repository -y cloud-archive:caracal &>/dev/null

# Instalar os pacotes necessários
echo "Instalando pacotes OpenStack..."
sudo apt update &>/dev/null
sudo apt install nova-compute -y &>/dev/null
sudo apt install python3-openstackclient -y &>/dev/null

# Instalar os pacotes do Nova
echo "Instalando o Nova-compute..."
sudo apt install nova-compute -y &>/dev/null

# Configuração do arquivo /etc/nova/nova.conf
echo "Configurando o arquivo /etc/nova/nova.conf..."
sudo bash -c 'cat <<EOF > /etc/nova/nova.conf
[DEFAULT]
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
my_ip = 192.168.1.22
transport_url = rabbit://openstack:admin@controller:5672/
[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = admin

[service_user]
send_service_user_token = true
#auth_url = https://controller/identity
auth_url = http://controller:5000/
auth_strategy = keystone
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = nova
password = admin

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = \$my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html

[glance]
api_servers = http://controller:9292

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = admin

[neutron]
auth_url = http://controller:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = admin
EOF'

# Verifica se a CPU suporta virtualização (Intel VT-x ou AMD-V)
if [[ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ]]; then
    echo "Virtualização não suportada pela CPU. Configurando o nova-compute para usar QEMU..."

    sudo bash -c 'cat <<EOF > /etc/nova/nova-compute.conf
[DEFAULT]
compute_driver=libvirt.LibvirtDriver
[libvirt]
virt_type=qemu
EOF'

    echo "Configuração concluída. O OpenStack Nova Compute agora usará QEMU como backend."
else
    echo "A CPU suporta virtualização. Nenhuma alteração necessária."
fi

echo "reiniciando serviço do nova-compute"
sudo service nova-compute restart

echo "Instalando os pacotes do Neutron..."
sudo apt install neutron-openvswitch-agent -y &>/dev/null

echo "Configurando o arquivo /etc/neutron/neutron.conf..."
sudo bash -c 'cat <<EOF > /etc/neutron/neutron.conf
[DEFAULT]
core_plugin = ml2
transport_url = rabbit://openstack:admin@controller

[agent]
root_helper = "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF'

echo "Configurando o arquivo /etc/neutron/plugins/ml2/openvswitch_agent.ini..."
sudo bash -c 'cat <<EOF > /etc/neutron/plugins/ml2/openvswitch_agent.ini
[ovs]
bridge_mappings = provider:br-provider
local_ip = 192.168.1.22

[agent]
tunnel_types = vxlan
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = openvswitch
EOF'

#####retornar para a config do controller
sudo ovs-vsctl add-br br-provider
sudo ovs-vsctl add-port br-provider enp0s8

echo "reiniciando serviços nova e neutron"
sudo service nova-compute restart
sudo service neutron-openvswitch-agent restart
echo "retornar para a configuração do controller, agora no Horizon"