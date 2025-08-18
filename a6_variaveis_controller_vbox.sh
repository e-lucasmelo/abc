#!/bin/bash

#variaveis

# insira o nome do usuário utilizado na configuração
USUARIO=$USER

# qual host está configurando?
# controller, compute1, compute2, compute3, block1, block2, block3,object1, object2, object3
host="controller"

# se for utilizar o host compute também como host block, digite 'sim'
# valores validos: "sim" ou "nao"
computeBlock="sim"

# se for host block ou computeBlock, identifique o disco que será utilizado
disk_block="sda3"

# se for utilizar o host compute também como host object, digite 'sim'
# valores validos: "sim" ou "nao"
computeObject="sim"

#se for host object ou computeObject, identifique o disco que será utilizado
#no host controller deve colocar o mesmo nome de disco que será usado no object ou computeObject
disk_object1="sda4"
#disk_object2="sdc"

# Qual repositório do openstack vai utilizar?
# Ubuntu 22.04: zed, antelope, bobcat e caracal
# Ubuntu 24.04: dalmatian e epoxy
# com o repositorio caracal não vai funcionar o vpnaas neste script
# Pode usar o dalmatian e bobcat que estão com menos bugs

repositorio="dalmatian"

# variável para validação das releases
valid_releases=("zed" "antelope" "bobcat" "caracal" "dalmatian" "epoxy")

# insira o caminho completo do arquivo netplan
arquivoNetplan="/etc/netplan/50-cloud-init.yaml"

# insira o tipo de conexão para a rede internet
# "ethernets" ou "wifis"
tipoConexao="ethernets"

# se for "wifis", insira o nome da rede e senha
rede_wifi=
senha_wifi=

# insira a interface de rede que é utilizada para a conexão de internet
interfaceInternet="enp0s3"

# insira as 3 primeiras partes do ip da sua rede de internet
# se a sua rede for '192.168.0.0/24', voce deve inserir: '192.168.0'
ip_internet="10.0.2"

# insira a parte final do ip do gateway da rede de internet
# normalmente é o ip com final 1, se não for esse, altere.
gateway_internet="${ip_internet}.2"

# insira os ips dns separados por espaço
dns=("181.213.132.2" "181.213.132.3")

# insira a interface da rede de gerenciamento
# Esta é a interface que os hosts controller, compute, block e object vão se comunicar
# Se você não tiver uma interface específica para o gerenciamento, 
# deixe a variável 'interface_ger' vazia que será configurada a interfaceInternet para o gerenciamento
interface_ger="enp0s8" # interface de gerenciamento

# insira as 3 primeiras partes do ip da sua rede de gerenciamento
ip_ger="172.16.1"

# Insira a interface da rede provider
# Essa é a interface que o openstack usará para a rede provider e IP´s FLAT
interfaceProvider="enps09"

# para a rede provider
# insira as 3 primeiras partes do ip da sua rede que fornecerá os ips flutuantes
ip_provider="10.0.0"

#altere a parte final do ip
#intervalo de ips flutuantes da rede provider
ip_inicio="$ip_provider.200"
ip_fim="$ip_provider.220"

#gateway da rede provider
gateway_provider="$ip_provider.1"

#dns da rede provider
dns_provider="$ip_provider.1"

#subnet da rede provider(deve ser igual a sua rede local)
subnet_provider="$ip_provider.0/24"

# variaveis para identificar os hosts e seus ips de gerenciamento e internet
 #("host" "ip_host" "ip_internet")
# Aqui está sendo esperado que o ip do controller termine com 11, ip do compute com 21, ip do block com 31 e ip do object com 41
controller=("controller" "${ip_ger}.11" "${ip_internet}.11/24")
compute1=("compute1" "${ip_ger}.21" "${ip_internet}.21/24")
compute2=("compute2" "${ip_ger}.22" "${ip_internet}.22/24")
compute3=("compute3" "${ip_ger}.23" "${ip_internet}.23/24")
block1=("block1" "${ip_ger}.31" "${ip_internet}.31/24")
block2=("block2" "${ip_ger}.32" "${ip_internet}.32/24")
block3=("block3" "${ip_ger}.33" "${ip_internet}.33/24")
object1=("object1" "${ip_ger}.41" "${ip_internet}.41/24")
object2=("object2" "${ip_ger}.42" "${ip_internet}.42/24")
object3=("object3" "${ip_ger}.43" "${ip_internet}.43/24")

# senha que será usada para todos os serviços do openstack
senha="admin"