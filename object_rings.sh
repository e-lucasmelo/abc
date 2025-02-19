#OBJECT STORAGE
# no object storage node
sudo swift-init all start
#verificar funcionamento
sudo chcon -R system_u:object_r:swift_data_t:s0 /srv/node
