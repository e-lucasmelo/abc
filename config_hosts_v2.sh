#!/bin/bash

source variaveis.sh


# Função que usa indireção para acessar o array correto
ip_gerencia(){
    # Variável indireta para pegar o array correto
    local array_name="$host"  # O nome do host
    eval "echo \${$array_name[@]}"  # Retorna toda a lista do array correspondente ao nome do host
}

host_array=($(ip_gerencia))
host_temp=$(echo "$host" | sed 's/[0-9]*$//')

if [ $host_temp = "storage" ]; then
if [ -b /dev/$disk_storage ]; then
    echo "/dev/$disk_storage existe, vamos seguir a configuração..."
else
    echo "/dev/$disk_storage não existe, por favor adicione o disk e tente novamente"
    exit 1
fi
else
echo "host não é de storage, vamos seguir a configuração..."
fi

# Atualizar e atualizar o sistema
echo "Atualizando o sistema..."
sudo apt update &>/dev/null
sudo apt upgrade -y &>/dev/null

# Definir o nome do host como 'controller'
echo "Definindo o hostname como '${host_array[0]}'..."
sudo hostnamectl set-hostname ${host_array[0]}

echo "desativando NetworkManager..."
sudo systemctl disable --now NetworkManager
echo "ativando systemd-networkd"
sudo systemctl enable --now systemd-networkd

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
            - ${host_array[2]}
            dhcp6: false
            accept-ra: no
"
else
i=""
fi

if [ $rede_ger = "wifis" ]; then
x="            access-points:
                \"$rede_wifi\":
                    password: \"$senha_wifi\"
            dhcp6: false
            accept-ra: no
    ethernets:
"
else
x="            dhcp6: false
            accept-ra: no
"
fi

# Editar o arquivo de configuração de rede /etc/netplan/50-cloud-init.yaml
echo "Configurando rede no $arquivoNetplan..."
sudo bash -c "cat <<EOF > $arquivoNetplan
network:
    renderer: networkd
    $rede_ger:
        $interface_ger:
            addresses:
            - ${host_array[1]}/24
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
$x
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

# Testando a conexão de rede com 3 tentativas
echo "Testando a conexão de rede..."
tentativas=0
max_tentativas=3

while ! curl -s --connect-timeout 5 http://www.google.com --output /dev/null; do
    tentativas=$((tentativas + 1))
    
    if [ "$tentativas" -ge "$max_tentativas" ]; then
        echo "Falha na conexão após $max_tentativas tentativas. Encerrando o script."
        exit 1
    fi

    echo "Sem conexão. Tentativa $tentativas de $max_tentativas. Tentando novamente em 3 segundos..."
    sleep 3
done

echo "Conexão estabelecida com sucesso!"

# Instalar o Chrony e configurar o servidor NTP
echo "Instalando o Chrony..."
sudo apt install chrony -y &>/dev/null

if [ $host = "controller" ]; then
network="allow $ip_ger.0/24
pool ntp.ubuntu.com        iburst maxsources 4"
else
network=""
fi

# Configurar o arquivo de configuração do Chrony
echo "Configurando o arquivo /etc/chrony/chrony.conf..."
sudo bash -c "cat <<EOF > /etc/chrony/chrony.conf
server ${controller[0]} iburst
$network
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
echo "Instalando python3-openstackclient..."
sudo apt install python3-openstackclient -y &>/dev/null

if [ $host_temp = "storage" ]; then
echo "desabilitando apenas o serviço do nova-compute para o host ${host_array[0]}..."
sudo systemctl disable --now nova-compute

echo "instalação do LVM"
# Configurar LVM
sudo apt install lvm2 thin-provisioning-tools -y &>/dev/null
sudo pvcreate /dev/$disk_storage
sudo vgcreate cinder-volumes /dev/$disk_storage

echo "configuração do arquivo /etc/lvm/lvm.conf"
# Configurar LVM
sudo bash -c "cat <<EOF > /etc/lvm/lvm.conf
config {
        checks = 1
        abort_on_errors = 0
        profile_dir = \"/etc/lvm/profile\"
}
devices {
        dir = \"/dev\"
        scan = [ \"/dev\" ]
        filter = [ \"a/$disk_storage/\", \"r/.*/\"]
        obtain_device_list_from_udev = 1
        external_device_info_source = \"none\"
        sysfs_scan = 1
        scan_lvs = 0
        multipath_component_detection = 1
        md_component_detection = 1
        fw_raid_component_detection = 0
        md_chunk_alignment = 1
        data_alignment_detection = 1
        data_alignment = 0
        data_alignment_offset_detection = 1
        ignore_suspended_devices = 0
        ignore_lvm_mirrors = 1
        require_restorefile_with_uuid = 1
        pv_min_size = 2048
        issue_discards = 1
        allow_changes_with_duplicate_pvs = 0
        allow_mixed_block_sizes = 0
}

allocation {
        maximise_cling = 1
        use_blkid_wiping = 1
        wipe_signatures_when_zeroing_new_lvs = 1
        mirror_logs_require_separate_pvs = 0
}
log {
        verbose = 0
        silent = 0
        syslog = 1
        overwrite = 0
        level = 0
        command_names = 0
        prefix = \"  \"
        activation = 0
        debug_classes = [ \"memory\", \"devices\", \"io\", \"activation\", \"allocation\", \"metadata\", \"cache\", \"locking\", \"lvmpolld\", \"dbus\" ]
}
backup {
        backup = 1
        backup_dir = \"/etc/lvm/backup\"
        archive = 1
        archive_dir = \"/etc/lvm/archive\"
        retain_min = 10
        retain_days = 30
}
shell {
        history_size = 100
}
global {
        umask = 077
        test = 0
        units = \"r\"
        si_unit_consistency = 1
        suffix = 1
        activation = 1
        proc = \"/proc\"
        etc = \"/etc\"
        wait_for_locks = 1
        locking_dir = \"/run/lock/lvm\"
        prioritise_write_locks = 1
        abort_on_internal_errors = 0
        metadata_read_only = 0
        mirror_segtype_default = \"raid1\"
        raid10_segtype_default = \"raid10\"
        sparse_segtype_default = \"thin\"
        use_lvmlockd = 0
        system_id_source = \"none\"
        use_lvmpolld = 1
        notify_dbus = 1
}
activation {
        checks = 0
        udev_sync = 1
        udev_rules = 1
        retry_deactivation = 1
        missing_stripe_filler = \"error\"
        raid_region_size = 2048
        raid_fault_policy = \"warn\"
        mirror_image_fault_policy = \"remove\"
        mirror_log_fault_policy = \"allocate\"
        snapshot_autoextend_threshold = 100
        snapshot_autoextend_percent = 20
        thin_pool_autoextend_threshold = 100
        thin_pool_autoextend_percent = 20
        monitoring = 1
        activation_mode = \"degraded\"
}
dmeventd {
}
EOF"

echo "instalando Cinder"
# Instalar e configurar Cinder
sudo apt install cinder-volume tgt -y &>/dev/null

echo "configurando o arquivo /etc/cinder/cinder.conf... "

sudo bash -c "cat <<EOF > /etc/cinder/cinder.conf
[DEFAULT]
transport_url = rabbit://openstack:$senha@${controller[0]}
auth_strategy = keystone
my_ip = ${host_array[1]}
enabled_backends = lvm
glance_api_servers = http://${controller[0]}:9292
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = lioadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes

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
password = $senha

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = tgtadm

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF"

# Configurar tgt
echo "configuração do arquivo /etc/tgt/conf.d/cinder.conf"
sudo bash -c 'cat <<EOF > /etc/tgt/conf.d/cinder.conf
include /var/lib/cinder/volumes/*
EOF'

echo "reiniciar serviços"
# Reiniciar serviços
sudo service tgt restart
sudo service cinder-volume restart

echo "finalizado"
echo "faça a configuração de update do host controller"

fi



if [ $host_temp = "compute" ]; then
# Configuração do arquivo /etc/nova/nova.conf
echo "configuração apenas para o host compute"
echo "Configurando o arquivo /etc/nova/nova.conf..."
sudo bash -c "cat <<EOF > /etc/nova/nova.conf
[DEFAULT]
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
my_ip = ${host_array[1]}
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
server_proxyclient_address = ${host_array[1]}
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
echo "faça a configuração do host storage."
echo "Se não for utilizar o host storage, volte e faça a configuração de update do host controller"
fi



if [ $host = "controller" ]; then
echo "##### Configurações apenas para o controller #####"
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
sudo rabbitmqctl add_user openstack $senha &>/dev/null
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*" &>/dev/null

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
echo "Habilitando o serviço etcd..."
sudo systemctl enable etcd &>/dev/null
echo "Reiniciando o serviço etcd..."
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
#sudo keystone-manage db_sync
sudo -u keystone /bin/sh -c "keystone-manage db_sync"

# Configurar o Fernet para o Keystone
echo "Configurando o Fernet para o Keystone..."
sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

# Configurar as credenciais do Keystone
echo "Configurando as credenciais do Keystone..."
sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

# Realizar o bootstrap do Keystone
echo "Realizando o bootstrap do Keystone, criando usuario e endpoints..."
sudo keystone-manage bootstrap --bootstrap-password $senha \
  --bootstrap-admin-url http://${controller[0]}:5000/v3/ \
  --bootstrap-internal-url http://${controller[0]}:5000/v3/ \
  --bootstrap-public-url http://${controller[0]}:5000/v3/ \
  --bootstrap-region-id RegionOne


# echo "criando região..."
# openstack region create RegionOne
# echo "criando usuário admin no dominio default..."
# openstack user create --domain default --password $senha admin
# echo "adicionando o usuário admin para o projeto admin..."
# openstack role add --project admin --user admin admin
# echo "criando o serviço para o Keystone..."
# openstack service create --name keystone --description "OpenStack Identity" identity
# echo "criando endpoint admin..."
# openstack endpoint create --region RegionOne identity admin http://${controller[0]}:5000/v3/
# echo "criando endpoint internal..."
# openstack endpoint create --region RegionOne identity internal http://${controller[0]}:5000/v3/
# echo "criando endpoint public..."
# openstack endpoint create --region RegionOne identity public http://${controller[0]}:5000/v3/


# Configuração do Apache para o Keystone
echo "Configurando o arquivo /etc/apache2/apache2.conf..."

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
echo "Reiniciando o Apache/Keystone..."
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
echo "configurando projeto dos serviços..."
openstack project create --domain default --description "Service Project" service
# echo "configurando projeto de demo..."
# openstack project create --domain default --description "Demo Project" myproject
# echo "configurando usuário myuser ..."
# openstack user create --domain default --password "$senha" myuser
# echo "configurando a função de usuário myrole..."
# openstack role create myrole
# echo "configurando usuário myuser na função myrole..."
# openstack role add --project myproject --user myuser myrole

# Desconfigurar variáveis de ambiente
#echo "Desconfigurando variáveis de ambiente..."
#unset OS_AUTH_URL OS_PASSWORD

# Obter o token de administrador
echo "testando obtenção de token de administrador..."
openstack --os-auth-url http://${controller[0]}:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name admin --os-username admin token issue

# Obter o token do usuário demo
# echo "testando obtenção de token do usuário myrole..."
# openstack --os-auth-url http://${controller[0]}:5000/v3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name myproject --os-username myuser token issue

# Criar arquivos admin-openrc e demo-openrc
echo "Criando arquivos admin-openrc..."
echo "export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$senha
export OS_AUTH_URL=http://${controller[0]}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2" | sudo tee admin-openrc &>/dev/null

# echo "Criando arquivo demo-openrc..."
# echo "export OS_PROJECT_DOMAIN_NAME=Default
# export OS_USER_DOMAIN_NAME=Default
# export OS_PROJECT_NAME=myproject
# export OS_USERNAME=myuser
# export OS_PASSWORD=$senha
# export OS_AUTH_URL=http://${controller[0]}:5000/v3
# export OS_IDENTITY_API_VERSION=3
# export OS_IMAGE_API_VERSION=2" | sudo tee demo-openrc &>/dev/null

# Carregar o arquivo admin-openrc e obter o token
echo "Carregando admin-openrc e testando obtenção  do token..."
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
echo "Configurando usuário Glance ..."
openstack user create --domain default --password "$senha" glance
echo "configurando usuário Glance no projeto de serviço..."
openstack role add --project service --user glance admin

# Criar o serviço Glance
echo "Criando serviço Glance..."
openstack service create --name glance --description "OpenStack Image" image

# Criar os endpoints de imagem
echo "Criando endpoint public..."
openstack endpoint create --region RegionOne image public http://${controller[0]}:9292
echo "Criando endpoint internal..."
openstack endpoint create --region RegionOne image internal http://${controller[0]}:9292
echo "Criando endpoint admin..."
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
echo "Obtendo o ID do endpoint public de imagem..."
public_image_endpoint_id=$(openstack endpoint list --service image --interface public -f value -c ID)

# Atualizar o arquivo de configuração com o ID do endpoint público
echo "Atualizando a configuração do Glance com o ID do endpoint público..."
sudo sed -i "s|endpoint_id = |endpoint_id = $public_image_endpoint_id|g" /etc/glance/glance-api.conf

# Adicionar a role "reader" ao usuário Glance
echo "Adicionando a role 'reader' ao usuário Glance..."
openstack role add --user glance --user-domain Default --system all reader

# Sincronizar o banco de dados do Glance
echo "Sincronizando o banco de dados do Glance..."
#sudo glance-manage db_sync &>/dev/null
sudo -u glance /bin/sh -c "glance-manage db_sync" &>/dev/null

# Reiniciar o serviço Glance API
echo "Reiniciando o serviço Glance API..."
sudo service glance-api restart

# Carregar novamente variáveis de ambiente
echo "Carregando variáveis de ambiente do openstack..."
. admin-openrc

# Baixar a imagem Cirros e registrar no Glance
echo "Baixando imagem Cirros..."
sudo wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img &>/dev/null

echo "adicionando imagem Cirros no Glance"
glance image-create --name "cirros" --file cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --visibility=public

# Listar as imagens no Glance
# echo "Listando imagens registradas no Glance..."
# glance image-list

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
openstack endpoint create --region RegionOne placement admin http://${controller[0]}:8778

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
#sudo placement-manage db sync
sudo -u placement /bin/sh -c "placement-manage db sync" &>/dev/null
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

echo "Listando atributos..."
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
#sudo nova-manage api_db sync
sudo -u nova /bin/sh -c "nova-manage api_db sync" &>/dev/null

# Criar e mapear células
echo "Criando e mapeando células do Nova..."
# sudo nova-manage cell_v2 map_cell0
sudo -u nova /bin/sh -c "nova-manage cell_v2 map_cell0" &>/dev/null

# sudo nova-manage cell_v2 create_cell --name=cell1 --verbose
sudo -u nova /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" &>/dev/null

# Sincronizar o banco de dados do Nova
echo "Sincronizando o banco de dados do Nova..."
# sudo nova-manage db sync
sudo -u nova /bin/sh -c "nova-manage db sync" &>/dev/null

# Listar células
echo "Listando as células do Nova..."
# sudo nova-manage cell_v2 list_cells
sudo -u nova /bin/sh -c "nova-manage cell_v2 list_cells" &>/dev/null

# Reiniciar os serviços do Nova
echo "Reiniciando os serviços do Nova..."
sudo service nova-api restart
sudo service nova-scheduler restart
sudo service nova-conductor restart
sudo service nova-novncproxy restart

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
# sudo neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head &>/dev/null
sudo -u neutron /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" &>/dev/null

echo "Reiniciando o serviço do NOVA API..."
sudo service nova-api restart

echo "Reiniciando os serviços do Neutron..."
sudo service neutron-server restart
sudo service neutron-openvswitch-agent restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-l3-agent restart

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
# sudo cinder-manage db sync
sudo -u cinder /bin/sh -c "cinder-manage db sync"

echo "reiniciando o serviço do NOVA-API"
sudo service nova-api restart

echo "reiniciando serviços do Cinder e apache/keystone"
sudo service cinder-scheduler restart
sudo service apache2 restart

echo "configuração do Cinder finalizada"
# echo "configurar o nó de storage"
##fazer a parte do storage e quando terminar voltar aqui

echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

echo "verificando os hosts compute..."
sudo -u nova /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose"

echo "verificar a lista de serviços, catálogo e imagem"
openstack compute service list
openstack catalog list
openstack image list
sudo nova-status upgrade check

echo "Verificando extensões de rede e agentes de rede do Neutron..."
openstack extension list --network
openstack network agent list

echo "configuração concluída!"
echo "Faça a configuração do host compute."
fi