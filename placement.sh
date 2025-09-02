#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

# Configuração do banco de dados MySQL para o Placement
echo "Configurando o banco de dados MySQL para o Placement..."
sudo mysql <<EOF
CREATE DATABASE placement;
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$senha';
FLUSH PRIVILEGES;
EOF

# Carregar variáveis de ambiente do OpenStack
echo "Carregando variáveis de ambiente do OpenStack..."
source "$SCRIPT_DIR/admin-openrc"

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
auth_url = http://${controller[0]}:5000
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


ubuntu_full_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d '"' -f 2)

if [ "$ubuntu_full_version" = "24.04" ]; then
echo "versão do ubuntu não precisa do python3-osc-placement...instalação abortada"
else
# Instalando python3-osc-placement
echo "Instalando python3-osc-placement..."
sudo apt install python3-osc-placement -y &>/dev/null
fi

# Verificar a atualização do Placement
echo "Verificando o status do Placement..."
sudo placement-status upgrade check

# Listar os recursos e traits
echo "Listando classes de recursos..."
openstack --os-placement-api-version 1.2 resource class list --sort-column name

echo "Listando atributos..."
openstack --os-placement-api-version 1.6 trait list --sort-column name