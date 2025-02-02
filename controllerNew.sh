#!/bin/bash

source variaveis.sh

# Atualizar e atualizar o sistema
echo "Atualizando o sistema..."
sudo apt update &>/dev/null
sudo apt upgrade -y &>/dev/null

# Definir o nome do host como 'controller'
echo "Definindo o hostname como '${controller[0]}'..."
sudo hostnamectl set-hostname ${controller[0]}

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
            - ${controller[2]}
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
            - ${controller[1]}/24
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
allow $gerenciamento.0/24
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

# Instalar os pacotes necessários
echo "Instalando nova-compute e dependências..."
sudo apt install nova-compute -y &>/dev/null
echo "desabilitando apenas o serviço do nova-compute..."
sudo systemctl disable --now nova-compute
echo "Instalando python3-openstackclient..."
sudo apt install python3-openstackclient -y &>/dev/null
echo "Instalando mariadb-server python3-pymysql..."
sudo apt install mariadb-server python3-pymysql -y &>/dev/null

# Configuração do MariaDB
echo "Configurando o MariaDB..."
sudo bash -c "cat <<EOF > /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = ${controller[1]}
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF"

# Reiniciar o serviço MariaDB
echo "Reiniciando o serviço MariaDB..."
sudo service mysql restart


# Instalar o RabbitMQ
echo "Instalando o RabbitMQ..."
sudo apt install rabbitmq-server -y &>/dev/null

# Configurar o RabbitMQ
echo "Configurando o RabbitMQ..."
sudo rabbitmqctl add_user openstack $senha
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# Instalar o Memcached
echo "Instalando o Memcached..."
sudo apt install memcached python3-memcache -y &>/dev/null

# Configurar o Memcached
echo "Configurando o Memcached..."
sudo bash -c "cat <<EOF > /etc/memcached.conf
-d
logfile /var/log/memcached.log
-m 64
-p 11211
-u memcache
-l ${controller[1]}
-P /var/run/memcached/memcached.pid
EOF"

# Reiniciar o serviço Memcached
echo "Reiniciando o serviço Memcached..."
sudo service memcached restart

# Instalar o etcd
echo "Instalando o etcd..."
sudo apt install etcd -y &>/dev/null

# Configurar o etcd
echo "Configurando o etcd..."
sudo bash -c "cat <<EOF > /etc/default/etcd
ETCD_NAME="${controller[0]}"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="${controller[0]}=http://${controller[1]}:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${controller[1]}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${controller[1]}:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://${controller[1]}:2379"
EOF"


# Habilitar e reiniciar o serviço etcd
echo "Habilitando e reiniciando o serviço etcd..."
sudo systemctl enable etcd
sudo systemctl restart etcd

# Configuração do banco de dados MySQL
echo "Configuração do banco de dados MySQL para o Keystone..."
sudo mysql <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$senha';
EOF

# Instalar o Keystone
echo "Instalando o Keystone..."
sudo apt install keystone -y &>/dev/null

# Configuração do Keystone
echo "Configurando o arquivo /etc/keystone/keystone.conf..."
sudo bash -c "cat <<EOF > /etc/keystone/keystone.conf
[DEFAULT]
log_dir = /var/log/keystone
[database]
connection = mysql+pymysql://keystone:$senha@${controller[0]}/keystone
[token]
provider = fernet
EOF"

# Sincronizar o banco de dados do Keystone
echo "Sincronizando o banco de dados do Keystone..."
sudo keystone-manage db_sync

# Configurar o Fernet para o Keystone
echo "Configurando o Fernet para o Keystone..."
sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

# Configurar as credenciais do Keystone
echo "Configurando as credenciais do Keystone..."
sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# Realizar o bootstrap do Keystone
echo "Realizando o bootstrap do Keystone..."
sudo keystone-manage bootstrap --bootstrap-password $senha \
  --bootstrap-admin-url http://${controller[0]}:5000/v3/ \
  --bootstrap-internal-url http://${controller[0]}:5000/v3/ \
  --bootstrap-public-url http://${controller[0]}:5000/v3/ \
  --bootstrap-region-id RegionOne

# Configuração do Apache para o Keystone
echo "Configurando o Apache para o Keystone..."

sudo tee /etc/apache2/apache2.conf > /dev/null <<EOF
DefaultRuntimeDir \${APACHE_RUN_DIR}

PidFile \${APACHE_PID_FILE}

Timeout 300

KeepAlive On

MaxKeepAliveRequests 100

ServerName ${controller[0]}

KeepAliveTimeout 5

User \${APACHE_RUN_USER}

Group \${APACHE_RUN_GROUP}

HostnameLookups Off

ErrorLog \${APACHE_LOG_DIR}/error.log

LogLevel warn

IncludeOptional mods-enabled/*.load

IncludeOptional mods-enabled/*.conf

Include ports.conf

<Directory />
        Options FollowSymLinks
        AllowOverride None
        Require all denied
</Directory>

<Directory /usr/share>
        AllowOverride None
        Require all granted
</Directory>

<Directory /var/www/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
</Directory>

AccessFileName .htaccess

<FilesMatch "^\.ht">
        Require all denied
</FilesMatch>

LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined

LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined

LogFormat "%h %l %u %t \"%r\" %>s %O" common

LogFormat "%{Referer}i -> %U" referer

LogFormat "%{User-agent}i" agent

IncludeOptional conf-enabled/*.conf

IncludeOptional sites-enabled/*.conf
EOF


# Reiniciar o Apache
echo "Reiniciando o Apache..."
sudo service apache2 restart

# Configurar as variáveis de ambiente
echo "Configurando variáveis de ambiente..."
export OS_USERNAME=admin
export OS_PASSWORD=$senha
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://${controller[0]}:5000/v3
export OS_IDENTITY_API_VERSION=3

# Criar projetos e usuários no OpenStack
echo "Criando projetos e usuários..."
openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Demo Project" myproject
openstack user create --domain default --password "$senha" myuser
openstack role create myrole
openstack role add --project myproject --user myuser myrole

# Desconfigurar variáveis de ambiente
#echo "Desconfigurando variáveis de ambiente..."
#unset OS_AUTH_URL OS_PASSWORD

# Obter o token de administrador
echo "Obtendo o token de administrador..."
openstack --os-auth-url http://${controller[0]}:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name admin --os-username admin token issue

# Obter o token do usuário demo
echo "Obtendo o token do usuário demo..."
openstack --os-auth-url http://${controller[0]}:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name myproject --os-username myuser token issue

# Criar arquivos admin-openrc e demo-openrc
echo "Criando arquivos admin-openrc e demo-openrc..."
echo "export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$senha
export OS_AUTH_URL=http://${controller[0]}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2" | sudo tee admin-openrc

echo "export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=myproject
export OS_USERNAME=myuser
export OS_PASSWORD=$senha
export OS_AUTH_URL=http://${controller[0]}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2" | sudo tee demo-openrc

# Carregar o arquivo admin-openrc e obter o token
echo "Carregando admin-openrc e obtendo o token..."
. admin-openrc
openstack token issue


# Configuração do banco de dados MySQL para o Glance
echo "Configurando o banco de dados MySQL para o Glance..."
sudo mysql <<EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$senha';
EOF

# Definir variáveis de ambiente para o OpenStack
echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

# Criar o usuário Glance e atribuir permissões
echo "Criando usuário Glance e atribuindo permissões..."
openstack user create --domain default --password "$senha" glance
openstack role add --project service --user glance admin

# Criar o serviço Glance
echo "Criando serviço Glance..."
openstack service create --name glance --description "OpenStack Image" image

# Criar os endpoints de imagem
echo "Criando endpoints de imagem..."
openstack endpoint create --region RegionOne image public http://${controller[0]}:9292
openstack endpoint create --region RegionOne image internal http://${controller[0]}:9292
openstack endpoint create --region RegionOne image admin http://${controller[0]}:9292

# Instalar o Glance
echo "Instalando o Glance..."
sudo apt install glance -y &>/dev/null

# Configuração do arquivo glance-api.conf
echo "Configurando o arquivo /etc/glance/glance-api.conf..."
sudo bash -c "cat <<EOF > /etc/glance/glance-api.conf
[DEFAULT]
enabled_backends=fs:file
[database]
connection = mysql+pymysql://glance:$senha@${controller[0]}/glance
[keystone_authtoken]
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $senha
[paste_deploy]
flavor = keystone
[glance_store]
default_backend = fs
[fs]
filesystem_store_datadir = /var/lib/glance/images/
[oslo_limit]
auth_url = http://${controller[0]}:5000
auth_type = password
user_domain_id = default
username = glance
system_scope = all
password = $senha
endpoint_id = 
region_name = RegionOne
EOF"

# Obter o ID do endpoint público de imagem
echo "Obtendo o ID do endpoint público de imagem..."
public_image_endpoint_id=$(openstack endpoint list --service image --interface public -f value -c ID)

# Atualizar o arquivo de configuração com o ID do endpoint público
echo "Atualizando a configuração do Glance com o ID do endpoint público..."
sudo sed -i "s|endpoint_id = |endpoint_id = $public_image_endpoint_id|g" /etc/glance/glance-api.conf

# Adicionar a role "reader" ao usuário Glance
echo "Adicionando a role 'reader' ao usuário Glance..."
openstack role add --user glance --user-domain Default --system all reader

# Sincronizar o banco de dados do Glance
echo "Sincronizando o banco de dados do Glance..."
sudo glance-manage db_sync

# Reiniciar o serviço Glance API
echo "Reiniciando o serviço Glance API..."
sudo service glance-api restart

# Carregar novamente variáveis de ambiente
. admin-openrc

# Baixar a imagem Cirros e registrar no Glance
echo "Baixando e registrando a imagem Cirros..."
sudo wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img &>/dev/null
glance image-create --name "cirros" --file cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --visibility=public

# Listar as imagens no Glance
echo "Listando imagens registradas no Glance..."
glance image-list

# Configuração do banco de dados MySQL para o Placement
echo "Configurando o banco de dados MySQL para o Placement..."
sudo mysql <<EOF
CREATE DATABASE placement;
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$senha';
EOF

# Carregar variáveis de ambiente do OpenStack
echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

# Criar o usuário Placement e atribuir permissões
echo "Criando usuário Placement e atribuindo permissões..."
openstack user create --domain default --password "$senha" placement
openstack role add --project service --user placement admin

# Criar o serviço Placement
echo "Criando serviço Placement..."
openstack service create --name placement --description "Placement API" placement

# Criar os endpoints do Placement
echo "Criando endpoints do Placement..."
openstack endpoint create --region RegionOne placement public http://${controller[0]}:8778
openstack endpoint create --region RegionOne placement internal http://${controller[0]}:8778
openstack endpoint create --region RegionOne placement $senha http://${controller[0]}:8778

# Instalar o serviço Placement API
echo "Instalando o serviço Placement API..."
sudo apt install placement-api -y &>/dev/null

# Configuração do arquivo /etc/placement/placement.conf
echo "Configurando o arquivo /etc/placement/placement.conf..."
sudo bash -c "cat <<EOF > /etc/placement/placement.conf
[placement_database]
connection = mysql+pymysql://placement:$senha@${controller[0]}/placement
[api]
auth_strategy = keystone
[keystone_authtoken]
auth_url = http://${controller[0]}:5000/v3
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = $senha
EOF"

# Sincronizar o banco de dados do Placement
echo "Sincronizando o banco de dados do Placement..."
sudo placement-manage db sync

# Reiniciar o serviço Apache para o Placement
echo "Reiniciando o serviço Apache..."
sudo service apache2 restart

# Verificar a atualização do Placement
echo "Verificando o status do Placement..."
. admin-openrc
sudo placement-status upgrade check

# Listar os recursos e traits
echo "Listando classes de recursos..."
openstack --os-placement-api-version 1.2 resource class list --sort-column name

echo "Listando traits..."
openstack --os-placement-api-version 1.6 trait list --sort-column name

#!/bin/bash

# Configuração do banco de dados MySQL para o Nova
echo "Configurando o banco de dados MySQL para o Nova..."
sudo mysql <<EOF
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$senha';
EOF

# Carregar variáveis de ambiente do OpenStack
echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

# Criar o usuário Nova e atribuir permissões
echo "Criando usuário Nova e atribuindo permissões..."
openstack user create --domain default --password "$senha" nova
openstack role add --project service --user nova admin

# Criar o serviço Nova
echo "Criando serviço Nova..."
openstack service create --name nova --description "OpenStack Compute" compute

# Criar os endpoints do Nova
echo "Criando endpoints do Nova..."
openstack endpoint create --region RegionOne compute public http://${controller[0]}:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://${controller[0]}:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://${controller[0]}:8774/v2.1

# Instalar os pacotes do Nova
echo "Instalando os pacotes do Nova..."
sudo apt install nova-api nova-conductor nova-novncproxy nova-scheduler -y &>/dev/null

# Configuração do arquivo /etc/nova/nova.conf
echo "Configurando o arquivo /etc/nova/nova.conf..."
sudo bash -c "cat <<EOF > /etc/nova/nova.conf
[DEFAULT]
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
my_ip = ${controller[1]}
transport_url = rabbit://openstack:$senha@${controller[0]}:5672/
[api_database]
connection = mysql+pymysql://nova:$senha@${controller[0]}/nova_api
[database]
connection = mysql+pymysql://nova:$senha@${controller[0]}/nova
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
[neutron]
auth_url = http://${controller[0]}:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = $senha
service_metadata_proxy = true
metadata_proxy_shared_secret = $senha
[service_user]
send_service_user_token = true
auth_url = http://${controller[0]}:5000/identity
auth_strategy = keystone
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = nova
password = $senha
[vnc]
enabled = true
server_listen = ${controller[1]}
server_proxyclient_address = ${controller[1]}
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
[cinder]
os_region_name = RegionOne
[cells]
enable = False
[os_region_name]
openstack =
EOF"

# Sincronizar o banco de dados da API Nova
echo "Sincronizando o banco de dados da API Nova..."
sudo nova-manage api_db sync

# Criar e mapear células
echo "Criando e mapeando células do Nova..."
sudo nova-manage cell_v2 map_cell0
sudo nova-manage cell_v2 create_cell --name=cell1 --verbose

# Sincronizar o banco de dados do Nova
echo "Sincronizando o banco de dados do Nova..."
sudo nova-manage db sync

# Listar células
echo "Listando as células do Nova..."
sudo nova-manage cell_v2 list_cells

# Reiniciar os serviços do Nova
echo "Reiniciando os serviços do Nova..."
sudo service nova-api restart
sudo service nova-scheduler restart
sudo service nova-conductor restart
sudo service nova-novncproxy restart


echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc
sudo nova-manage cell_v2 discover_hosts --verbose

echo "verificar funcionamento"
openstack compute service list
openstack catalog list
openstack image list
sudo nova-status upgrade check

echo "Configurando o banco de dados MySQL para o Neutron..."
sudo mysql <<EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$senha';
EOF

echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

echo "Criando usuário Neutron e atribuindo permissões..."
openstack user create --domain default --password "$senha" neutron
openstack role add --project service --user neutron admin

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
service_plugins = router
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

echo "Sincronizando o banco de dados Neutron e arquivos de conf..."
sudo neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head

echo "Reiniciando 0 serviço do NOVA API..."
sudo service nova-api restart

echo "Reiniciando os serviços do Neutron..."
sudo service neutron-server restart
sudo service neutron-openvswitch-agent restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-l3-agent restart

echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

echo "Verificando extensões de rede e agentes de rede do OpenStack..."
openstack extension list --network
openstack network agent list

echo "Instalando o Horizon (OpenStack Dashboard)..."
sudo apt install openstack-dashboard -y &>/dev/null

echo "Configurando o arquivo /etc/openstack-dashboard/local_settings.py..."
sudo bash -c "cat <<EOF > /etc/openstack-dashboard/local_settings.py
import os
from django.utils.translation import gettext_lazy as _
from horizon.utils import secret_key
from openstack_dashboard.settings import HORIZON_CONFIG

DEBUG = False

LOCAL_PATH = os.path.dirname(os.path.abspath(__file__))

SECRET_KEY = secret_key.generate_or_read_from_file(\"/var/lib/openstack-dashboard/secret_key\")

CACHES = {
    \"default\": {
        \"BACKEND\": \"django.core.cache.backends.memcached.PyMemcacheCache\",
        \"LOCATION\": \"${controller[1]}:11211\",
    },
}

EMAIL_BACKEND = \"django.core.mail.backends.console.EmailBackend\"

OPENSTACK_HOST = \"${controller[1]}\"
OPENSTACK_KEYSTONE_URL = \"http://%s:5000/identity/v3\" % OPENSTACK_HOST
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_API_VERSIONS = {
    \"identity\": 3,
    \"image\": 2,
    \"volume\": 3,
}
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"Default\"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"
OPENSTACK_NEUTRON_NETWORK = {
    \"enable_router\": True,
    \"enable_quotas\": True,
    \"enable_ipv6\": False,
    \"enable_distributed_router\": False,
    \"enable_ha_router\": False,
    \"enable_fip_topology_check\": True,
}
TIME_ZONE = \"UTC\"

LOGGING = {
    \"version\": 1,
    \"disable_existing_loggers\": False,
    \"formatters\": {
        \"console\": {
            \"format\": \"%(levelname)s %(name)s %(message)s\"
        },
        \"operation\": {
            \"format\": \"%(message)s\"
        },
    },
    \"handlers\": {
        \"null\": {
            \"level\": \"DEBUG\",
            \"class\": \"logging.NullHandler\",
        },
        \"console\": {
            \"level\": \"DEBUG\" if DEBUG else \"INFO\",
            \"class\": \"logging.StreamHandler\",
            \"formatter\": \"console\",
        },
        \"operation\": {
            \"level\": \"INFO\",
            \"class\": \"logging.StreamHandler\",
            \"formatter\": \"operation\",
        },
    },
    \"loggers\": {
        \"horizon\": {
            \"handlers\": [\"console\"],
            \"level\": \"DEBUG\",
            \"propagate\": False,
        },
        \"openstack_dashboard\": {
            \"handlers\": [\"console\"],
            \"level\": \"DEBUG\",
            \"propagate\": False,
        },
    },
}

SECURITY_GROUP_RULES = {
    \"all_tcp\": {
        \"name\": _(\"All TCP\"),
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"1\",
        \"to_port\": \"65535\",
    },
    \"ssh\": {
        \"name\": \"SSH\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"22\",
        \"to_port\": \"22\",
    },
    \"http\": {
        \"name\": \"HTTP\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"80\",
        \"to_port\": \"80\",
    },
    \"https\": {
        \"name\": \"HTTPS\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"443\",
        \"to_port\": \"443\",
    },
    \"mysql\": {
        \"name\": \"MYSQL\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"3306\",
        \"to_port\": \"3306\",
    },
}

DEFAULT_THEME = \"default\"
WEBROOT = \"/horizon/\"
ALLOWED_HOSTS = [\"*\"]
COMPRESS_OFFLINE = False
EOF"

echo "Reiniciando serviço do Apache..."
sudo systemctl reload apache2

echo "Configuração do Horizon concluída com sucesso."
#!/bin/bash

echo "configuração do banco de dados para o cinder"
sudo mysql <<EOF
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$senha';
EOF

echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

echo "Criando usuário Cinder e atribuindo permissões..."
openstack user create --domain default --password "$senha" cinder
openstack role add --project service --user cinder admin
echo "criando serviço de storage do Cinder"
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3

echo "criando endpoints do Cinder"
openstack endpoint create --region RegionOne volumev3 public http://${controller[0]}:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://${controller[0]}:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://${controller[0]}:8776/v3/%\(project_id\)s

echo "instalando Cinder"
sudo apt install cinder-api cinder-scheduler -y &>/dev/null

echo "configurando o arquivo "
sudo bash -c "cat <<EOF > /etc/cinder/cinder.conf
[DEFAULT]
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = lioadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
auth_strategy = keystone
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes
enabled_backends = lvm
transport_url = rabbit://openstack:$senha@${controller[0]}
my_ip = ${controller[1]}

[database]
connection = mysql+pymysql://cinder:$senha@${controller[0]}/cinder

[keystone_authtoken]
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = admin

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF"

echo "sincronizando banco de dados Cinder"
sudo cinder-manage db sync

echo "reiniciando o serviço do NOVA-API"
sudo service nova-api restart

echo "reiniciando serviços do Cinder e apache/keystone"
sudo service cinder-scheduler restart
sudo service apache2 restart

echo "configuração do Cinder finalizada"
echo "configurar o nó de storage"
##fazer a parte do storage e quando terminar voltar aqui