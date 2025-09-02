#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

# Instalar o RabbitMQ
echo "Instalando o RabbitMQ..."
sudo apt install rabbitmq-server -y &>/dev/null

# Configurar o RabbitMQ
echo "Configurando o RabbitMQ..."
sudo rabbitmqctl add_user openstack $senha &>/dev/null
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*" &>/dev/null