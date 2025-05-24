#!/bin/bash

# Lista de interfaces a serem configuradas
INTERFACES=("enp7s0" "eno1")

# Caminho do script de configuração
SCRIPT_PATH="/usr/local/sbin/set-nic-speed.sh"

# Cria o script que configura a velocidade da interface
echo "Criando script de configuração de rede..."

sudo cat << EOF > "$SCRIPT_PATH"
#!/bin/bash

INTERFACES=("enp7s0" "eno1")
SPEED=1000
DUPLEX=full
AUTONEG=off

for IFACE in "\${INTERFACES[@]}"; do
    if ip link show "\$IFACE" > /dev/null 2>&1; then
        echo "Configurando \$IFACE para \${SPEED}Mb/s \$DUPLEX (autoneg \$AUTONEG)..."
        sudo ethtool -s \$IFACE speed \$SPEED duplex \$DUPLEX autoneg \$AUTONEG
    else
        echo "Interface \$IFACE não encontrada. Ignorando."
    fi
done
EOF

sudo chmod +x "$SCRIPT_PATH"

echo "Script criado em $SCRIPT_PATH"

# Cria o arquivo de serviço systemd
SERVICE_PATH="/etc/systemd/system/set-nic-speed.service"

echo "Criando serviço systemd..."

sudo cat << EOF > "$SERVICE_PATH"
[Unit]
Description=Set network interfaces speed to 1Gbps
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Ativa o serviço no boot
echo "Habilitando e iniciando serviço..."
sudo systemctl daemon-reload
sudo systemctl enable --now set-nic-speed.service

echo "Configuração concluída com sucesso."
