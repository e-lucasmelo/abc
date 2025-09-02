#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

echo "Instalando mariadb-server python3-pymysql..."
sudo apt install mariadb-server python3-pymysql -y &>/dev/null

# Configuração do MariaDB
echo "Configurando o MariaDB..."
sudo bash -c "cat <<EOF > /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF"

sudo mysql <<EOF
GRANT ALL PRIVILEGES ON *.* TO 'lucas'@'%' IDENTIFIED BY '$senha';
FLUSH PRIVILEGES;
EOF

# Reiniciar o serviço MariaDB
echo "Reiniciando o serviço MariaDB..."
sudo service mysql restart