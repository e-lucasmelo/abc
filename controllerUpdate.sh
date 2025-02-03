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


echo "desabilitando apenas o serviço do nova-compute..."
sudo systemctl disable --now nova-compute
echo "reiniciando todos os serviços...."
sudo systemctl restart apache2.service glance-api.service neutron-dhcp-agent.service neutron-l3-agent.service neutron-metadata-agent.service neutron-openvswitch-agent.service neutron-server.service nova-api.service nova-compute.service nova-conductor.service nova-novncproxy.service nova-scheduler.service nova-api.service cinder-scheduler.service

echo "configuração concluída!"