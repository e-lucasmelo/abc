#!/bin/bash
echo "carregar variaveis.sh..."
source variaveis.sh
source admin-openrc

echo "acessar o server object e executar comandos..."
sudo mv /home/lucas/*.gz /etc/swift
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
echo "alterando proprietário para o usuário swift"
sudo chown -R root:swift /etc/swift
echo "ajusta o contexto SELinux de /srv/node para permitir o acesso do Swift..."
sudo chcon -R system_u:object_r:swift_data_t:s0 /srv/node
echo "iniciar o swift..."
sudo swift-init all start