#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

if [ $host_temp = "controller" ]; then
echo "configurando o SWIFT..."

echo "criando usuário SWIFT no openstack..."
openstack user create --domain default --password "$senha" swift
openstack role add --project service --user swift admin
echo "criando serviço do SWIFT"
openstack service create --name swift --description "OpenStack Object Storage" object-store

echo "criando os endpoints do SWIFT"
openstack endpoint create --region RegionOne object-store public http://${controller[0]}:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store internal http://${controller[0]}:8080/v1/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store admin http://${controller[0]}:8080/v1

sudo apt install swift swift-proxy python3-swiftclient python3-keystoneclient python3-keystonemiddleware memcached -y &>/dev/null
sudo curl -o /etc/swift/proxy-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/proxy-server.conf-sample

sudo bash -c "cat <<EOF > /etc/swift/proxy-server.conf
[DEFAULT]
bind_port = 8080
user = swift
swift_dir = /etc/swift
[pipeline:main]
pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server
[app:proxy-server]
use = egg:swift#proxy
account_autocreate = True
[filter:tempauth]
use = egg:swift#tempauth
user_admin_admin = admin .admin .reseller_admin
user_admin_auditor = admin_ro .reseller_reader
user_test_tester = testing .admin
user_test_tester2 = testing2 .admin
user_test_tester3 = testing3
user_test2_tester2 = testing2 .admin
user_test5_tester5 = testing5 service
[filter:authtoken]
paste.filter_factory = keystonemiddleware.auth_token:filter_factory
www_authenticate_uri = http://${controller[0]}:5000
auth_url = http://${controller[0]}:5000
memcached_servers = ${controller[0]}:11211
auth_type = password
project_domain_id = default
user_domain_id = default
project_name = service
username = swift
password = $senha
delay_auth_decision = True
[filter:keystoneauth]
use = egg:swift#keystoneauth
operator_roles = admin,user,manager
[filter:s3api]
use = egg:swift#s3api
[filter:s3token]
use = egg:swift#s3token
reseller_prefix = AUTH_
delay_auth_decision = False
auth_uri = http://keystonehost:5000/v3
http_timeout = 10.0
[filter:healthcheck]
use = egg:swift#healthcheck
[filter:cache]
use = egg:swift#memcache
memcache_servers = controller:11211
[filter:ratelimit]
use = egg:swift#ratelimit
[filter:read_only]
use = egg:swift#read_only
[filter:domain_remap]
use = egg:swift#domain_remap
[filter:catch_errors]
use = egg:swift#catch_errors
[filter:cname_lookup]
use = egg:swift#cname_lookup
[filter:staticweb]
use = egg:swift#staticweb
[filter:tempurl]
use = egg:swift#tempurl
[filter:formpost]
use = egg:swift#formpost
[filter:name_check]
use = egg:swift#name_check
[filter:etag-quoter]
use = egg:swift#etag_quoter
[filter:list-endpoints]
use = egg:swift#list_endpoints
[filter:proxy-logging]
use = egg:swift#proxy_logging
[filter:bulk]
use = egg:swift#bulk
[filter:slo]
use = egg:swift#slo
[filter:dlo]
use = egg:swift#dlo
[filter:container-quotas]
use = egg:swift#container_quotas
[filter:account-quotas]
use = egg:swift#account_quotas
[filter:gatekeeper]
use = egg:swift#gatekeeper
[filter:container_sync]
use = egg:swift#container_sync
[filter:xprofile]
use = egg:swift#xprofile
[filter:versioned_writes]
use = egg:swift#versioned_writes
[filter:copy]
use = egg:swift#copy
[filter:keymaster]
use = egg:swift#keymaster
meta_version_to_write = 2
encryption_root_secret = changeme
[filter:kms_keymaster]
use = egg:swift#kms_keymaster
[filter:kmip_keymaster]
use = egg:swift#kmip_keymaster
[filter:encryption]
use = egg:swift#encryption
[filter:listing_formats]
use = egg:swift#listing_formats
[filter:symlink]
use = egg:swift#symlink
EOF"

sudo systemctl restart neutron* apach* open*

fi


if [[ "$host_temp" = "object" || ( "$computeObject" = "sim" && "$host_temp" = "compute" ) ]]; then
echo "Instalando xfsprogs e rsync..."
sudo apt install xfsprogs rsync -y &>/dev/null

echo "formatar disco em xfs"
sudo mkfs.xfs /dev/$disk_object1
#sudo mkfs.xfs /dev/$disk_object2

echo "criar a estrutura do diretorio montado"
sudo mkdir -p /srv/node/$disk_object1
#sudo mkdir -p /srv/node/$disk_object2

#sudo blkid

# Define o dispositivo (substitua /dev/sdX pelo seu dispositivo)
device_object1="/dev/$disk_object1"
#device_object2="/dev/$disk_object2"

# Obtém o UUID do dispositivo e armazena na variável UUID
UUID1=$(sudo blkid -s UUID -o value "$device_object1")
#UUID2=$(sudo blkid -s UUID -o value "$device_object2")

# echo "$UUID1"
echo "configurando o arquivo /etc/fstab..."
sudo bash -c "cat <<EOF >> /etc/fstab
UUID=$UUID1 /srv/node/$disk_object1 xfs noatime 0 2
#UUID=$UUID2 /srv/node/$disk_object2 xfs noatime 0 2
EOF"

sudo mount /srv/node/$disk_object1
#sudo mount /srv/node/$disk_object2

sudo bash -c "cat <<EOF > /etc/rsyncd.conf
uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = ${host_array[1]}

[account]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/account.lock

[container]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/container.lock

[object]
max connections = 2
path = /srv/node/
read only = False
lock file = /var/lock/object.lock
EOF"

echo "configurando o arquivo /etc/default/rsync..."
sudo bash -c "cat <<EOF > /etc/default/rsync
RSYNC_ENABLE=true
RSYNC_OPTS=''
RSYNC_NICE=''
EOF"

echo "reiniciando serviço do rsync..."
sudo service rsync start

echo "instalando swift e dependencias..."
sudo apt-get install swift swift-account swift-container swift-object -y &>/dev/null

echo "baixando os arquivo de configuração para accounting, container and object"
sudo curl -o /etc/swift/account-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/account-server.conf-sample &>/dev/null
sudo curl -o /etc/swift/container-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/container-server.conf-sample &>/dev/null
sudo curl -o /etc/swift/object-server.conf https://opendev.org/openstack/swift/raw/branch/master/etc/object-server.conf-sample &>/dev/null

echo "configurando o arquivo /etc/swift/account-server.conf..."
sudo bash -c "cat <<EOF > /etc/swift/account-server.conf
[DEFAULT]
bind_ip = ${host_array[1]}
bind_port = 6202
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = True
[pipeline:main]
pipeline = healthcheck recon account-server
[app:account-server]
use = egg:swift#account
[filter:healthcheck]
use = egg:swift#healthcheck
[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
[filter:backend_ratelimit]
use = egg:swift#backend_ratelimit
[account-replicator]
[account-auditor]
[account-reaper]
[filter:xprofile]
use = egg:swift#xprofile
EOF"

echo "configurando o arquivo /etc/swift/container-server.conf..."
sudo bash -c "cat <<EOF > /etc/swift/container-server.conf
[DEFAULT]
bind_ip = ${host_array[1]}
bind_port = 6201
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = True
[pipeline:main]
pipeline = healthcheck recon container-server
[app:container-server]
use = egg:swift#container
[filter:healthcheck]
use = egg:swift#healthcheck
[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
[filter:backend_ratelimit]
use = egg:swift#backend_ratelimit
[container-replicator]
[container-updater]
[container-auditor]
[container-sync]
[filter:xprofile]
use = egg:swift#xprofile
[container-sharder]
EOF"

echo "configurando o arquivo /etc/swift/object-server.conf..."
sudo bash -c "cat <<EOF > /etc/swift/object-server.conf
[DEFAULT]
bind_port = 6200
bind_ip = ${host_array[1]}
user = swift
swift_dir = /etc/swift
devices = /srv/node
mount_check = True
[pipeline:main]
pipeline = healthcheck recon object-server
[app:object-server]
use = egg:swift#object
[filter:healthcheck]
use = egg:swift#healthcheck
[filter:recon]
use = egg:swift#recon
recon_cache_path = /var/cache/swift
recon_lock_path = /var/lock
[filter:backend_ratelimit]
use = egg:swift#backend_ratelimit
[object-replicator]
[object-reconstructor]
[object-updater]
[object-auditor]
[object-expirer]
[filter:xprofile]
use = egg:swift#xprofile
[object-relinker]
EOF"

echo "alterando o proprietario da pasta /srv/node para o swift..."
sudo chown -R swift:swift /srv/node

echo "criando pasta /var/cache/swift e alterando o proprietário para o swift..."
sudo mkdir -p /var/cache/swift
sudo chown -R root:swift /var/cache/swift
sudo chmod -R 775 /var/cache/swift

echo "configuração do object storage finalizada, faça a configuração do ring no nó controller"
fi
