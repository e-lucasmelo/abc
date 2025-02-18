#!/bin/bash

source variaveis.sh

# Criar o account ring
sudo swift-ring-builder /etc/swift/account.builder create 10 2 1
sleep 2
# ajustar o if para validar todos os discos corretamente
if [ -z "disk_object1" ]; then
# Adicionar dispositivos ao ring
sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 1 --ip ${object1[1]} --port 6202 --device $disk_object1 --weight 100
sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 1 --ip ${object1[1]} --port 6202 --device $disk_object2 --weight 100
#sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 2 --ip 10.0.0.52 --port 6202 --device sdb --weight 100
#sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 2 --ip 10.0.0.52 --port 6202 --device sdc --weight 100
fi

# Verificar o ring
sudo swift-ring-builder /etc/swift/account.builder
sleep 2
# Rebalancear o ring
sudo swift-ring-builder /etc/swift/account.builder rebalance
sleep 2
#container

sudo swift-ring-builder /etc/swift/container.builder create 10 2 1
sleep 2
sudo swift-ring-builder /etc/swift/container.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6201   --device $disk_object1 --weight 100
sudo swift-ring-builder /etc/swift/container.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6201   --device $disk_object2 --weight 100
sudo swift-ring-builder /etc/swift/container.builder rebalance
sleep 2
sudo swift-ring-builder /etc/swift/container.builder
#object

sudo swift-ring-builder /etc/swift/object.builder create 10 2 1
sleep 2
sudo swift-ring-builder /etc/swift/object.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6200   --device $disk_object1 --weight 100
sudo swift-ring-builder /etc/swift/object.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6200   --device $disk_object2 --weight 100

sudo swift-ring-builder /etc/swift/object.builder rebalance
sleep 2
sudo swift-ring-builder /etc/swift/object.builder

sudo scp /etc/swift/*.ring.gz lucas@192.168.0.141:/home/lucas/

echo "Configuração do account ring concluída!"
