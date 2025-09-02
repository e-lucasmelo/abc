#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

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