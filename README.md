# Configuração Manual do OpenStack

## Sobre

Este repositório contém scripts para ajudar na configuração manual do OpenStack, seguindo os passos sugeridos na documentação oficial:

- Guia de instalação: [OpenStack Install Guide](https://docs.openstack.org/install-guide/)
- Instalação mínima do OpenStack "Caracal" (2024.1): [Minimal Deployment](https://docs.openstack.org/install-guide/openstack-services.html#minimal-deployment-for-2024-1-caracal)

Os serviços instalados são:

- [Keystone](https://docs.openstack.org/keystone/2024.1/install/)
- [Glance](https://docs.openstack.org/glance/2024.1/install/)
- [Placement](https://docs.openstack.org/placement/2024.1/install/)
- [Nova](https://docs.openstack.org/nova/2024.1/install/)
- [Neutron (Networking Option 2: Self-service networks)](https://docs.openstack.org/neutron/2024.1/install/)
- [Horizon](https://docs.openstack.org/horizon/2024.1/install/)
- [Cinder](https://docs.openstack.org/cinder/2024.1/install/)

## Ambiente de Testes

O procedimento foi realizado em máquinas virtuais utilizando o [VirtualBox](https://www.virtualbox.org/), mas pode ser adaptado para máquinas físicas ou combinações de VMs e hosts físicos. A configuração mais básica envolve:

- 1 VM para o **controller**
- 1 ou mais VMs para **compute**

Os scripts permitem criar:

- 1 VM para o **controller**
- 3 VMs para **compute**
- 3 VMs para **storage**

## Requisitos

<!-- ### Hardware

```plaintext
| Função    | RAM  | CPUs | Armazenamento         |
|------------|------|------|----------------------|
| Controller | 3GB  | 2    | 10GB                 |
| Compute    | 3GB  | 4    | 50GB                 |
| Storage    | 3GB  | 2    | 10GB (sistema) + 50GB (volumes) |
``` -->

### Software

- [VirtualBox](https://www.virtualbox.org/)
- [Ubuntu Server 22.04 LTS](https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso)

### Redes

Crie as seguintes redes no VirtualBox:

1. **NAT (192.168.1.0/24)** - Rede de gerenciamento
2. **NAT (192.168.0.0/24)** - Rede provider
3. **Bridge** - Rede adicional (personalizável)

<!-- Todas as VMs devem ter **virtualização aninhada** habilitada. -->

## Configuração e Instalação

1. Instale a vm **controller**.

2. Clone o repositório:

   ```sh
   git clone https://github.com/e-lucasmelo/abc
   cd abc
   ```
3. Edite o arquivo de variáveis (**variaveis.sh**), preenchendo os dados conforme o necessário.

4. Torne os scripts executáveis:

   ```sh
   sudo chmod +x *.sh
   ```
5. execute o script (**config_hosts.sh**)
   ```
   sudo ./config_hosts.sh
   ```
6. Instale a VM **compute** 

6. repita os passos "2", "3", "4" e "5"

6. (Opcional) Instale as VMs **storage** e repita os passos "2", "3", "4" e "5" 

7. Volte para a VM **controller** e execute o script (**controllerUpdate.sh**):

   ```sh
   sudo ./controllerUpdate.sh
   ```

## Acesso ao OpenStack

no windows altere o arquivo host inserindo o ip definido para a rede bridge.

   ```'C:\Windows\System32\drivers\etc'
   192.168.0.111  controller
   ```

Se tudo correu bem, o OpenStack estará acessível pelo Horizon via navegador, usando a rede bridge:

```
http://controller/horizon/
```

Agora seu OpenStack está pronto para uso! 🎉

### Canais do youtube que foram de ajuda:

- Curso de openstack, Mateus Miller: https://www.youtube.com/watch?v=deiPxC8SOZk&list=PL0zspxm7AK_DsypYjkFVEU7ZxPn5gReKF
- Openstack Manual, Daniel Persson: https://www.youtube.com/watch?v=teWgCm6Aq1c&list=PLP2v7zU48xOJbK1HeOPxoBaxqBKtOAJB8
- Complete openstack tutorial, MrFares, https://www.youtube.com/playlist?list=PLwPU5FTUL-DbftrOlnfuDfNj0QlgQNFRL

