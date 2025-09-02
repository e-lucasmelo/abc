#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

if [[ "$host_temp" = "block" || ( "$computeBlock" = "sim" && "$host_temp" = "compute" ) ]]; then
echo "instalação do LVM"
# Configurar LVM
sudo apt install lvm2 thin-provisioning-tools -y &>/dev/null
sudo pvcreate /dev/$disk_block
sudo vgcreate cinder-volumes /dev/$disk_block

echo "configuração do arquivo /etc/lvm/lvm.conf"

# Configurar LVM
sudo bash -c "cat <<EOF > /etc/lvm/lvm.conf
config {
        checks = 1
        abort_on_errors = 0
        profile_dir = \"/etc/lvm/profile\"
}
devices {
        dir = \"/dev\"
        scan = [ \"/dev\" ]
        filter = [ \"a/$disk_block/\", \"r/.*/\"]
        obtain_device_list_from_udev = 1
        external_device_info_source = \"none\"
        sysfs_scan = 1
        scan_lvs = 0
        multipath_component_detection = 1
        md_component_detection = 1
        fw_raid_component_detection = 0
        md_chunk_alignment = 1
        data_alignment_detection = 1
        data_alignment = 0
        data_alignment_offset_detection = 1
        ignore_suspended_devices = 0
        ignore_lvm_mirrors = 1
        require_restorefile_with_uuid = 1
        pv_min_size = 2048
        issue_discards = 1
        allow_changes_with_duplicate_pvs = 0
        allow_mixed_block_sizes = 0
}

allocation {
        maximise_cling = 1
        use_blkid_wiping = 1
        wipe_signatures_when_zeroing_new_lvs = 1
        mirror_logs_require_separate_pvs = 0
}
log {
        verbose = 0
        silent = 0
        syslog = 1
        overwrite = 0
        level = 0
        command_names = 0
        prefix = \"  \"
        activation = 0
        debug_classes = [ \"memory\", \"devices\", \"io\", \"activation\", \"allocation\", \"metadata\", \"cache\", \"locking\", \"lvmpolld\", \"dbus\" ]
}
backup {
        backup = 1
        backup_dir = \"/etc/lvm/backup\"
        archive = 1
        archive_dir = \"/etc/lvm/archive\"
        retain_min = 10
        retain_days = 30
}
shell {
        history_size = 100
}
global {
        umask = 077
        test = 0
        units = \"r\"
        si_unit_consistency = 1
        suffix = 1
        activation = 1
        proc = \"/proc\"
        etc = \"/etc\"
        wait_for_locks = 1
        locking_dir = \"/run/lock/lvm\"
        prioritise_write_locks = 1
        abort_on_internal_errors = 0
        metadata_read_only = 0
        mirror_segtype_default = \"raid1\"
        raid10_segtype_default = \"raid10\"
        sparse_segtype_default = \"thin\"
        use_lvmlockd = 0
        system_id_source = \"none\"
        use_lvmpolld = 1
        notify_dbus = 1
}
activation {
        checks = 0
        udev_sync = 1
        udev_rules = 1
        retry_deactivation = 1
        missing_stripe_filler = \"error\"
        raid_region_size = 2048
        raid_fault_policy = \"warn\"
        mirror_image_fault_policy = \"remove\"
        mirror_log_fault_policy = \"allocate\"
        snapshot_autoextend_threshold = 100
        snapshot_autoextend_percent = 20
        thin_pool_autoextend_threshold = 100
        thin_pool_autoextend_percent = 20
        monitoring = 1
        activation_mode = \"degraded\"
}
dmeventd {
}
EOF"

echo "instalando Cinder"
# Instalar e configurar Cinder
sudo apt install cinder-volume -y &>/dev/null
sudo apt install tgt -y &>/dev/null

echo "configurando o arquivo /etc/cinder/cinder.conf... "

sudo bash -c "cat <<EOF > /etc/cinder/cinder.conf
[DEFAULT]
transport_url = rabbit://openstack:$senha@${controller[0]}
auth_strategy = keystone
my_ip = ${host_array[1]}
enabled_backends = lvm
glance_api_servers = http://${controller[0]}:9292
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = lioadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes

[database]
connection = mysql+pymysql://cinder:$senha@${controller[0]}/cinder

[keystone_authtoken]
service_token_roles = service
service_token_roles_required = true
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = cinder
password = $senha

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = tgtadm

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

[service_user]
send_service_user_token = true
auth_url = http://${controller[0]}:5000
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = cinder
password = $senha
EOF"

# Configurar tgt
echo "configuração do arquivo /etc/tgt/conf.d/cinder.conf"
sudo bash -c 'cat <<EOF > /etc/tgt/conf.d/cinder.conf
include /var/lib/cinder/volumes/*
EOF'

echo "reiniciar serviços"
# Reiniciar serviços
sudo service tgt restart 
sudo service cinder-volume restart

echo "finalizado"
echo "faça a configuração de update do host controller"

fi

if [ $host = "controller" ]; then
echo "configuração do banco de dados para o cinder"
sudo mysql <<EOF
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$senha';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$senha';
FLUSH PRIVILEGES;
EOF

echo "Carregando variáveis de ambiente do OpenStack..."
source "$SCRIPT_DIR/admin-openrc"

echo "Criando usuário Cinder e atribuindo permissões..."
openstack user create --domain default --password "$senha" cinder
openstack role add --project service --user cinder admin
openstack role add --project service --user cinder service
echo "criando serviço de storage do Cinder"
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3

echo "criando endpoints do Cinder"
openstack endpoint create --region RegionOne volumev3 public http://${controller[0]}:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://${controller[0]}:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://${controller[0]}:8776/v3/%\(project_id\)s

echo "instalando Cinder"
sudo apt install cinder-api cinder-scheduler -y &>/dev/null

echo "configurando o arquivo "
sudo bash -c "cat <<EOF > /etc/cinder/cinder.conf
[DEFAULT]
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = lioadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
auth_strategy = keystone
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes
enabled_backends = lvm
transport_url = rabbit://openstack:$senha@${controller[0]}
my_ip = ${controller[1]}

[database]
connection = mysql+pymysql://cinder:$senha@${controller[0]}/cinder

[keystone_authtoken]
service_token_roles = service
service_token_roles_required = true
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = cinder
password = $senha

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

[service_user]
send_service_user_token = true
auth_url = http://${controller[0]}:5000
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = cinder
password = $senha
EOF"

echo "sincronizando banco de dados Cinder"
sudo -u cinder /bin/sh -c "cinder-manage db sync" &>/dev/null

echo "reiniciando o serviço do NOVA-API"
sudo service nova-api restart

echo "reiniciando serviços do Cinder e apache/keystone"
sudo service cinder-scheduler restart
sudo service apache2 restart

echo "configuração do Cinder finalizada"
fi