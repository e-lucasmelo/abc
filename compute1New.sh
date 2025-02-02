#!/bin/bash

source variaveis.sh

# Atualizar e atualizar o sistema
echo "Atualizando o sistema..."
sudo apt update &>/dev/null
sudo apt upgrade -y &>/dev/null

# Definir o nome do host como 'compute1'
echo "Definindo o hostname como '${compute1[0]}'..."
sudo hostnamectl set-hostname ${compute1[0]}

# Editar o arquivo /etc/hosts
echo "Adicionando entradas no /etc/hosts..."
sudo bash -c "cat <<EOF > /etc/hosts
127.0.0.1	localhost
${controller[1]}	${controller[0]}
${compute1[1]}	${compute1[0]}
${compute2[1]}	${compute2[0]}
${compute3[1]}	${compute3[0]}
${storage1[1]}	${storage1[0]}
${storage2[1]}	${storage2[0]}
${storage3[1]}	${storage3[0]}
EOF"

if [ -n "$interfaceAdicional" ]; then
i="        $interfaceAdicional:
            addresses:
            - ${compute1[2]}
            dhcp6: false
            accept-ra: no
"
else
i=""
fi

# Editar o arquivo de configuração de rede /etc/netplan/50-cloud-init.yaml
echo "Configurando rede no $arquivoNetplan..."
sudo bash -c "cat <<EOF > $arquivoNetplan
network:
    ethernets:
        enp0s3:
            addresses:
            - ${compute1[1]}/24
            nameservers:
                addresses:
                - ${dns[0]}
                - ${dns[1]}
                search: []
            routes:
            -   to: default
                via: $gateway_gerencia
                metric: 100
            -   to: ${dns[0]}
                via: $gateway_gerencia
                metric: 100
            -   to: ${dns[1]}
                via: $gateway_gerencia
                metric: 100
            dhcp6: false
            accept-ra: no
        enp0s8:
            dhcp4: false
            dhcp6: false
            accept-ra: no
$i
    version: 2
EOF"


# Configurar o fuso horário para America/Sao_Paulo
echo "Configurando o fuso horário para America/Sao_Paulo..."
sudo timedatectl set-timezone America/Sao_Paulo

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
sudo bash -c "cat <<EOF > /etc/chrony/chrony.conf
server ${controller[0]} iburst
confdir /etc/chrony/conf.d
pool ntp.ubuntu.com        iburst maxsources 4
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
EOF"

# Reiniciar o serviço Chrony
echo "Reiniciando o serviço Chrony..."
sudo service chrony restart

# Verificar as fontes do Chrony
echo "Verificando fontes do Chrony..."
sudo chronyc sources

# Adicionar o repositório do OpenStack Caracal
echo "Adicionando o repositório do OpenStack Caracal..."
sudo add-apt-repository -y cloud-archive:caracal &>/dev/null

echo "Instalando nova-compute..."
sudo apt install nova-compute -y &>/dev/null
echo "Instalando python3-openstackclient..."
sudo apt install python3-openstackclient -y &>/dev/null

# Configuração do arquivo /etc/nova/nova.conf
echo "Configurando o arquivo /etc/nova/nova.conf..."
sudo bash -c "cat <<EOF > /etc/nova/nova.conf
[DEFAULT]
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
my_ip = ${compute1[1]}
transport_url = rabbit://openstack:$senha@${controller[0]}:5672/
[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://${controller[0]}:5000/
auth_url = http://${controller[0]}:5000/
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = $senha

[service_user]
send_service_user_token = true
#auth_url = https://${controller[0]}/identity
auth_url = http://${controller[0]}:5000/
auth_strategy = keystone
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = nova
password = $senha

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = ${compute1[1]}
novncproxy_base_url = http://${controller[0]}:6080/vnc_auto.html

[glance]
api_servers = http://${controller[0]}:9292

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://${controller[0]}:5000/v3
username = placement
password = $senha

[neutron]
auth_url = http://${controller[0]}:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = $senha
EOF"

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
local_ip = ${compute1[1]}

[agent]
tunnel_types = vxlan
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = openvswitch
EOF"

#####retornar para a config do controller
sudo ovs-vsctl add-br br-provider
sudo ovs-vsctl add-port br-provider $interfaceProvider
echo "reiniciando serviços nova e neutron"
sudo service nova-compute restart
sudo service neutron-openvswitch-agent restart
echo "retornar para a configuração do ${controller[0]}, agora no Horizon"