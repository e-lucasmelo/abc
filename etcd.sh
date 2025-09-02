#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

if [ "$ubuntu_full_version" = "24.04" ]; then
# Instalar o etcd
echo "Instalando o etcd-server..."
sudo apt install etcd-server -y &>/dev/null
else
# Instalar o etcd
echo "Instalando o etcd..."
sudo apt install etcd -y &>/dev/null
fi

# Configurar o etcd
echo "Configurando o etcd..."
sudo bash -c "cat <<EOF > /etc/default/etcd
ETCD_NAME=\"${controller[0]}\"
ETCD_DATA_DIR=\"/var/lib/etcd\"
ETCD_INITIAL_CLUSTER_STATE=\"new\"
ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster-01\"
ETCD_INITIAL_CLUSTER=\"${controller[0]}=http://${controller[1]}:2380\"
ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http://${controller[1]}:2380\"
ETCD_ADVERTISE_CLIENT_URLS=\"http://${controller[1]}:2379\"
ETCD_LISTEN_PEER_URLS=\"http://0.0.0.0:2380\"
ETCD_LISTEN_CLIENT_URLS=\"http://${controller[1]}:2379\"
EOF"

ubuntu_full_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d '"' -f 2)

if [ "$ubuntu_full_version" = "24.04" ]; then
  # Habilitar e reiniciar o serviço etcd
echo "Habilitando o serviço etcd-server..."
sudo systemctl enable etcd &>/dev/null
echo "Reiniciando o serviço etcd-server..."
sudo systemctl restart etcd.service
else
    # Habilitar e reiniciar o serviço etcd
echo "Habilitando o serviço etcd..."
sudo systemctl enable etcd &>/dev/null
echo "Reiniciando o serviço etcd..."
sudo systemctl restart etcd.service
fi