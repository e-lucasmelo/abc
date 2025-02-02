#!/bin/bash

source variaveis.sh

echo "criando rede provider..."
. admin-openrc
openstack network create  --share --external --provider-physical-network provider --provider-network-type flat provider
echo "alocando ip da rede provider..."
openstack subnet create --network provider --allocation-pool start=$ip_inicio,end=$ip_fim --dns-nameserver $dns_provider --gateway $gateway_provider --subnet-range $subnet_provider provider

echo "criando rede selfservice..."
openstack network create selfservice
openstack subnet create --network selfservice --dns-nameserver 8.8.8.8 --gateway 10.0.0.1 --subnet-range 10.0.0.0/24 selfservice

echo "criando roteador..."
openstack router create router

echo "adicionando a rede selfservice ao router"
openstack router add subnet router selfservice

echo "adicionando a rede provider ao router"
openstack router set router --external-gateway provider
ip netns
echo "listando portas do router..."
openstack port list --router router

echo "criando grupo de segurança com portas liberadas ..."

echo " criando o grupo 'grupoTeste' ..."
openstack security group create grupoteste --description "Grupo com portas específicas liberadas"
echo " adicionando porta "22"..."
openstack security group rule create grupoTeste --protocol tcp --dst-port 22 --ingress
echo " adicionando porta "3389"..."
openstack security group rule create grupoTeste --protocol tcp --dst-port 3389 --ingress
echo " adicionando porta para icmp (ping)..."
openstack security group rule create grupoTeste --protocol icmp --ingress
echo " adicionando porta "53 - tcp"..."
openstack security group rule create grupoTeste --protocol tcp --dst-port 53 --ingress
echo " adicionando porta "53 - udp"..."
openstack security group rule create grupoTeste --protocol udp --dst-port 53 --ingress
echo " adicionando porta "80"..."
openstack security group rule create grupoTeste --protocol tcp --dst-port 80 --ingress
echo " adicionando porta "3306"..."
openstack security group rule create grupoTeste --protocol tcp --dst-port 3306 --ingress
echo " adicionando porta "443"..."
openstack security group rule create grupoTeste --protocol tcp --dst-port 443 --ingress
echo " criando o flavor m1.nano..."
openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano
echo "criando a instância cirros com o favor m1.nano, rede: selfservice e grupo de segurança: grupoTeste"
openstack server create --flavor m1.nano --image cirros --network selfservice --security-group grupoTeste Cirros
