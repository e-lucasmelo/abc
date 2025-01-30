#!/bin/bash

# Atualizar pacotes
echo "atualizando server"
sudo apt update &>/dev/null
sudo apt upgrade -y &>/dev/null

echo "alterando hostname"
# Definir o nome do host
sudo hostnamectl set-hostname storage

echo "configurando hosts"
# Configurar /etc/hosts
cat <<EOF | sudo tee /etc/hosts
127.0.0.1   localhost
192.168.1.10   controller
192.168.1.20   compute1
192.168.1.30   storage
EOF

echo "ajustando fuso horario"
# Ajustar o timezone
sudo timedatectl set-timezone America/Sao_Paulo

echo "configurando rede"
# Configurar rede
cat <<EOF | sudo tee /etc/netplan/50-cloud-init.yaml
network:
    ethernets:
        enp0s3:
            addresses:
            - 192.168.1.30/24
            nameservers:
                addresses:
                - 181.213.132.2
                - 181.213.132.3
                search: []
            routes:
            -   to: default
                via: 192.168.1.1
                metric: 100
            -   to: 181.213.132.2
                via: 192.168.1.1
                metric: 100
            -   to: 181.213.132.3
                via: 192.168.1.1
                metric: 100
            dhcp6: false
            accept-ra: no
        enp0s8:
            dhcp4: false
            dhcp6: false
            accept-ra: no
        enp0s9:
            addresses: 
            - 192.168.0.85/24
            dhcp6: false
            accept-ra: no
    version: 2
EOF

echo "ajustando para configurações serem permanentes"
# Desabilitar configuração de rede do cloud-init
cat <<EOF | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network: {config: disabled}
EOF

echo "aplicando alteração"
# Aplicar configurações de rede
sudo netplan apply


echo "instalando chrony"
# Instalar e configurar Chrony
sudo apt install chrony -y &>/dev/null
cat <<EOF | sudo tee /etc/chrony/chrony.conf
server controller iburst
confdir /etc/chrony/conf.d
sourcedir /run/chrony-dhcp
sourcedir /etc/chrony/sources.d
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
leapsectz right/UTC
EOF

echo "reiniciando chrony"
# Reiniciar Chrony
sudo service chrony restart
sudo chronyc sources

echo "instalação do LVM"
# Configurar LVM
sudo apt install lvm2 thin-provisioning-tools -y &>/dev/null
sudo pvcreate /dev/sdb
sudo vgcreate cinder-volumes /dev/sdb

echo "configuração do arquivo /etc/lvm/lvm.conf"
# Configurar LVM
sudo bash -c 'cat <<EOF > /etc/lvm/lvm.conf
config {
        checks = 1
        abort_on_errors = 0
        profile_dir = "/etc/lvm/profile"
}
devices {
        dir = "/dev"
        scan = [ "/dev" ]
        filter = [ "a/sdb/", "r/.*/"]
        obtain_device_list_from_udev = 1
        external_device_info_source = "none"
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
        prefix = "  "
        activation = 0
        debug_classes = [ "memory", "devices", "io", "activation", "allocation", "metadata", "cache", "locking", "lvmpolld", "dbus" ]
}
backup {
        backup = 1
        backup_dir = "/etc/lvm/backup"
        archive = 1
        archive_dir = "/etc/lvm/archive"
        retain_min = 10
        retain_days = 30
}
shell {
        history_size = 100
}
global {
        umask = 077
        test = 0
        units = "r"
        si_unit_consistency = 1
        suffix = 1
        activation = 1
        proc = "/proc"
        etc = "/etc"
        wait_for_locks = 1
        locking_dir = "/run/lock/lvm"
        prioritise_write_locks = 1
        abort_on_internal_errors = 0
        metadata_read_only = 0
        mirror_segtype_default = "raid1"
        raid10_segtype_default = "raid10"
        sparse_segtype_default = "thin"
        use_lvmlockd = 0
        system_id_source = "none"
        use_lvmpolld = 1
        notify_dbus = 1
}
activation {
        checks = 0
        udev_sync = 1
        udev_rules = 1
        retry_deactivation = 1
        missing_stripe_filler = "error"
        raid_region_size = 2048
        raid_fault_policy = "warn"
        mirror_image_fault_policy = "remove"
        mirror_log_fault_policy = "allocate"
        snapshot_autoextend_threshold = 100
        snapshot_autoextend_percent = 20
        thin_pool_autoextend_threshold = 100
        thin_pool_autoextend_percent = 20
        monitoring = 1
        activation_mode = "degraded"
}
dmeventd {
}
EOF'

echo "instalando e configurando os parametros do Cinder"
# Instalar e configurar Cinder
sudo apt install cinder-volume tgt -y &>/dev/null
cat <<EOF | sudo tee  /etc/cinder/cinder.conf
[DEFAULT]
transport_url = rabbit://openstack:admin@controller
auth_strategy = keystone
my_ip = 192.168.1.30
enabled_backends = lvm
glance_api_servers = http://controller:9292
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
connection = mysql+pymysql://cinder:admin@controller/cinder

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = admin

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = tgtadm

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF

echo "configuração de tgt"
# Configurar tgt
cat <<EOF | sudo tee /etc/tgt/conf.d/cinder.conf
include /var/lib/cinder/volumes/*
EOF

echo "reiniciar serviços"
# Reiniciar serviços
sudo service tgt restart
sudo service cinder-volume restart

echo "finalizado"
echo "continuar configuração no controller"
