#!/bin/bash
echo "carregar variaveis.sh..."
source variaveis.sh

echo "acessar o server object e executar comandos..."
sudo mv  /tmp/swift.conf /tmp/account.ring.gz /tmp/container.ring.gz /tmp/object.ring.gz /etc/swift
echo "alterando proprietário para o usuário swift"
sudo chown -R root:swift /etc/swift
echo "ajusta o contexto SELinux de /srv/node para permitir o acesso do Swift..."
sudo chcon -R system_u:object_r:swift_data_t:s0 /srv/node
echo "iniciar o swift..."
sudo swift-init all start