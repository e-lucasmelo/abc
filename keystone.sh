#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

# Configuração do banco de dados MySQL
echo "Configuração do banco de dados MySQL para o Keystone..."
sudo mysql <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$senha';
FLUSH PRIVILEGES;
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

sudo bash -c "cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html
        LimitRequestBody 200000000000

        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF"

# Reiniciar o Apache
echo "Reiniciando o Apache/Keystone..."
sudo service apache2 restart

# Configurar as variáveis de ambiente
echo "Configurando variáveis de ambiente..."
export OS_USERNAME=admin
export OS_PASSWORD=$senha
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_DOMAIN_NAME=default
export OS_AUTH_URL=http://${controller[0]}:5000/v3
export OS_IDENTITY_API_VERSION=3

# Criar projetos e usuários no OpenStack
echo "configurando projeto dos serviços..."
openstack project create --domain default --description "Service Project" service
echo "configurando o papel de 'usuário...'"
openstack role create user

# Obter o token de administrador
echo "testando obtenção de token de administrador..."
openstack --os-auth-url http://${controller[0]}:5000/v3 --os-project-domain-name default --os-user-domain-name default --os-project-name admin --os-username admin token issue

# Criar arquivos admin-openrc e demo-openrc
echo "Criando arquivos admin-openrc..."
echo "export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$senha
export OS_AUTH_URL=http://${controller[0]}:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2" | sudo tee "$SCRIPT_DIR/admin-openrc" &>/dev/null

# Carregar o arquivo admin-openrc e obter o token
echo "Carregando admin-openrc e testando obtenção  do token..."
source "$SCRIPT_DIR/admin-openrc"
openstack token issue