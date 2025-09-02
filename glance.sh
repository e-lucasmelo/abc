#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

# Configuração do banco de dados MySQL para o Glance
echo "Configurando o banco de dados MySQL para o Glance..."
sudo mysql <<EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$senha';
FLUSH PRIVILEGES;
EOF

# Definir variáveis de ambiente para o OpenStack
echo "Carregando variáveis de ambiente do OpenStack..."
source "$SCRIPT_DIR/admin-openrc"

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
#enabled_backends=cinder:cinder
image_size_cap = 200000000000
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
#default_backend = cinder
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
[cinder]
#store_description = \"Cinder backend\"
EOF"

# Obter o ID do endpoint público de imagem
echo "Obtendo o ID do endpoint public de imagem..."
public_image_endpoint_id=$(openstack endpoint list --service image --interface public -f value -c ID)

# Atualizar o arquivo de configuração com o ID do endpoint público
echo "Atualizando a configuração do Glance com o ID do endpoint público..."
sudo sed -i "s|endpoint_id = |endpoint_id = $public_image_endpoint_id|g" /etc/glance/glance-api.conf

# Adicionar a role "reader" ao usuário Glance
echo "Adicionando a role 'reader' ao usuário Glance..."
openstack role add --user glance --user-domain default --system all reader

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