#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

if [ $host_temp = "block" ] || [ $host_temp = "object" ]; then
echo "desabilitando apenas o serviço do nova-compute para o host ${host_array[0]}..."
sudo systemctl disable --now nova-compute
fi

if [ $host_temp = "compute" ]; then
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
service_token_roles = service
service_token_roles_required = true
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = $senha

[service_user]
send_service_user_token = true
auth_url = http://${controller[0]}:5000
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
#auth_url = http://${controller[0]}:5000/v3
auth_url = http://${controller[0]}:5000
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

    echo "Configuração concluída. O Nova Compute usará QEMU como backend."
else
    echo "A CPU suporta virtualização. Nenhuma alteração necessária."
fi

echo "reiniciando serviço do nova-compute"
sudo service nova-compute restart

fi


if [ $host_temp = "controller" ]; then
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
FLUSH PRIVILEGES;
EOF

# Carregar variáveis de ambiente do OpenStack
echo "Carregando variáveis de ambiente do OpenStack..."
source "$SCRIPT_DIR/admin-openrc"

# Criar o usuário Nova e atribuir permissões
echo "Criando usuário Nova e atribuindo permissões..."
openstack user create --domain default --password "$senha" nova
openstack role add --project service --user nova admin
openstack role add --project service --user nova service


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
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
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
#linha comentada para o compute no controller
#auth_url = http://${controller[0]}:5000/identity
#nova_linha para o compute no controller
#auth_url = http://${controller[0]}:5000/
auth_url = http://${controller[0]}:5000
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
#nova_linha para o compute no controller
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
#auth_url = http://${controller[0]}:5000/v3
auth_url = http://${controller[0]}:5000
username = placement
password = $senha
[cinder]
os_region_name = RegionOne
[cells]
enable = False
[os_region_name]
openstack =
EOF"

# nova verificação do compute no controller
# Verifica se a CPU suporta virtualização (Intel VT-x ou AMD-V)
if [[ $(egrep -c '(vmx|svm)' /proc/cpuinfo) -eq 0 ]]; then
    echo "Virtualização não suportada pela CPU. Configurando o nova-compute para usar QEMU..."

    sudo bash -c 'cat <<EOF > /etc/nova/nova-compute.conf
[DEFAULT]
compute_driver=libvirt.LibvirtDriver
[libvirt]
virt_type=qemu
EOF'

    echo "Configuração concluída. O Nova Compute usará QEMU como backend."
else
    echo "A CPU suporta virtualização. Nenhuma alteração necessária."
fi

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
fi