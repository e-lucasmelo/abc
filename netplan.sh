#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

# Verifica se o serviço NetworkManager existe
if systemctl list-unit-files | grep -q '^NetworkManager.service'; then
    # Verifica se o NetworkManager está ativo
    if systemctl is-active --quiet NetworkManager; then
        echo "Desativando NetworkManager..."
        sudo systemctl disable --now NetworkManager
        echo "Ativando systemd-networkd..."
        sudo systemctl enable --now systemd-networkd
    else
        echo "NetworkManager não está ativo. Nenhuma ação necessária."
    fi
else
    echo "NetworkManager não está instalado ou não gerenciado pelo systemd."
fi

if [ $tipoConexao = "wifis" ]; then
x="            access-points:
                \"$rede_wifi\":
                    password: \"$senha_wifi\""
else
x="            dhcp4: false
            dhcp6: false
            accept-ra: no"
fi

if [ -n "$interfaceInternet" ]; then
i="network:
    version: 2
    renderer: networkd
    $tipoConexao:
        $interfaceInternet:
            addresses:
            - ${host_array[2]}
            nameservers:
                addresses:
                - $gateway_internet
                - ${dns[0]}
                - ${dns[1]}
            routes:
            -   to: default
                via: $gateway_internet
                metric: 100
            -   to: ${dns[0]}
                via: $gateway_internet
                metric: 100
            -   to: ${dns[1]}
                via: $gateway_internet
                metric: 100
$x"
else
i=""
fi

if [ -n "$interface_ger" ]; then
g="        $interface_ger:
            addresses:
            - ${host_array[1]}/24
            dhcp4: false
            dhcp6: false
            ignore-carrier: true
            link-local: []
            critical: true
            wakeonlan: true"
fi

if [ "$host_temp" = "controller" ] || [ "$host_temp" = "compute" ]; then
p="        $interfaceProvider:
            dhcp4: false
            dhcp6: false
            accept-ra: no"
else
p=""
fi

# Editar o arquivo de configuração de rede /etc/netplan/50-cloud-init.yaml
echo "Configurando rede no $arquivoNetplan..."
sudo bash -c "cat <<EOF > $arquivoNetplan
$i
$g
$p
EOF"

# Desabilitar configuração de rede no /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
echo "Desabilitando a configuração de rede no /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg..."
sudo bash -c 'cat <<EOF > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network: {config: disabled}
EOF'

# Aplicar as configurações do Netplan
echo "Aplicando configurações do Netplan..."
sudo netplan apply

# Testando a conexão de rede com 3 tentativas
echo "Testando a conexão de rede..."
tentativas=0
max_tentativas=10

while ! curl -s --connect-timeout 5 http://www.google.com --output /dev/null; do
    tentativas=$((tentativas + 1))
    
    if [ "$tentativas" -ge "$max_tentativas" ]; then
        echo "Falha na conexão após $max_tentativas tentativas. Encerrando o script."
        exit 1
    fi

    echo "Sem conexão. Tentativa $tentativas de $max_tentativas. Tentando novamente em 3 segundos..."
    sleep 3
done

echo "Conexão estabelecida com sucesso!"