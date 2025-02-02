#variaveis.sh

#defina a rede de gerenciamento
arquivoNetplan="/etc/netplan/50-cloud-init.yaml"
gerenciamento="192.168.1" # sem a parte final, será definida mais a frente.
dns=("181.213.132.2" "181.213.132.3")
interfaceGerencia="enp0s3" # interface de gerenciamento
interfaceProvider="enp0s8" # interface da rede provider do openstack
interfaceAdicional="enp0s9" # interface adicional para usar no virtualbox, deixar em branco se não usar.
gateway_gerencia="${gerenciamento}.1"
controller=("controller" "${gerenciamento}.11") #("host" "ip_host")
compute1=("compute1" "${gerenciamento}.21")
compute2=("compute2" "${gerenciamento}.22")
compute3=("compute3" "${gerenciamento}.23")
storage1=("storage1" "${gerenciamento}.31")
storage2=("storage2" "${gerenciamento}.32")
storage3=("storage3" "${gerenciamento}.33")
senha="admin"


colocar variavel da senha admin