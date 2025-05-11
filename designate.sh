#!/bin/bash

#carrega as variáveis
source variaveis.sh

# Configuração do banco de dados MySQL
echo "Configuração do banco de dados MySQL para o Designate..."
sudo mysql <<EOF
CREATE DATABASE designate CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON designate.* TO 'designate'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON designate.* TO 'designate'@'%' IDENTIFIED BY '$senha';
EOF

# criar usuário designate para openstack
echo "criar usuário designate para openstack..."
openstack user create --domain default --password $senha designate

# adicionar a role do usuario designate
echo "adicionar a role do usuario designate..."
openstack role add --project service --user designate admin

#  criando serviço dns
echo "criando serviço dns"
openstack service create --name designate --description "DNS" dns

# criando endpoints
echo "criando endpoints dns"
openstack endpoint create --region RegionOne dns public http://${controller[0]}:9001/
openstack endpoint create --region RegionOne dns internal http://${controller[0]}:9001/
openstack endpoint create --region RegionOne dns admin http://${controller[0]}:9001/

# instalando o designate e bind9
echo "Instalando o designate e bind9..."
sudo apt install designate bind9 bind9utils bind9-doc -y &>/dev/null

# criando rndc key
echo "criando rndc key..."
rndc-confgen -a -k designate -c /etc/bind/rndc.key

# criando arquivo named.conf.options
"criando arquivo named.conf.options..."
sudo bash -c "cat <<EOF > /etc/bind/named.conf.options
include \"/etc/bind/rndc.key\";

controls {
    inet 127.0.0.1 port 953
        allow { 127.0.0.1; } keys { \"designate\"; };
};

options {
    directory \"/var/cache/bind\";

    // Permitir criação de zonas dinamicamente
    allow-new-zones yes;
    request-ixfr no;

    // DNSSEC
    dnssec-validation auto;

    // Interface de escuta (ajustada para Designate)
    listen-on port 53 { 127.0.0.1; };
    listen-on-v6 { any; };

    // Permitir consultas apenas do localhost
    recursion no;
    allow-query { 127.0.0.1; };
};
EOF"

# configurando o arquivo /etc/bind/named.conf.options

echo "configurando o arquivo /etc/bind/named.conf.options..."
sudo bash -c "cat <<EOF > /etc/bind/named.conf.options
include \"/etc/bind/rndc.key\";

options {
    allow-new-zones yes;
    request-ixfr no;
    listen-on port 53 { 127.0.0.1; };
    recursion no;
    allow-query { 127.0.0.1; };
};

controls {
  inet 127.0.0.1 port 953
    allow { 127.0.0.1; } keys { \"designate\"; };
};
EOF"

sudo bash -c "cat <<EOF > /etc/designate/designate.conf
[DEFAULT]
transport_url = rabbit://openstack:$senha@controller:5672/
storage-driver = sqlalchemy
auth_strategy = keystone
[keystone_authtoken]
auth_type = password
username = designate
password = admin
project_name = service
project_domain_name = Default
user_domain_name = Default
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
[service:api]
listen = 0.0.0.0:9001
auth_strategy = keystone
enable_api_v2 = True
enable_api_admin = True
enable_host_header = True
enabled_extensions_admin = quotas, reports
[storage:sqlalchemy]
connection = mysql+pymysql://designate:admin@controller/designate
EOF"

# criar o designate

sudo bash -c "cat <<EOF > /etc/designate/designate.conf
[DEFAULT]
transport_url = rabbit://openstack:admin@controller:5672/
storage-driver = sqlalchemy
auth_strategy = keystone
[keystone_authtoken]
auth_type = password
username = designate
password = admin
project_name = service
project_domain_name = Default
user_domain_name = Default
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
[service:api]
listen = 0.0.0.0:9001
auth_strategy = keystone
enable_api_v2 = True
enable_api_admin = True
enable_host_header = True
enabled_extensions_admin = quotas, reports
[storage:sqlalchemy]
connection = mysql+pymysql://designate:admin@controller/designate
[oslo_policy]
policy_file = /etc/designate/policy.yaml

EOF"