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


sudo curl -o /etc/swift/swift.conf https://opendev.org/openstack/swift/raw/branch/master/etc/swift.conf-sample
sleep 2

sudo bash -c "cat <<EOF > /etc/swift/swift.conf
[swift-hash]
swift_hash_path_suffix = $senha
swift_hash_path_prefix = $senha
[storage-policy:0]
name = Policy-0
default = yes
aliases = yellow, orange
[swift-constraints]
EOF"

sudo chown -R root:swift /etc/swift

sudo service memcached restart
sudo service swift-proxy restart #verificar o nome do serviço

# no object storage node
sudo swift-init all start

#verificar funcionamento
sudo chcon -R system_u:object_r:swift_data_t:s0 /srv/node

echo "Configuração do account ring concluída!"
