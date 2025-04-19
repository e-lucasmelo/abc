#!/bin/bash

#variaveis.sh

# insira o nome do usuário utilizado na configuração
USUARIO="ubuntu"

# qual repsitório do openstack vai utilizar?
# "zed", "antelope", "bobcat", "caracal"
# com o repositorio caracal não vai funcionar o vpnaas neste script
# sugestão é usar o "bobcat"
repositorio="bobcat"

valid_releases=("zed" "antelope" "bobcat" "caracal")

# insira o caminho completo do arquivo netplan
arquivoNetplan="/etc/netplan/50-cloud-init.yaml"

# insira o tipo de rede de gerenciamento e provider
# "ethernets" ou "wifis"
rede_ger="ethernets"

# se for "wifis", insira o nome da rede e senha
rede_wifi=
senha_wifi=

# insira a interface da rede de gerenciamento
interface_ger="enp0s3" # interface de gerenciamento

# insira as 3 primeiras partes do ip da sua rede de gerenciamento
ip_ger="192.168.1"

# insira a parte final do ip do gateway da rede de gerencia
gateway_gerencia="${ip_ger}.1"

# insira os ips dns separados por espaço
dns=("181.213.132.2" "181.213.132.3")

#insira a interface da rede provider
interfaceProvider="enp0s8" # interface da rede provider do openstack

# para a rede provider
# insira as 3 primeiras partes do ip da sua rede que fornecerá os ips flutuantes
ip_provider="192.168.0"

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

# essa interface adicional só é usado no virtualbox para acessar direto a vm em questão
#insira o nome da interface de rede
interfaceAdicional=""

#insira as 3 primeiras partes do ip da sua rede bridge que é a sua rede local
ip_Adic="192.168.0"


# qual host está configurando?
# controller, compute1, compute2, compute3, block1, block2, block3,object1, object2, object3
host="controller"

# se for host compute, vai usar também como host block?
# digite "sim" ou "nao"
computeBlock="nao"

# se for host block ou computeBlock, identifique o disco que será utilizado
disk_block="sdb"

# se for host compute, vai usar também como host object?
# digite "sim" ou "nao"
computeObject="nao"

#se for host object ou computeObject, identifique o disco que será utilizado
#no host controller deve colocar o mesmo nome de disco que será usado no object
disk_object1="sdb"
#disk_object2="sdc"

#identifique qual(is) object storages serão instalados
controller=("controller" "${ip_ger}.11" "${ip_Adic}.111/24") #("host" "ip_host" "ip_acesso_vm")
compute1=("compute1" "${ip_ger}.21" "${ip_Adic}.121/24")
compute2=("compute2" "${ip_ger}.22" "${ip_Adic}.122/24")
compute3=("compute3" "${ip_ger}.23" "${ip_Adic}.123/24")
block1=("block1" "${ip_ger}.31" "${ip_Adic}.131/24")
block2=("block2" "${ip_ger}.32" "${ip_Adic}.132/24")
block3=("block3" "${ip_ger}.33" "${ip_Adic}.133/24")
object1=("object1" "${ip_ger}.41" "${ip_Adic}.141/24")
object2=("object2" "${ip_ger}.42" "${ip_Adic}.142/24")
object3=("object3" "${ip_ger}.43" "${ip_Adic}.143/24")
senha="admin"
