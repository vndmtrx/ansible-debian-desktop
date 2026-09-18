#!/usr/bin/env bash
#
# setup-testbed-vm.sh
# Cria a Máquina Virtual de Testes (debian-testbed) no KVM/Libvirt
# Utiliza a ISO testbed/debian-live.iso e volume COW (qcow2) de 100GB gerenciado pelo Libvirt (sem sudo)

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

VM_NAME="debian-testbed"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_PATH="${REPO_DIR}/testbed/debian-live.iso"
DISK_SIZE="100"
RAM_MB="8192"
CPUS="2"

echo -e "\n${BOLD}${BLUE}======================================================================${RESET}"
echo -e "   ${BOLD}🛠️  CRIAÇÃO DA VM DE TESTES KVM: ${VM_NAME}${RESET}"
echo -e "${BOLD}${BLUE}======================================================================${RESET}\n"

# 1. Verificar se a ISO existe em testbed/debian-live.iso
if [[ ! -f "${ISO_PATH}" ]]; then
    echo -e "${YELLOW}⚠️  A imagem ISO não foi encontrada em: ${BOLD}${ISO_PATH}${RESET}\n"
    read -rp "Deseja fazer o download automático da ISO do Debian Live GNOME agora? (S/n): " DOWNLOAD_CHOICE
    if [[ "${DOWNLOAD_CHOICE,,}" != "n" && "${DOWNLOAD_CHOICE,,}" != "nao" ]]; then
        echo -e "${CYAN}📥 Baixando Debian Live GNOME para ${ISO_PATH}...${RESET}"
        wget -c -O "${ISO_PATH}" \
            "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-13.7.0-amd64-gnome.iso"
        echo -e "${GREEN}✅ Download concluído com sucesso!${RESET}\n"
    else
        echo -e "${RED}❌ Coloque o arquivo ISO em '${ISO_PATH}' e execute este script novamente.${RESET}"
        exit 1
    fi
fi

# 2. Verificar se a VM já existe
if virsh --connect qemu:///system dominfo "${VM_NAME}" &>/dev/null; then
    echo -e "${YELLOW}⚠️  A VM '${VM_NAME}' já existe no Libvirt.${RESET}"
    read -rp "Deseja DESTRUIR e RECRIAR a VM do zero (apagará o disco antigo)? (s/N): " RECREATE_CHOICE
    if [[ "${RECREATE_CHOICE,,}" == "s" || "${RECREATE_CHOICE,,}" == "sim" ]]; then
        echo -e "🛑 Removendo VM anterior..."
        virsh --connect qemu:///system destroy "${VM_NAME}" 2>/dev/null || true
        virsh --connect qemu:///system undefine "${VM_NAME}" --nvram --remove-all-storage --snapshots-metadata 2>/dev/null || \
        virsh --connect qemu:///system undefine "${VM_NAME}" --nvram --remove-all-storage 2>/dev/null || true
        echo -e "${GREEN}✅ VM anterior removida.${RESET}\n"
    else
        echo -e "${CYAN}ℹ️  Operação cancelada. A VM existente foi mantida.${RESET}"
        exit 0
    fi
fi

# 3. Provisionar e inicializar a VM via virt-install (sem sudo, utilizando o pool gerenciado do libvirt)
echo -e "${BOLD}Provisionando e inicializando a VM via virt-install...${RESET}"
virt-install \
    --connect qemu:///system \
    --name "${VM_NAME}" \
    --vcpus "${CPUS}" \
    --memory "${RAM_MB}" \
    --disk pool=default,size="${DISK_SIZE}",format=qcow2,bus=virtio \
    --cdrom "${ISO_PATH}" \
    --os-variant debian12 \
    --boot uefi \
    --network network=default,model=virtio \
    --graphics spice,listen=127.0.0.1 \
    --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
    --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
    --noautoconsole

echo -e "\n${BOLD}${GREEN}======================================================================${RESET}"
echo -e "   ${BOLD}🎉 VM '${VM_NAME}' CRIADA E INICIADA COM SUCESSO!${RESET}"
echo -e "${BOLD}${GREEN}======================================================================${RESET}\n"

echo -e "${CYAN}📋 Próximos passos para instalação:${RESET}"
echo -e "   1. Abra o console gráfico da VM no ${BOLD}virt-manager${RESET} (ou execute: ${BOLD}virt-viewer -c qemu:///system ${VM_NAME}${RESET})."
echo -e "   2. No instalador Calamares:"
echo -e "      - Na tela de partição: marque ${BOLD}'Apagar disco'${RESET} (criptografia LUKS opcional)."
echo -e "      - Crie seu usuário e suas senhas."
echo -e "   3. Ao concluir a instalação, reinicie a VM e faça o primeiro login."
echo -e "   4. ${BOLD}${YELLOW}Abra o terminal na VM e instale/inicie o SSH Server:${RESET}"
echo -e "      ${BOLD}sudo apt update && sudo apt install -y openssh-server && sudo ssh-keygen -A && sudo systemctl enable --now ssh${RESET}"
echo -e "   5. No seu Host, execute o script de automação completa: ${BOLD}./test-e2e-vm.sh${RESET}\n"
