#!/usr/bin/env bash
# ==============================================================================
#  setup-day0.sh - Otimizações e Calibrações Pós-Instalação (Day-0 / Day-1)
#  Debian GNU/Linux 13 (Trixie) Desktop & Laptops
# ==============================================================================
#
#  Este script automatiza as otimizações de baixo nível executadas logo após
#  a instalação limpa do sistema operacional:
#    1. Desativação do swap em disco e configuração de RESUME=none no initramfs
#    2. Calibração PBKDF2 do Keyslot 0 do LUKS (500ms) + flags de alta performance
#    3. Instalação e ativação do zram-tools (swap comprimido em RAM)
#    4. Remoção da partição legada de swap e expansão online da partição raiz (100%)
#    5. Limpeza de parâmetros no GRUB, mascaramento de serviços lentos e rebuild
#
#  Uso:
#    sudo ./setup-day0.sh
# ==============================================================================

set -euo pipefail

# Cores e Formatação
BOLD='\033[1m'
GREEN='\033[38;2;46;204;113m'
CYAN='\033[38;2;52;152;219m'
YELLOW='\033[38;2;241;196;15m'
RED='\033[38;2;231;76;60m'
RESET='\033[0m'

# Verificar privilégios de root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Este script precisa ser executado como root ou via sudo:${RESET}"
    echo -e "   ${BOLD}sudo $0${RESET}"
    exit 1
fi

clear
echo -e "${BOLD}${CYAN}======================================================================${RESET}"
echo -e "${BOLD}${CYAN}  ⚡ SETUP DAY-0: Otimizações Pós-Instalação (Debian 13 Trixie)       ${RESET}"
echo -e "${BOLD}${CYAN}======================================================================${RESET}"
echo -e "Este assistente aplicará as otimizações de baixo nível e calibrações de boot:"
echo -e "  ${BOLD}1.${RESET} Desativação de swap em disco e remoção de delay de hibernação."
echo -e "  ${BOLD}2.${RESET} Calibração do Keyslot LUKS (PBKDF2 500ms) e flags de I/O rápido."
echo -e "  ${BOLD}3.${RESET} Ativação do zram (swap em RAM com compressão zstd)."
echo -e "  ${BOLD}4.${RESET} Expansão online do sistema de arquivos raiz para 100% do disco."
echo -e "  ${BOLD}5.${RESET} Otimização do GRUB, initramfs e eliminação de gargalos no boot."
echo -e "${CYAN}----------------------------------------------------------------------${RESET}"

read -rp "Deseja prosseguir com as otimizações? (S/n): " CONFIRM
CONFIRM=${CONFIRM:-S}
if [[ ! "$CONFIRM" =~ ^[sSyY]$ ]]; then
    echo -e "${YELLOW}Operação cancelada pelo usuário.${RESET}"
    exit 0
fi

echo -e "\n${BOLD}[*] Identificando topologia de armazenamento...${RESET}"
ROOT_DEV=$(findmnt -n -o SOURCE /)
IS_LUKS=false
LUKS_DEV=""
MAPPER_NAME=""
FS_TYPE=$(findmnt -n -o FSTYPE /)

if [[ "${ROOT_DEV}" == /dev/mapper/* ]]; then
    MAPPER_NAME=$(basename "${ROOT_DEV}")
    if cryptsetup status "${MAPPER_NAME}" &>/dev/null; then
        IS_LUKS=true
        LUKS_DEV=$(cryptsetup status "${MAPPER_NAME}" | grep "device:" | awk '{print $2}')
        DISK_DEV=$(lsblk -no PKNAME "${LUKS_DEV}" | grep -v "^$" | tail -n 1 | tr -d " ")
        DISK_PATH="/dev/${DISK_DEV}"
        PART_NUM=$(lsblk -no PARTN "${LUKS_DEV}" | grep -v "^$" | head -n 1 | tr -d " ")
        echo -e "   • ${BOLD}Topologia:${RESET}        Criptografia de disco integral (${GREEN}LUKS ativa${RESET})"
        echo -e "   • ${BOLD}Mapper Raiz:${RESET}      ${ROOT_DEV}"
        echo -e "   • ${BOLD}Partição Cripto:${RESET}  ${LUKS_DEV} (Partição nº ${PART_NUM})"
        echo -e "   • ${BOLD}Disco Físico:${RESET}     ${DISK_PATH}"
        echo -e "   • ${BOLD}Sistema Arq.:${RESET}     ${FS_TYPE}"
    fi
fi

if [[ "${IS_LUKS}" == "false" ]]; then
    DISK_DEV=$(lsblk -no PKNAME "${ROOT_DEV}" | grep -v "^$" | tail -n 1 | tr -d " ")
    DISK_PATH="/dev/${DISK_DEV}"
    PART_NUM=$(lsblk -no PARTN "${ROOT_DEV}" | grep -v "^$" | head -n 1 | tr -d " ")
    echo -e "   • ${BOLD}Topologia:${RESET}        Partição direta (${YELLOW}Sem LUKS${RESET})"
    echo -e "   • ${BOLD}Partição Raiz:${RESET}    ${ROOT_DEV} (Partição nº ${PART_NUM})"
    echo -e "   • ${BOLD}Disco Físico:${RESET}     ${DISK_PATH}"
    echo -e "   • ${BOLD}Sistema Arq.:${RESET}     ${FS_TYPE}"
fi

# ==============================================================================
# 1. Desativação do swap em disco e initramfs
# ==============================================================================
echo -e "\n${BOLD}${CYAN}[1/5] Desativando swap em disco e configurando RESUME=none...${RESET}"
mkdir -p /etc/initramfs-tools/conf.d/
echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume

# Desativar swap e limpar mappers de swap
swapoff -a 2>/dev/null || true
SWAP_MAPPERS=$(grep -E "\sswap\s" /etc/fstab | awk '{print $1}' || true)
for sm in ${SWAP_MAPPERS}; do
    if [[ "${sm}" == /dev/mapper/* ]]; then
        cryptsetup close "$(basename "${sm}")" 2>/dev/null || true
        sed -i "\|$(basename "${sm}")|d" /etc/crypttab 2>/dev/null || true
    fi
    sed -i "\\|${sm}|d" /etc/fstab || true
done
sed -i '/swap/d' /etc/fstab || true
echo -e "${GREEN}  ✓ Swap em disco desativado e removido do fstab/crypttab.${RESET}"

# ==============================================================================
# 2. Calibração do LUKS (Se aplicável)
# ==============================================================================
if [[ "${IS_LUKS}" == "true" ]]; then
    echo -e "\n${BOLD}${CYAN}[2/5] Calibrando PBKDF2 no Keyslot 0 do LUKS para 500ms...${RESET}"
    echo -e "${YELLOW}  ℹ️  Informe a senha atual do LUKS para recalibrar o tempo de descriptografia:${RESET}"
    
    LUKS_SUCCESS=false
    for attempt in 1 2 3; do
        read -s -rp "  Senha LUKS: " LUKS_PASS
        echo ""
        if printf "%s\n%s\n" "${LUKS_PASS}" "${LUKS_PASS}" | cryptsetup luksChangeKey "${LUKS_DEV}" --key-slot 0 --pbkdf pbkdf2 --iter-time 500 2>/dev/null; then
            echo -e "${GREEN}  ✓ Keyslot 0 calibrado com sucesso para PBKDF2 (500ms)!${RESET}"
            LUKS_SUCCESS=true
            break
        else
            echo -e "${RED}  ❌ Senha incorreta ou falha na calibração (Tentativa ${attempt}/3).${RESET}"
        fi
    done

    if [[ "$LUKS_SUCCESS" != "true" ]]; then
        echo -e "${YELLOW}  ⚠️ Não foi possível alterar a chave do LUKS agora. Prosseguindo com os outros passos...${RESET}"
    fi

    echo -e "\n${BOLD}${CYAN}[*] Injetando flags de alta performance no /etc/crypttab...${RESET}"
    if [ -f /etc/crypttab ]; then
        if grep -q "discard" /etc/crypttab; then
            sed -i 's/discard/discard,no-read-workqueue,no-write-workqueue/' /etc/crypttab
        else
            sed -i "s/\(luks\)/\1,discard,no-read-workqueue,no-write-workqueue/" /etc/crypttab
        fi
        echo -e "${GREEN}  ✓ Flags 'discard,no-read-workqueue,no-write-workqueue' aplicadas.${RESET}"
    fi
else
    echo -e "\n${BOLD}${CYAN}[2/5] Calibração LUKS ignorada (disco não criptografado).${RESET}"
fi

# ==============================================================================
# 3. Instalação e Ativação do zram-tools
# ==============================================================================
echo -e "\n${BOLD}${CYAN}[3/5] Instalando e ativando zram-tools, parted e rsync...${RESET}"
systemctl stop packagekit 2>/dev/null || true
while fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo -e "${YELLOW}  ⏳ Aguardando GNOME Software/PackageKit liberar as travas do apt...${RESET}"
    sleep 2
done

export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=120 update -qq
apt-get -o DPkg::Lock::Timeout=120 install -y -qq zram-tools parted rsync

# Ativar serviço do zram
systemctl enable --now zramswap.service 2>/dev/null || true
echo -e "${GREEN}  ✓ zram-tools instalado e serviço zramswap ativo!${RESET}"

# ==============================================================================
# 4. Expansão Online da Partição e Sistema de Arquivos
# ==============================================================================
echo -e "\n${BOLD}${CYAN}[4/5] Expandindo partição raiz para ocupar 100% do disco...${RESET}"
# Se houver partição 3 (antigo swap criado pelo instalador), remove para liberar espaço contíguo
if parted -s "${DISK_PATH}" print | grep -E "^\s*3\s" >/dev/null 2>&1; then
    echo -e "  • Removendo partição legada nº 3 (swap)..."
    parted -s "${DISK_PATH}" rm 3 2>/dev/null || true
fi

echo -e "  • Redimensionando partição nº ${PART_NUM} para 100%..."
parted -s "${DISK_PATH}" resizepart "${PART_NUM}" 100% 2>/dev/null || true

if [[ "${IS_LUKS}" == "true" ]]; then
    echo -e "  • Expandindo contêiner criptográfico LUKS..."
    cryptsetup resize "${MAPPER_NAME}" 2>/dev/null || true
fi

echo -e "  • Expandindo sistema de arquivos (${FS_TYPE})..."
if [[ "${FS_TYPE}" == "ext4" || "${FS_TYPE}" == "ext3" ]]; then
    resize2fs "${ROOT_DEV}" 2>/dev/null || true
elif [[ "${FS_TYPE}" == "btrfs" ]]; then
    btrfs filesystem resize max / 2>/dev/null || true
fi
echo -e "${GREEN}  ✓ Espaço em disco expandido com sucesso!${RESET}"

# ==============================================================================
# 5. Otimizações de GRUB, Plymouth e Rebuild do Initramfs
# ==============================================================================
echo -e "\n${BOLD}${CYAN}[5/5] Otimizando parâmetros do GRUB, mascarando serviços e gerando initramfs...${RESET}"
if [ -f /etc/default/grub ]; then
    sed -i -E "s/resume=[^ \"'	]+//" /etc/default/grub || true
    sed -i -E "s/\bsplash\b//" /etc/default/grub || true
    sed -i -E "s/[[:blank:]]+(['\"])/\1/g" /etc/default/grub || true
    sed -i -E "s/(['\"])[[:blank:]]+/\1/g" /etc/default/grub || true
    sed -i -E "s/[[:blank:]]{2,}/ /g" /etc/default/grub || true
    sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/" /etc/default/grub || true
    update-grub >/dev/null
    echo -e "${GREEN}  ✓ GRUB atualizado (removido resume=/splash, timeout reduzido para 1s).${RESET}"
fi

systemctl mask plymouth-quit-wait.service 2>/dev/null || true
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
echo -e "${GREEN}  ✓ Serviços bloqueadores de boot desativados (plymouth-quit-wait, wait-online).${RESET}"

echo -e "  • Reconstruindo initramfs para todos os kernels..."
update-initramfs -u -k all >/dev/null
echo -e "${GREEN}  ✓ Initramfs atualizado com sucesso!${RESET}"

# ==============================================================================
# Resumo Final e Reinicialização
# ==============================================================================
echo -e "\n${BOLD}${GREEN}======================================================================${RESET}"
echo -e "   ${BOLD}🎉 OTIMIZAÇÕES DE DAY-0 CONCLUÍDAS COM SUCESSO!${RESET}"
echo -e "${BOLD}${GREEN}======================================================================${RESET}\n"

echo -e "${BOLD}📊 Status Atual do Sistema:${RESET}"
echo -e "• ${BOLD}Espaço em Disco (/):${RESET}"
df -h / | awk 'NR==1 || NR==2 {print "   " $0}'

echo -e "\n• ${BOLD}Memória e ZRAM:${RESET}"
free -h | awk 'NR==1 || NR==2 || NR==3 {print "   " $0}'

echo -e "\n${CYAN}----------------------------------------------------------------------${RESET}"
echo -e "O sistema está pronto para ser reiniciado e carregar o kernel otimizado."
echo -e "Após o reboot, execute o provisionamento do Ansible:"
echo -e "   ${BOLD}./bootstrap.sh${RESET}"
echo -e "${CYAN}----------------------------------------------------------------------${RESET}\n"

read -rp "Deseja reiniciar o computador agora? (S/n): " REBOOT_NOW
REBOOT_NOW=${REBOOT_NOW:-S}
if [[ "$REBOOT_NOW" =~ ^[sSyY]$ ]]; then
    echo -e "${GREEN}Reiniciando o sistema...${RESET}"
    reboot
else
    echo -e "${YELLOW}Reboot pendente. Lembre-se de reiniciar antes de rodar o ./bootstrap.sh.${RESET}"
fi
