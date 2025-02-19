#!/bin/bash

source variaveis.sh

# Criar o account ring
sudo swift-ring-builder /etc/swift/account.builder create 10 2 1
# ajustar o if para validar todos os discos corretamente
# Adicionar dispositivos ao ring
sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 1 --ip ${object1[1]} --port 6202 --device $disk_object1 --weight 100
sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 1 --ip ${object1[1]} --port 6202 --device $disk_object2 --weight 100
#sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 2 --ip 10.0.0.52 --port 6202 --device sdb --weight 100
#sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 2 --ip 10.0.0.52 --port 6202 --device sdc --weight 100


# Rebalancear o ring
sudo swift-ring-builder /etc/swift/account.builder rebalance
#container
# Verificar o ring
sudo swift-ring-builder /etc/swift/account.builder


sudo swift-ring-builder /etc/swift/container.builder create 10 2 1
sudo swift-ring-builder /etc/swift/container.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6201   --device $disk_object1 --weight 100
sudo swift-ring-builder /etc/swift/container.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6201   --device $disk_object2 --weight 100
sudo swift-ring-builder /etc/swift/container.builder rebalance
sudo swift-ring-builder /etc/swift/container.builder
#object

sudo swift-ring-builder /etc/swift/object.builder create 10 2 1
sudo swift-ring-builder /etc/swift/object.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6200   --device $disk_object1 --weight 100
sudo swift-ring-builder /etc/swift/object.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6200   --device $disk_object2 --weight 100

sudo swift-ring-builder /etc/swift/object.builder rebalance
sudo swift-ring-builder /etc/swift/object.builder

sudo scp /etc/swift/account.ring.gz /etc/swift/container.ring.gz /etc/swift/object.ring.gz lucas@192.168.0.141:/home/lucas/

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

echo "Configuração do account ring concluída!"


### parte 2

. admin-openrc

swift stat

openstack container create container1
openstack object create container1 FILE
openstack object list container1
openstack object save container1 FILE