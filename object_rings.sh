sudo curl -o /etc/swift/swift.conf https://opendev.org/openstack/swift/raw/branch/master/etc/swift.conf-sample
sleep 2

sudo bash -c "cat <<EOF > /etc/swift/swift.conf
[swift-hash]
swift_hash_path_suffix = $senha
swift_hash_path_prefix = $senha
[storage-policy:0]
name = Policy-0
default = yes
aliases = yellow, orange
[swift-constraints]
EOF"

sudo chown -R root:swift /etc/swift

#CONTROLLER
#sudo service memcached restart
#sudo service swift-proxy restart #verificar o nome do serviço

#OBJECT STORAGE
# no object storage node
sudo swift-init all start

#CONTROLLER
#verificar funcionamento
sudo chcon -R system_u:object_r:swift_data_t:s0 /srv/node
