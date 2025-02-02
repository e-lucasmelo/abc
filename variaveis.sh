#variaveis.sh

#defina a rede de gerenciamento
arquivoNetplan="/etc/netplan/50-cloud-init.yaml"
gerenciamento="192.168.1" # sem a parte final, será definida mais a frente.
ipAcessoVM="192.168.0" # ip da rede bridge, sem a parte final, será definida mais a frente
dns=("181.213.132.2" "181.213.132.3")
interfaceGerencia="enp0s3" # interface de gerenciamento
interfaceProvider="enp0s8" # interface da rede provider do openstack
interfaceAdicional="enp0s9" # interface adicional(bridge) para usar no virtualbox, deixar em branco se não usar.
gateway_gerencia="${gerenciamento}.1"
controller=("controller" "${gerenciamento}.11" "${ipAcessoVM}.111/24") #("host" "ip_host" "ip_acesso_vm")
compute1=("compute1" "${gerenciamento}.21" "${ipAcessoVM}.111/24")
compute2=("compute2" "${gerenciamento}.22" "${ipAcessoVM}.122/24")
compute3=("compute3" "${gerenciamento}.23" "${ipAcessoVM}.123/24")
storage1=("storage1" "${gerenciamento}.31" "${ipAcessoVM}.131/24")
storage2=("storage2" "${gerenciamento}.32" "${ipAcessoVM}.132/24")
storage3=("storage3" "${gerenciamento}.33" "${ipAcessoVM}.133/24")
senha="admin"

# para a rede provider
#altere conforme a sua rede
ip_inicio="192.168.0.100"
ip_fim="192.168.0.130"
gateway_provider="192.168.0.1"
dns_provider="192.168.0.1"
subnet_provider="192.168.0.0/24"