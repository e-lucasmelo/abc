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
rndc-confgen -a -k designate -c /etc/bind/rndc.key -y &>/dev/null

# criando arquivo named.conf.options
"criando arquivo /etc/bind/named.conf.options..."
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

# criar o designate.conf
echo "criando o /etc/designate/designate.conf..."
sudo bash -c "cat <<EOF > /etc/designate/designate.conf
[DEFAULT]
transport_url = rabbit://openstack:$senha@${controller[0]}:5672/
storage-driver = sqlalchemy
auth_strategy = keystone
[keystone_authtoken]
auth_type = password
username = designate
password = $senha
project_name = service
project_domain_name = Default
user_domain_name = Default
www_authenticate_uri = http://${controller[0]}:5000/
auth_url = http://${controller[0]}:5000/
memcached_servers = ${controller[0]}:11211
[service:api]
listen = 0.0.0.0:9001
auth_strategy = keystone
enable_api_v2 = True
enable_api_admin = True
enable_host_header = True
enabled_extensions_admin = quotas, reports
[storage:sqlalchemy]
connection = mysql+pymysql://designate:$senha@${controller[0]}/designate
[oslo_policy]
policy_file = /etc/designate/policy.yaml
EOF"

#criando o arquivo /etc/designate/policy.yaml
echo "criando o arquivo /etc/designate/policy.yaml..."
sudo bash -c "cat <<EOF > /etc/designate/policy.yaml
# Acesso básico (default)
\"default\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"

# Blacklists (admin only)
\"create_blacklist\": \"role:admin\"
\"find_blacklists\": \"role:admin\"
\"get_blacklist\": \"role:admin\"
\"update_blacklist\": \"role:admin\"
\"delete_blacklist\": \"role:admin\"
\"use_blacklisted_zone\": \"role:admin\"

# Pools (admin only)
\"create_pool\": \"role:admin\"
\"get_pool\": \"role:admin\"
\"find_pools\": \"role:admin\"
\"update_pool\": \"role:admin\"
\"delete_pool\": \"role:admin\"

# Zones (admin + member in same project)
\"create_zone\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"get_zone\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"find_zones\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"update_zone\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"delete_zone\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"

# Zone imports/exports (admin + member)
\"create_zone_import\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"get_zone_import\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"find_zone_imports\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"

\"create_zone_export\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"get_zone_export\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"find_zone_exports\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"

# Recordsets (admin + member)
\"create_recordset\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"get_recordset\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"find_recordsets\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"update_recordset\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"delete_recordset\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"

# Records (admin + member)
\"create_record\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"get_record\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"find_records\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"update_record\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"delete_record\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"

# Quotas (admin only)
\"get_quotas\": \"role:admin\"
\"set_quotas\": \"role:admin\"
\"reset_quotas\": \"role:admin\"

# Reports (admin only)
\"get_reports\": \"role:admin\"

# Floating IPs and PTRs (reverse DNS)
\"find_floatingips\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"get_floatingip\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"
\"set_floatingip\": \"(role:admin) or (role:member and project_id:%(project_id)s)\"

# All tenants flag
\"all_tenants\": \"role:admin\"
EOF"

# atualizando banco de dados do designate
echo  "atualizando banco de dados do designate..."
sudo -u designate /bin/sh -c "designate-manage database sync" &>/dev/null

# iniciando serviços do designate
echo "iniciando e habilitando no boot os serviços do designate"
sudo systemctl start designate-central designate-api &>/dev/null
sudo systemctl enable designate-central designate-api &>/dev/null

# criando o arquivo pools.yaml
echo "criando o arquivo /etc/designate/pools.yaml"
sudo bash -c "cat <<EOF > /etc/designate/pools.yaml
- name: default
  # The name is immutable. There will be no option to change the name after
  # creation and the only way will to change it will be to delete it
  # (and all zones associated with it) and recreate it.
  description: Default Pool

  attributes: {}

  # List out the NS records for zones hosted within this pool
  # This should be a record that is created outside of designate, that
  # points to the public IP of the controller node.
  ns_records:
    - hostname: ns1-1.example.org.
      priority: 1

  # List out the nameservers for this pool. These are the actual BIND servers.
  # We use these to verify changes have propagated to all nameservers.
  nameservers:
    - host: 127.0.0.1
      port: 53

  # List out the targets for this pool. For BIND there will be one
  # entry for each BIND server, as we have to run rndc command on each server
  targets:
    - type: bind9
      description: BIND9 Server 1

      # List out the designate-mdns servers from which BIND servers should
      # request zone transfers (AXFRs) from.
      # This should be the IP of the controller node.
      # If you have multiple controllers you can add multiple masters
      # by running designate-mdns on them, and adding them here.
      masters:
        - host: 127.0.0.1
          port: 5354

      # BIND Configuration options
      options:
        host: 127.0.0.1
        port: 53
        rndc_host: 127.0.0.1
        rndc_port: 953
        rndc_key_file: /etc/bind/rndc.key
EOF"

# atualização do banco de dados do designate pool
echo "atualizando o banco de dados do designate pool"
sudo -u designate /bin/sh -c "designate-manage pool update" &>/dev/null

# instalando o designate-worker designate-producer designate-mdns
echo "instalando o designate-worker designate-producer designate-mdns..."
sudo apt install designate-worker designate-producer designate-mdns -y &>/dev/null

# iniciando serviços designate-worker designate-producer designate-mdns
echo "iniciando e habilitando no boot os serviços designate-worker designate-producer designate-mdns..."
sudo systemctl start designate-worker designate-producer designate-mdns &>/dev/null
sudo systemctl enable designate-worker designate-producer designate-mdns &>/dev/null

# instalando o python3-designate-dashboard
echo "instalando o python3-designate-dashboard..."
sudo apt install python3-designate-dashboard -y &>/dev/null

# reiniciando o apache para o Horizon
echo "reiniciando apache para o Horizon"
sudo systemctl restart apache2 &>/dev/null

echo "configuração finalizada do designate"