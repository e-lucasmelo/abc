#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

# Verifica se a variável está definida e se é um valor válido
if [[ -z "$repositorio" || ! " ${valid_releases[@]} " =~ " $repositorio " ]]; then
    echo "Erro: variável 'repositorio' não definida ou contém um valor inválido."
    echo "Valores válidos: ${valid_releases[*]}"
    exit 1
fi

if [[ ("$repositorio" == "dalmatian" || "$repositorio" == "epoxy") && "$ubuntu_major_version" != "24" ]]; then
    echo "Erro: O repositório $repositorio só é compatível com Ubuntu 24."
    exit 1

elif [[ "$repositorio" != "dalmatian" && "$repositorio" != "epoxy" && "$ubuntu_major_version" != "22" ]]; then
    echo "Erro: O repositório $repositorio só é compatível com Ubuntu 22."
    exit 1
fi

echo "Repositório '$repositorio' e Ubuntu $ubuntu_major_version são compatíveis."

# Verifica se o usuário está configurado para usar o sudo sem digitar senha
if sudo grep -q "^$USUARIO ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
    echo "O usuário $USUARIO já tem sudo sem senha."
#    exit 0
else
# Adiciona a regra no sudoers
echo "$USUARIO ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null

echo "Configuração concluída! O usuário $USUARIO pode usar sudo sem senha."
fi

if [[ "$host_temp" = "block" || ( "$computeBlock" = "sim" && "$host_temp" = "compute" ) ]]; then
if [ -b "/dev/$disk_block" ]; then
    echo "/dev/$disk_block existe, vamos seguir a configuração..."
elif [ -n "$disk_block" ];then
    echo "a variável disk_block está vazia, não podemos seguir com a configuração."
    echo "preencha a variavel e inicie o script novamente."
    exit 1
else
    echo "/dev/$disk_block não existe, por favor adicione o disk e tente novamente"
    exit 1
fi
else
echo "host não é de block, vamos seguir a configuração..."
fi

if [[ "$host_temp" = "object" || ( "$computeObject" = "sim" && "$host_temp" = "compute" ) ]]; then
    if [ -z "$disk_object1" ]; then
        echo "a variável disk_object1 está vazia, preencha a variável e inicie o script novamente."
        exit 1
    elif [ ! -e "/dev/$disk_object1" ]; then
        echo "o disco /dev/$disk_object1 não foi encontrado, veja se a variável foi definida corretamente e se o disco existe"
        exit 1
    elif [ -e "/dev/$disk_object1" ]; then
        echo "o disco /dev/$disk_object1 existe, vamos seguir a configuração..."
    else
        echo "Os discos não existem, por favor adicione-os e tente novamente."
        exit 1
    fi
else
    echo "host não é de object, vamos seguir a configuração..."
fi

#echo "chamando o script 'netplan.sh'..."
#bash "$SCRIPT_DIR/netplan.sh"

# Atualizar e atualizar o sistema
echo "Atualizando o sistema..."
sudo apt update &>/dev/null
sudo apt upgrade -y &>/dev/null

# Definir o nome do host como 'controller'
echo "Definindo o hostname como '${host_array[0]}'..."
sudo hostnamectl set-hostname ${host_array[0]}

# Editar o arquivo /etc/hosts
echo "Adicionando entradas no /etc/hosts..."
sudo bash -c "cat <<EOF > /etc/hosts
127.0.0.1	localhost
${controller[1]}	${controller[0]}
${compute1[1]}	${compute1[0]}
${block1[1]}	${block1[0]}
${block3[1]}	${block3[0]}
${object1[1]}	${object1[0]}
EOF"

echo "chamando o script 'chrony.sh'..."
bash "$SCRIPT_DIR/chrony.sh"

# Adicionar o repositório do OpenStack Caracal
echo "Adicionando o repositório do OpenStack $repositorio..."
sudo add-apt-repository -y cloud-archive:$repositorio &>/dev/null

# Instalar os pacotes necessários
echo "Instalando nova-compute e dependências..."
sudo apt install nova-compute -y &>/dev/null
echo "Instalando python3-openstackclient..."
sudo apt install python3-openstackclient -y &>/dev/null

if [ $host = "controller" ]; then

echo "chamando o script 'mariadb.sh'..."
bash "$SCRIPT_DIR/mariadb.sh"

echo "chamando o script 'rabbitmq.sh'..."
bash "$SCRIPT_DIR/rabbitmq.sh"

echo "chamando o script 'memcached.sh'..."
bash "$SCRIPT_DIR/memcached.sh"

echo "chamando o script 'etcd.sh'..."
bash "$SCRIPT_DIR/etcd.sh"

echo "chamando o script 'keystone.sh'..."
bash "$SCRIPT_DIR/keystone.sh"

echo "chamando o script 'glance.sh'..."
bash "$SCRIPT_DIR/glance.sh"

echo "chamando o script 'placement.sh'..."
bash "$SCRIPT_DIR/placement.sh"
fi

echo "chamando o script 'nova.sh'..."
bash "$SCRIPT_DIR/nova.sh"

echo "chamando o script 'neutron.sh'..."
bash "$SCRIPT_DIR/neutron.sh"

echo "chamando script 'cinder.sh'..."
bash "$SCRIPT_DIR/cinder.sh"

echo "chamando script 'swift.sh'..."
bash "$SCRIPT_DIR/swift.sh"

if [ $host = "controller" ]; then

echo "chamando o script 'horizon.sh'..."
bash "$SCRIPT_DIR/horizon.sh"


echo "##### Configurações apenas para o controller #####"

echo "Carregando variáveis de ambiente do OpenStack..."
source "$SCRIPT_DIR/admin-openrc"

echo "verificando os hosts compute..."
sudo -u nova /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" &>/dev/null

sudo nova-status upgrade check

#bash designate.sh
#bash heat.sh
#bash etcd_correcao_boot.sh
#bash memcached_correcao_boot.sh
echo "configuração concluída!"
echo "Faça a configuração do host compute."
fi