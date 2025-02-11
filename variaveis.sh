#variaveis.sh

# insira o caminho completo do arquivo netplan
arquivoNetplan="/etc/netplan/50-cloud-init.yaml"

# insira o tipo de rede de gerenciamento
# "ethernets" ou "wifis"
rede_ger="ethernets"

# se for "wifi", insira o nome da rede e senha
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
#altere conforme a sua rede
#intervalo de ips flutuantes da rede provider
ip_inicio="192.168.0.100"
ip_fim="192.168.0.130"

#gateway da rede provider
gateway_provider="192.168.0.1"

#dns da rede provider
dns_provider="192.168.0.1"

#subnet da rede provider(deve ser igual a sua rede local)
subnet_provider="192.168.0.0/24"

# essa interface adicional só é usado no virtualbox para acessar direto a vm em questão
#insira o nome da interface de rede
interfaceAdicional=""

#insira as 3 primeiras partes do ip da sua rede bridge que é a sua rede local
ip_Adic="192.168.0"


# qual host está configurando?
# controller, compute1, compute2, compute3, storage1, storage2, storage3

host="controller"

# se for host storage, identifique o disco que será utilizado
disk_storage="sdb"

controller=("controller" "${ip_ger}.11" "${ip_Adic}.111/24") #("host" "ip_host" "ip_acesso_vm")
compute1=("compute1" "${ip_ger}.21" "${ip_Adic}.121/24")
compute2=("compute2" "${ip_ger}.22" "${ip_Adic}.122/24")
compute3=("compute3" "${ip_ger}.23" "${ip_Adic}.123/24")
storage1=("storage1" "${ip_ger}.31" "${ip_Adic}.131/24")
storage2=("storage2" "${ip_ger}.32" "${ip_Adic}.132/24")
storage3=("storage3" "${ip_ger}.33" "${ip_Adic}.133/24")

senha="admin"
