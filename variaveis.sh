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
disk_block="vdb"

# se for utilizar o host compute também como host object, digite 'sim'
# valores validos: "sim" ou "nao"
computeObject="sim"

#se for host object ou computeObject, identifique o disco que será utilizado
#no host controller deve colocar o mesmo nome de disco que será usado no object
disk_object1="vdc"
#disk_object2="sdc"

# Qual repositório do openstack vai utilizar?
# Ubuntu 22.04: zed, antelope, bobcat e caracal
# Ubuntu 24.04: dalmatian e epoxy
# com o repositorio caracal não vai funcionar o vpnaas neste script
# Pode usar o epoxy e bobcat

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


####################################################
########## Interface de rede para internet #########
####################################################

# insira a interface de rede que é utilizada para a conexão de internet
interfaceInternet="ens3"

# insira as 3 primeiras partes do ip da sua rede de internet
# se a sua rede for '192.168.0.0/24', voce deve inserir: '192.168.0'
ip_internet="172.16.1"

# insira a parte final do ip do gateway da rede de internet
# normalmente é o ip com final 1, se não for esse, altere.
gateway_internet="${ip_internet}.1"

# insira os ips dns separados por espaço
dns=("181.213.132.2" "181.213.132.3")


#########################################################
########## Interface de rede para gerenciamento #########
#########################################################

# Esta é a interface que os hosts controller, compute, block e object vão se comunicar
# Se você não tiver uma interface específica para o gerenciamento, 
# deixe a variável 'interface_ger' vazia que será configurada a interfaceInternet para o gerenciamento
interface_ger="ens4" # interface de gerenciamento

# insira as 3 primeiras partes do ip da sua rede de gerenciamento
ip_ger="172.16.2"


##########################################################
########## Interface de rede para flat(provider) #########
##########################################################

# Insira a interface da rede provider
# Essa é a interface que o openstack usará para a rede provider e IP´s FLAT
interfaceProvider="ens5"

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
block1=("block1" "${ip_ger}.31" "${ip_internet}.31/24")
object1=("object1" "${ip_ger}.41" "${ip_internet}.41/24")

# Função que usa indireção para acessar o array correto
ip_gerencia(){
    # Variável indireta para pegar o array correto
    local array_name="$host"  # O nome do host
    eval "echo \${$array_name[@]}"  # Retorna toda a lista do array correspondente ao nome do host
}

host_array=($(ip_gerencia))
host_temp=$(echo "$host" | sed 's/[0-9]*$//')

# Pega a versão completa, ex: "24.04"
ubuntu_full_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d '"' -f 2)

# Extrai apenas a parte antes do ponto, ex: "24"
ubuntu_major_version=$(echo "$ubuntu_full_version" | cut -d '.' -f 1)

# senha que será usada para todos os serviços do openstack
senha="admin"