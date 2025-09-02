#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/variaveis.sh"

echo "Instalando o Horizon (OpenStack Dashboard)..."
sudo apt install openstack-dashboard -y &>/dev/null

echo "Configurando o arquivo /etc/openstack-dashboard/local_settings.py..."
sudo bash -c "cat <<EOF > /etc/openstack-dashboard/local_settings.py
import os
from django.utils.translation import gettext_lazy as _
from horizon.utils import secret_key
from openstack_dashboard.settings import HORIZON_CONFIG

DEBUG = False

LOCAL_PATH = os.path.dirname(os.path.abspath(__file__))

SECRET_KEY = secret_key.generate_or_read_from_file(\"/var/lib/openstack-dashboard/secret_key\")

CACHES = {
    \"default\": {
        \"BACKEND\": \"django.core.cache.backends.memcached.PyMemcacheCache\",
        \"LOCATION\": \"${controller[1]}:11211\",
    },
}

EMAIL_BACKEND = \"django.core.mail.backends.console.EmailBackend\"

OPENSTACK_HOST = \"${controller[1]}\"
OPENSTACK_KEYSTONE_URL = \"http://%s:5000/identity/v3\" % OPENSTACK_HOST
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_API_VERSIONS = {
    \"identity\": 3,
    \"image\": 2,
    \"volume\": 3,
}
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"default\"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"
OPENSTACK_NEUTRON_NETWORK = {
    \"enable_router\": True,
    \"enable_quotas\": True,
    \"enable_ipv6\": False,
    \"enable_distributed_router\": False,
    \"enable_ha_router\": False,
    \"enable_fip_topology_check\": True,
}
TIME_ZONE = \"UTC\"

LOGGING = {
    \"version\": 1,
    \"disable_existing_loggers\": False,
    \"formatters\": {
        \"console\": {
            \"format\": \"%(levelname)s %(name)s %(message)s\"
        },
        \"operation\": {
            \"format\": \"%(message)s\"
        },
    },
    \"handlers\": {
        \"null\": {
            \"level\": \"DEBUG\",
            \"class\": \"logging.NullHandler\",
        },
        \"console\": {
            \"level\": \"DEBUG\" if DEBUG else \"INFO\",
            \"class\": \"logging.StreamHandler\",
            \"formatter\": \"console\",
        },
        \"operation\": {
            \"level\": \"INFO\",
            \"class\": \"logging.StreamHandler\",
            \"formatter\": \"operation\",
        },
    },
    \"loggers\": {
        \"horizon\": {
            \"handlers\": [\"console\"],
            \"level\": \"DEBUG\",
            \"propagate\": False,
        },
        \"openstack_dashboard\": {
            \"handlers\": [\"console\"],
            \"level\": \"DEBUG\",
            \"propagate\": False,
        },
    },
}

SECURITY_GROUP_RULES = {
    \"all_tcp\": {
        \"name\": _(\"All TCP\"),
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"1\",
        \"to_port\": \"65535\",
    },
    \"ssh\": {
        \"name\": \"SSH\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"22\",
        \"to_port\": \"22\",
    },
    \"http\": {
        \"name\": \"HTTP\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"80\",
        \"to_port\": \"80\",
    },
    \"https\": {
        \"name\": \"HTTPS\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"443\",
        \"to_port\": \"443\",
    },
    \"mysql\": {
        \"name\": \"MYSQL\",
        \"ip_protocol\": \"tcp\",
        \"from_port\": \"3306\",
        \"to_port\": \"3306\",
    },
}

DEFAULT_THEME = \"default\"
WEBROOT = \"/horizon/\"
ALLOWED_HOSTS = [\"*\"]
COMPRESS_OFFLINE = False
EOF"

echo "Reiniciando serviço do Apache..."
sudo systemctl reload apache2

echo "Configuração do Horizon concluída com sucesso."