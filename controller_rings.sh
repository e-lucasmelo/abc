#!/bin/bash
echo "carregar variaveis.sh..."
source variaveis.sh
source admin-openrc

if [ "$computeObject" = "sim" ];then
ip_object1="${compute1[1]}"
else
ip_object1="${object1[1]}"
fi

# Criar o account ring
echo "criar account.builder..."
sudo swift-ring-builder /etc/swift/account.builder create 10 1 1
# ajustar o if para validar todos os discos corretamente
# Adicionar dispositivos ao ring
echo "adicionar dispositivos no account.builder..."
sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 1 --ip "$ip_object1" --port 6202 --device $disk_object1 --weight 100
#sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 1 --ip ${object1[1]} --port 6202 --device $disk_object2 --weight 100
#sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 2 --ip 10.0.0.52 --port 6202 --device sdb --weight 100
#sudo swift-ring-builder /etc/swift/account.builder add --region 1 --zone 2 --ip 10.0.0.52 --port 6202 --device sdc --weight 100


# Rebalancear o ring
echo "criar rebalance account.builder..."
sudo swift-ring-builder /etc/swift/account.builder rebalance
#container
# Verificar o ring
echo "verificar configuração do account.builder..."
sudo swift-ring-builder /etc/swift/account.builder

echo "criar container.builder..."
sudo swift-ring-builder /etc/swift/container.builder create 10 1 1
echo "adicionar dispositivos no container.builder..."
sudo swift-ring-builder /etc/swift/container.builder   add --region 1 --zone 1 --ip "$ip_object1" --port 6201   --device $disk_object1 --weight 100
#sudo swift-ring-builder /etc/swift/container.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6201   --device $disk_object2 --weight 100
echo "criar rebalance container.builder..."
sudo swift-ring-builder /etc/swift/container.builder rebalance
echo "verificar configuração do container.builder..."
sudo swift-ring-builder /etc/swift/container.builder
#object
echo "criar object.builder..."
sudo swift-ring-builder /etc/swift/object.builder create 10 1 1
echo "adicionar dispositivos object.builder..."
sudo swift-ring-builder /etc/swift/object.builder   add --region 1 --zone 1 --ip "$ip_object1" --port 6200   --device $disk_object1 --weight 100
#sudo swift-ring-builder /etc/swift/object.builder   add --region 1 --zone 1 --ip ${object1[1]} --port 6200   --device $disk_object2 --weight 100
echo "criar rebalance object.builder..."
sudo swift-ring-builder /etc/swift/object.builder rebalance
echo "verificar configuração object.builder..."
sudo swift-ring-builder /etc/swift/object.builder

echo "baixar swift.conf-sample..."
sudo curl -o /etc/swift/swift.conf https://opendev.org/openstack/swift/raw/branch/master/etc/swift.conf-sample
echo "configuração swift.conf..."
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

echo "copiar arquivos para o server object..."
sudo scp /etc/swift/swift.conf /etc/swift/account.ring.gz /etc/swift/container.ring.gz /etc/swift/object.ring.gz $USUARIO@"$ip_object1":/temp/

ssh $USUARIO@"$ip_object1" "sudo bash /home/$USUARIO/abc/object_rings.sh"


sudo chown -R root:swift /etc/swift

sudo service memcached restart
sudo service swift-proxy restart #verificar o nome do serviço


swift stat

echo "Configuração do account ring concluída!"


### parte 2

#. admin-openrc

#swift stat

#openstack container create container1
#openstack object create container1 FILE
#openstack object list container1
#openstack object save container1 FILE