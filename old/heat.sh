#!/bin/bash

#carrega as variáveis
source variaveis.sh
source admin-openrc

#echo "forçando instalação do python-zaqarclient==2.7.0..."
#sudo python3 -m pip install python-zaqarclient==2.7.0 --break-system-packages &>/dev/null
#echo "travando a versão instalada do python3-zaqarClient..."
#sudo apt-mark hold python3-zaqarclient &>/dev/null

# Configuração do banco de dados MySQL
echo "Configuração do banco de dados MySQL para o Heat..."
sudo mysql <<EOF
CREATE DATABASE heat;
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY '$senha';
EOF

# criar usuário heat para openstack
echo "criar usuário heat para openstack..."
openstack user create --domain default --password $senha heat

# adicionar a role do usuario heat
echo "adicionar a role do usuario heat..."
openstack role add --project service --user heat admin


# criando serviços heat e heat-cfn
echo "criando serviços heat e heat-cfn..."
openstack service create --name heat --description "Orchestration" orchestration
openstack service create --name heat-cfn --description "Orchestration"  cloudformation

# criando os endpoints do heat
echo "criando os endpoints do heat..."
openstack endpoint create --region RegionOne orchestration public http://${controller[0]}:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration internal http://${controller[0]}:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne orchestration admin http://${controller[0]}:8004/v1/%\(tenant_id\)s
openstack endpoint create --region RegionOne cloudformation public http://${controller[0]}:8000/v1
openstack endpoint create --region RegionOne cloudformation internal http://${controller[0]}:8000/v1
openstack endpoint create --region RegionOne cloudformation admin http://${controller[0]}:8000/v1

# criando o dominio que contém projetos e usuários do heat
echo "criando o dominio que contém projetos e usuários do heat..."
openstack domain create --description "Stack projects and users" heat

# criando o heat_domain_admin
echo "criando o heat_domain_admin..."
openstack user create --domain heat --password $senha heat_domain_admin


openstack role add --domain heat --user-domain heat --user heat_domain_admin admin

# criando heat_stack_owner role
echo "criando heat_stack_owner role.."
openstack role create heat_stack_owner

# criando heat_stack_user role
echo "criando heat_stack_user role..."
openstack role create heat_stack_user

# instalando os pacotes necessários
echo "instalando os pacotes necessários..."
sudo apt install heat-api heat-api-cfn heat-engine -y &>/dev/null

sudo bash -c "cat <<EOF > /etc/heat/heat.conf
[DEFAULT]
transport_url = rabbit://openstack:$senha@${controller[0]}
heat_metadata_server_url = http://${controller[0]}:8000
heat_waitcondition_server_url = http://${controller[0]}:8000/v1/waitcondition
stack_domain_admin = heat_domain_admin
stack_domain_admin_password = $senha
stack_user_domain_name = heat
[database]
connection = mysql+pymysql://heat:$senha@${controller[0]}/heat
[keystone_authtoken]
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = heat
password = $senha
[trustee]
auth_type = password
auth_url = http://${controller[0]}:5000
username = heat
password = $senha
user_domain_name = Default
[clients_keystone]
auth_uri = http://${controller[0]}:5000
EOF"

sudo -u heat /bin/sh -c "heat-manage db_sync" 

sudo systemctl restart heat-api heat-api-cfn heat-engine

source admin-openrc
openstack orchestration service list

# instalando o heat no dashboard
echo "instalando o heat no dashboard..."
sudo apt install python3-heat-dashboard -y &>/dev/null

sudo python3 -m pip install python-zaqarclient==2.7.0 --break-system-packages &>/dev/null
sudo apt-mark hold python3-zaqarclient &>/dev/null

# reiniciando o apache
echo "reiniciando o apache2..."
sudo systemctl restart apache2

