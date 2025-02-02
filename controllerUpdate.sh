#!/bin/bash

echo "Carregando variáveis de ambiente do OpenStack..."
. admin-openrc

echo "verificando os novos hosts compute..."
sudo nova-manage cell_v2 discover_hosts --verbose

echo "verificar a lista de serviços, catálogo e imagem"
openstack compute service list
openstack catalog list
openstack image list
sudo nova-status upgrade check

echo "Verificando extensões de rede e agentes de rede do Neutron..."
openstack extension list --network
openstack network agent list

echo "configuração concluída!"