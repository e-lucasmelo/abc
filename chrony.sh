#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

# Instalar o Chrony e configurar o servidor NTP
echo "Instalando o Chrony..."
sudo apt install chrony -y &>/dev/null

if [ $host = "controller" ]; then
network="allow $ip_ger.0/24
pool ntp.ubuntu.com        iburst maxsources 4"
else
network=""
fi

# Configurar o arquivo de configuração do Chrony
echo "Configurando o arquivo /etc/chrony/chrony.conf..."
sudo bash -c "cat <<EOF > /etc/chrony/chrony.conf
server ${controller[0]} iburst
$network
confdir /etc/chrony/conf.d
sourcedir /run/chrony-dhcp
sourcedir /etc/chrony/sources.d
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
leapsectz right/UTC
EOF"


# Reiniciar o serviço Chrony
echo "Reiniciando o serviço Chrony..."
sudo service chrony restart

# Verificar as fontes do Chrony
echo "Verificando fontes do Chrony..."
sudo chronyc sources