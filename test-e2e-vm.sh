#!/usr/bin/env bash
#
# test-e2e-vm.sh
# Script de orquestração para teste end-to-end em VM KVM/Libvirt
# Suporta ambientes criptografados com LUKS ou instalações padrão (sem criptografia)

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

VM_NAME="debian-testbed"
SNAPSHOT_NAME="base-clean"

echo -e "\n${BOLD}${BLUE}======================================================================${RESET}"
echo -e "   ${BOLD}🚀 TESTBED AUTOMATIZADO: ANSIBLE DEBIAN DESKTOP (KVM/LIBVIRT)${RESET}"
echo -e "${BOLD}${BLUE}======================================================================${RESET}\n"

echo -e "${CYAN}ℹ️  Este script realiza o provisionamento completo (Day-0 a Day-2) em uma VM de testes."
echo -e "   Pré-requisito: VM KVM com Debian 13 recém-instalado.${RESET}\n"

# 1. Verificar se a VM existe no Libvirt
if ! virsh --connect qemu:///system dominfo "${VM_NAME}" &>/dev/null; then
    echo -e "${YELLOW}⚠️  A máquina virtual '${VM_NAME}' não foi encontrada no Libvirt/KVM.${RESET}\n"
    echo -e "${BOLD}📋 Para provisionar a VM de testes automaticamente a partir da ISO:${RESET}\n"
    echo -e "   1. Coloque a imagem em ${BOLD}testbed/debian-live.iso${RESET} (ou deixe o script baixar)."
    echo -e "   2. Execute: ${BOLD}./setup-testbed-vm.sh${RESET}"
    echo -e "   3. Instale o Debian pelo Calamares."
    echo -e "   4. Execute este script (${BOLD}./test-e2e-vm.sh${RESET}) novamente!\n"
    exit 1
fi

# 2. Solicitar credenciais de forma segura e separada
echo -e "${BOLD}🔑 Configuração de Credenciais do Testbed:${RESET}"
read -rp "   👤 Usuário cadastrado na VM: " VM_USER

if [[ -z "${VM_USER}" ]]; then
    echo -e "${RED}❌ O nome de usuário não pode ser vazio.${RESET}"
    exit 1
fi

read -rsp "   🔒 Senha de login/sudo do usuário: " USER_PASSWORD
echo ""

if [[ -z "${USER_PASSWORD}" ]]; then
    echo -e "${RED}❌ A senha do usuário não pode ser vazia.${RESET}"
    exit 1
fi

read -rsp "   🔐 Senha de descriptografia do disco (LUKS) [Pressione Enter se for igual]: " LUKS_PASSWORD
echo ""
LUKS_PASSWORD="${LUKS_PASSWORD:-$USER_PASSWORD}"

echo ""

# 3. Verificar snapshots no Libvirt
echo -e "${BOLD}[1/6] Verificando snapshots da VM '${VM_NAME}'...${RESET}"
SNAPSHOT_LIST=$(virsh --connect qemu:///system snapshot-list "${VM_NAME}" --name 2>/dev/null || true)

if echo "${SNAPSHOT_LIST}" | grep -qw "${SNAPSHOT_NAME}"; then
    echo -e "${CYAN}📸 Snapshot limpo '${SNAPSHOT_NAME}' encontrado. Revertendo estado inicial...${RESET}"
    virsh --connect qemu:///system snapshot-revert "${VM_NAME}" "${SNAPSHOT_NAME}"
    echo -e "${GREEN}✅ Revertido com sucesso para '${SNAPSHOT_NAME}'.${RESET}"
else
    echo -e "${YELLOW}⚠️  Snapshot '${SNAPSHOT_NAME}' não encontrado.${RESET}"
    read -rp "   Deseja criar o snapshot limpo inicial '${SNAPSHOT_NAME}' agora a partir do estado atual da VM? (s/N): " CREATE_SNAP
    if [[ "${CREATE_SNAP,,}" == "s" || "${CREATE_SNAP,,}" == "sim" ]]; then
        echo -e "📸 Criando snapshot limpo '${SNAPSHOT_NAME}'..."
        if ! virsh --connect qemu:///system snapshot-create-as "${VM_NAME}" "${SNAPSHOT_NAME}" --description "Debian 13 limpo pos-instalacao" 2>/dev/null; then
            virsh --connect qemu:///system snapshot-create-as "${VM_NAME}" "${SNAPSHOT_NAME}" --disk-only --description "Debian 13 limpo pos-instalacao"
        fi
        echo -e "${GREEN}✅ Snapshot '${SNAPSHOT_NAME}' criado com sucesso!${RESET}"
    else
        echo -e "${CYAN}ℹ️  Prosseguindo com o estado atual da VM sem snapshot.${RESET}"
    fi
fi

# Garantir que a VM está ligada
VM_STATE=$(virsh --connect qemu:///system domstate "${VM_NAME}" 2>/dev/null || true)
if [[ "${VM_STATE}" != "executando" && "${VM_STATE}" != "running" ]]; then
    echo -e "${BOLD}Iniciando máquina virtual...${RESET}"
    virsh --connect qemu:///system start "${VM_NAME}"
fi

echo -e "${YELLOW}ℹ️  Se o console solicitar a senha de boot do LUKS, informe a senha configurada.${RESET}\n"

# 4. Obter IP e aguardar SSH
echo -e "${BOLD}[2/6] Aguardando inicialização do sistema e conectividade de rede (SSH)...${RESET}"
VM_IP=""
SSH_READY=false
for i in {1..60}; do
    VM_IP=$(virsh --connect qemu:///system domifaddr "${VM_NAME}" 2>/dev/null | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1 || true)
    if [[ -n "${VM_IP}" ]]; then
        # Testa se a porta 22 TCP está aberta sem tentar autenticar e sem gerar falhas no log
        if timeout 1 bash -c "</dev/tcp/${VM_IP}/22" &>/dev/null; then
            echo -e "\n${GREEN}✅ Porta SSH aberta na VM (IP: ${BOLD}${VM_IP}${RESET})${GREEN}.${RESET}"
            SSH_READY=true
            break
        fi
    fi
    echo -n "."
    sleep 2
done

if [[ "${SSH_READY}" != "true" ]]; then
    echo -e "\n${RED}❌ Não foi possível conectar na porta SSH (22) da VM após 120s.${RESET}"
    if [[ -n "${VM_IP}" ]]; then
        echo -e "${YELLOW}ℹ️  O IP '${VM_IP}' foi detectado, mas a porta 22 está recusando conexão.${RESET}"
        echo -e "${YELLOW}👉 No console da VM, certifique-se de que o SSH está instalado e ativo:${RESET}"
        echo -e "   ${BOLD}sudo apt update && sudo apt install -y openssh-server && sudo systemctl enable --now ssh${RESET}\n"
    else
        echo -e "${YELLOW}👉 Verifique se a VM concluiu o boot e obteve endereço IP via DHCP.${RESET}\n"
    fi
    exit 1
fi

# 4.1 Garantir par de chaves SSH local e copiar para a VM de forma confiável
if [[ ! -f "$HOME/.ssh/id_ed25519" && ! -f "$HOME/.ssh/id_rsa" ]]; then
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" <<< y &>/dev/null || true
fi

echo -e "${CYAN}🔑 Configurando autenticação por chave SSH na VM...${RESET}"
# Usa sshpass para injetar a chave sem tentativas repetitivas
sshpass -p "${USER_PASSWORD}" ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" &>/dev/null || true

# Configura sudo sem senha para o usuário do testbed na VM para execução autônoma
sshpass -p "${USER_PASSWORD}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" \
    "echo '${USER_PASSWORD}' | sudo -S sh -c 'echo \"${VM_USER} ALL=(ALL:ALL) NOPASSWD:ALL\" > /etc/sudoers.d/99-${VM_USER}-nopasswd && chmod 0440 /etc/sudoers.d/99-${VM_USER}-nopasswd'" &>/dev/null || true

# Testa conexão SSH com a chave
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=3 "${VM_USER}@${VM_IP}" "echo ready" &>/dev/null; then
    echo -e "${GREEN}✅ Autenticação SSH e permissões configuradas com sucesso!${RESET}\n"
else
    echo -e "${YELLOW}⚠️  Acesso SSH via chave concluído.${RESET}\n"
fi

# 4.2 Sincronizar relógio da VM com o Host imediatamente para evitar falhas OpenPGP no apt
echo -e "${BOLD}Sincronizando relógio da VM com o Host...${RESET}"
virsh --connect qemu:///system domtime "${VM_NAME}" --sync 2>/dev/null || true
HOST_UTC=$(date -u +"%Y-%m-%d %H:%M:%S")
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" \
    "sudo date -u -s '${HOST_UTC}' && sudo systemctl restart systemd-timesyncd 2>/dev/null || true"
echo -e "${GREEN}✅ Relógio da VM sincronizado: $(date)${RESET}\n"

# 5. Aplicar Otimizações de Day-0 / Day-1 com detecção 100% dinâmica de disco
echo -e "${BOLD}[3/6] Aplicando calibrações de baixo nível (Day-0 / Day-1)...${RESET}"
echo -e "${CYAN}ℹ️  Identificando dinamicamente disco, partição raiz e mapeamento (/dev/vda, /dev/nvme*, /dev/sda)...${RESET}"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" \
    bash -s -- "${LUKS_PASSWORD}" << 'REMOTE_SCRIPT'
set -euo pipefail

LUKS_PASS="$1"

echo "🔍 Detectando topologia de armazenamento..."
ROOT_DEV=$(findmnt -n -o SOURCE /)

# Verifica se o sistema raiz utiliza LUKS ou partição direta
IS_LUKS=false
if [[ "${ROOT_DEV}" == /dev/mapper/* ]]; then
    MAPPER_NAME=$(basename "${ROOT_DEV}")
    if sudo cryptsetup status "${MAPPER_NAME}" &>/dev/null; then
        IS_LUKS=true
        LUKS_DEV=$(sudo cryptsetup status "${MAPPER_NAME}" | grep device: | awk '{print $2}')
        DISK_DEV=$(lsblk -no PKNAME "${LUKS_DEV}" | grep -v "^$" | tail -n 1 | tr -d " ")
        DISK_PATH="/dev/${DISK_DEV}"
        PART_NUM=$(lsblk -no PARTN "${LUKS_DEV}" | grep -v "^$" | head -n 1 | tr -d " ")
        echo "   - Topologia:        Criptografia LUKS ativa"
        echo "   - Mapper Raiz:      ${ROOT_DEV}"
        echo "   - Partição LUKS:    ${LUKS_DEV} (Partição nº ${PART_NUM})"
        echo "   - Disco Físico:     ${DISK_PATH}"
    fi
fi

if [[ "${IS_LUKS}" == "false" ]]; then
    DISK_DEV=$(lsblk -no PKNAME "${ROOT_DEV}" | grep -v "^$" | tail -n 1 | tr -d " ")
    DISK_PATH="/dev/${DISK_DEV}"
    PART_NUM=$(lsblk -no PARTN "${ROOT_DEV}" | grep -v "^$" | head -n 1 | tr -d " ")
    echo "   - Topologia:        Partição direta (sem criptografia LUKS)"
    echo "   - Partição Raiz:    ${ROOT_DEV} (Partição nº ${PART_NUM})"
    echo "   - Disco Físico:     ${DISK_PATH}"
fi

# A. Desativação do swap em disco e initramfs
echo "⚙️ [1/6] Configurando RESUME=none no initramfs e limpando swap..."
echo "RESUME=none" | sudo tee /etc/initramfs-tools/conf.d/resume >/dev/null

# Desativar swap e fechar container criptografado do swap se existir
sudo swapoff -a 2>/dev/null || true
SWAP_MAPPERS=$(grep -E "\sswap\s" /etc/fstab | awk '{print $1}' || true)
for sm in ${SWAP_MAPPERS}; do
    if [[ "${sm}" == /dev/mapper/* ]]; then
        sudo cryptsetup close "$(basename "${sm}")" 2>/dev/null || true
        sudo sed -i "\|$(basename "${sm}")|d" /etc/crypttab 2>/dev/null || true
    fi
    sudo sed -i "\\|${sm}|d" /etc/fstab || true
done
sudo sed -i '/swap/d' /etc/fstab || true

# B. Se for LUKS, calibrar Slot 0 para 500ms e ajustar crypttab
if [[ "${IS_LUKS}" == "true" ]]; then
    echo "⚙️ [2/6] Calibrando PBKDF2 no Keyslot 0 do LUKS para 500ms..."
    printf "%s\n%s\n" "${LUKS_PASS}" "${LUKS_PASS}" | sudo cryptsetup luksChangeKey "${LUKS_DEV}" --key-slot 0 --pbkdf pbkdf2 --iter-time 500 2>/dev/null || true

    echo "⚙️ [3/6] Injetando flags de alta performance no /etc/crypttab..."
    sudo sed -i 's/discard/discard,no-read-workqueue,no-write-workqueue/' /etc/crypttab 2>/dev/null || true
else
    echo "⚙️ [2/6] Pulando calibração de chaves LUKS (disco não criptografado)."
fi

# C. Instalação do zram-tools
echo "⚙️ [4/6] Ativando zram-tools (swap comprimido em RAM)..."
sudo systemctl stop packagekit 2>/dev/null || true
while sudo fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ Aguardando GNOME/PackageKit liberar as travas do apt..."
    sleep 2
done
sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y -qq zram-tools parted rsync

# D. Expansão online da partição
echo "⚙️ [5/6] Expandindo partição raiz..."
# Se houver partição 3 (antigo swap), remove para liberar o disco
sudo parted -s "${DISK_PATH}" rm 3 2>/dev/null || true
sudo parted -s "${DISK_PATH}" resizepart "${PART_NUM}" 100% 2>/dev/null || true

if [[ "${IS_LUKS}" == "true" ]]; then
    sudo cryptsetup resize "${MAPPER_NAME}" 2>/dev/null || true
    sudo resize2fs "${ROOT_DEV}" 2>/dev/null || true
else
    sudo resize2fs "${ROOT_DEV}" 2>/dev/null || true
fi

# E. Limpeza do GRUB e otimizações de Userspace
echo "⚙️ [6/6] Ajustando parâmetros de boot do GRUB, Plymouth e initramfs..."
sudo sed -i -E 's/resume=[^ "	]+//' /etc/default/grub || true
sudo sed -i -E "s/\bsplash\b//" /etc/default/grub || true
sudo sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/" /etc/default/grub || true
sudo update-grub >/dev/null

sudo systemctl mask plymouth-quit-wait.service 2>/dev/null || true
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
sudo update-initramfs -u -k all >/dev/null

echo "✅ Calibrações de Day-0 concluídas com sucesso!"
REMOTE_SCRIPT

# 6. Reiniciar a VM
echo -e "\n${BOLD}[4/6] Reiniciando a VM para carregar o kernel e initramfs otimizados...${RESET}"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" "sudo reboot" 2>/dev/null || true

echo -e "${YELLOW}⏳ Aguardando VM reiniciar...${RESET}"
sleep 8

for i in {1..60}; do
    if timeout 1 bash -c "</dev/tcp/${VM_IP}/22" &>/dev/null; then
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=2 "${VM_USER}@${VM_IP}" "echo reboot_ok" &>/dev/null; then
            echo -e "${GREEN}✅ VM reiniciada e pronta para o Ansible!${RESET}\n"
            break
        fi
    fi
    echo -n "."
    sleep 2
done

# 7. Sincronizar o repositório local e pacotes Antigravity
echo -e "${BOLD}[5/6] Sincronizando repositório e instaladores para a VM...${RESET}"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" \
    "mkdir -p ~/du/dev/github/ansible-debian-desktop ~/Downloads"

# Copiar repositório atual via tar pipe (100% garantido e rápido, excluindo pasta testbed e ISOs)
tar -cf - --exclude='*.git*' --exclude='testbed' --exclude='*.iso' --exclude='*.qcow2' . | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" "tar -xf - -C ~/du/dev/github/ansible-debian-desktop/"

# Copiar binários do Antigravity (prioriza a pasta testbed/ e fallback para ~/Downloads)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANTIGRAVITY_FOUND=false

if compgen -G "${SCRIPT_DIR}/testbed/Antigravity*.tar.gz" > /dev/null; then
    echo -e "${CYAN}📦 Copiando pacotes do Antigravity de ${SCRIPT_DIR}/testbed/...${RESET}"
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${SCRIPT_DIR}/testbed"/Antigravity*.tar.gz "${VM_USER}@${VM_IP}:~/Downloads/"
    ANTIGRAVITY_FOUND=true
elif compgen -G "$HOME/Downloads/Antigravity*.tar.gz" > /dev/null; then
    echo -e "${CYAN}📦 Copiando pacotes do Antigravity de $HOME/Downloads/...${RESET}"
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$HOME/Downloads"/Antigravity*.tar.gz "${VM_USER}@${VM_IP}:~/Downloads/"
    ANTIGRAVITY_FOUND=true
fi

if [[ "$ANTIGRAVITY_FOUND" == "true" ]]; then
    echo -e "${GREEN}✅ Pacotes do Antigravity enviados para ~/Downloads na VM.${RESET}"
fi

echo -e "${GREEN}✅ Sincronização finalizada.${RESET}\n"

# 8. Executar o Bootstrap do Ansible
echo -e "${BOLD}[6/6] Disparando o provisionamento completo do Ansible (bootstrap.sh)...${RESET}\n"
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" \
    "cd ~/du/dev/github/ansible-debian-desktop && echo '${USER_PASSWORD}' | ./bootstrap.sh -e 'ansible_become_password=${USER_PASSWORD}'"

echo -e "\n${BOLD}${GREEN}======================================================================${RESET}"
echo -e "   ${BOLD}🎉 CICLO COMPLETO CONCLUÍDO COM SUCESSO!${RESET}"
echo -e "${BOLD}${GREEN}======================================================================${RESET}\n"

# Exibir relatório de boot final da VM
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@${VM_IP}" "systemd-analyze && free -h && df -h /"
