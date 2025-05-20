#!/bin/bash

# Corrigir erro de boot do memcached no Ubuntu 24.04 para OpenStack

echo "Criando override para memcached.service..."

sudo mkdir -p /etc/systemd/system/memcached.service.d

sudo cat <<EOF | sudo tee /etc/systemd/system/memcached.service.d/override.conf > /dev/null
[Unit]
After=network-online.target
Wants=network-online.target
EOF

echo "Recarregando systemd e reiniciando memcached..."

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable memcached
sudo systemctl restart memcached

echo "Status do memcached:"
sudo systemctl status memcached --no-pager

echo "Correção aplicada com sucesso!"
