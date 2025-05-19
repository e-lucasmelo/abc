#!/bin/bash

set -e

SCRIPT_PATH="/usr/local/bin/wait-for-default-route.sh"
SERVICE_DROPIN_DIR="/etc/systemd/system/etcd.service.d"
SERVICE_DROPIN_FILE="$SERVICE_DROPIN_DIR/wait-for-network.conf"

echo "[+] Criando script de verificação de rota default em: $SCRIPT_PATH"

sudo cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash
TRIES=20
for i in $(seq 1 $TRIES); do
  if ip route | grep -q "^default"; then
    echo "Rota default encontrada."
    exit 0
  fi
  echo "Esperando rota default... ($i/$TRIES)"
  sleep 2
done
echo "Erro: rota default não encontrada após espera."
exit 1
EOF

sudo chmod +x "$SCRIPT_PATH"
echo "[✓] Script criado e marcado como executável."

echo "[+] Criando drop-in de configuração para etcd: $SERVICE_DROPIN_FILE"

sudo mkdir -p "$SERVICE_DROPIN_DIR"
cat << EOF > "$SERVICE_DROPIN_FILE"
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
ExecStartPre=$SCRIPT_PATH
EOF

echo "[✓] Drop-in de systemd criado."

echo "[+] Recarregando systemd e reiniciando etcd..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart etcd
sudo systemctl restart memcached
echo "[✓] Configuração aplicada. Verifique com: systemctl status etcd"
