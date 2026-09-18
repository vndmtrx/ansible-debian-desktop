#!/usr/bin/env bash
# ==============================================================================
# backup.sh - Utilitário de Backup de Segurança e Personalizações do Sistema
#
# Coleta:
#   - Credenciais e configurações SSH (~/.ssh)
#   - Chaveiro GnuPG (chaves públicas, secretas e ownertrust)
#   - GNOME Keyrings (~/.local/share/keyrings)
#   - Configurações do Git (~/.gitconfig e ~/.config/git)
#   - Dumps cirúrgicos do GNOME (extensões, atalhos de janelas, layout e interface)
#
# Processamento:
#   - Compacta em .tar.bz2
#   - Criptografa com senha usando GPG simétrico (AES-256) -> .tar.bz2.gpg
#   - Gera checksum SHA-256 e assinatura digital desanexada GPG (.asc)
#   - Salva em ~/du/backups/YYYYMMDD_HHMM.tar.bz2.gpg
#   - Sincroniza opcionalmente com /mnt/ventoy/backup/ ou diretório informado
# ==============================================================================
set -euo pipefail

BOLD='\033[1m'
RESET='\033[0m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
RED='\033[31m'
DIM='\033[2m'

BACKUP_BASE_DIR="${HOME}/du/backups"
STAGE_DIR=""

cleanup_temp() {
    if [[ -n "${STAGE_DIR:-}" && -d "${STAGE_DIR:-}" ]]; then
        rm -rf "${STAGE_DIR}"
        STAGE_DIR=""
    fi
}
trap cleanup_temp EXIT INT TERM

print_header() {
    echo -e "${BOLD}${BLUE}====================================================${RESET}"
    echo -e "${BOLD}${BLUE}   🔒 Utilitário de Backup de Segurança & Desktop  ${RESET}"
    echo -e "${BOLD}${BLUE}====================================================${RESET}"
}

usage() {
    print_header
    local exit_code="${1:-1}"
    echo -e "${BOLD}Uso:${RESET} $0 [opções] [DIRETÓRIO_EXTRA_DESTINO]"
    echo ""
    echo -e "  Cria um backup criptografado em ${CYAN}${BACKUP_BASE_DIR}/YYYYMMDD_HHMM.tar.bz2.gpg${RESET}"
    echo -e "  e replica automaticamente para o pendrive Ventoy se montado."
    echo ""
    echo -e "  ${BOLD}Exemplos:${RESET}"
    echo -e "    $0                       # Executa o backup padrão em ~/du/backups"
    echo -e "    $0 /mnt/ventoy/backup    # Salva em ~/du/backups e copia para /mnt/ventoy/backup"
    echo ""
    exit "${exit_code}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage 0
fi

EXTRA_DEST_DIR="${1:-}"

print_header
timestamp=$(date +%Y%m%d_%H%M%S)
archive_base="${timestamp}.tar.bz2"
encrypted_archive="${archive_base}.gpg"
archive_path="${BACKUP_BASE_DIR}/${encrypted_archive}"
sha_path="${archive_path}.sha256"
sig_path="${archive_path}.asc"

echo -e "${BOLD}Iniciando rotina de backup de segurança...${RESET}"
echo -e "  - Destino principal: ${CYAN}${archive_path}${RESET}"
echo ""

mkdir -p "${BACKUP_BASE_DIR}"
chmod 700 "${BACKUP_BASE_DIR}"

STAGE_DIR=$(mktemp -d -t sec_backup_stage_XXXXXX)
chmod 700 "${STAGE_DIR}"

# 1. Git
echo -e "  ${BOLD}${BLUE}[1/5] Coletando configurações do Git...${RESET}"
mkdir -p "${STAGE_DIR}/git"
git_found=0
if [[ -f "${HOME}/.gitconfig" ]]; then
    cp -p "${HOME}/.gitconfig" "${STAGE_DIR}/git/"
    git_user=$(git config --file "${HOME}/.gitconfig" user.name 2>/dev/null || echo "não definido")
    git_email=$(git config --file "${HOME}/.gitconfig" user.email 2>/dev/null || echo "não definido")
    echo -e "    ${GREEN}✔${RESET} ~/.gitconfig (${CYAN}${git_user} <${git_email}>${RESET})"
    git_found=1
fi
if [[ -d "${HOME}/.config/git" ]]; then
    cp -a "${HOME}/.config/git" "${STAGE_DIR}/git/"
    echo -e "    ${GREEN}✔${RESET} ~/.config/git"
    git_found=1
fi
if [[ "${git_found}" -eq 0 ]]; then
    echo -e "    ${DIM}Nenhuma configuração Git encontrada.${RESET}"
fi
echo ""

# 2. SSH
echo -e "  ${BOLD}${BLUE}[2/5] Coletando credenciais e configurações SSH...${RESET}"
mkdir -p "${STAGE_DIR}/ssh"
if [[ -d "${HOME}/.ssh" ]]; then
    cp -a "${HOME}/.ssh/." "${STAGE_DIR}/ssh/"
    ssh_files=0
    while IFS= read -r -d '' sfile; do
        rel_path="${sfile#"${HOME}/.ssh/"}"
        fsize=$(du -h "${sfile}" 2>/dev/null | awk '{print $1}')
        if [[ "${rel_path}" == id_* && "${rel_path}" != *.pub ]]; then
            echo -e "    ${GREEN}✔${RESET} 🔑 Chave privada: ${YELLOW}~/.ssh/${rel_path}${RESET} (${fsize})"
        elif [[ "${rel_path}" == *.pub ]]; then
            echo -e "    ${GREEN}✔${RESET} 📄 Chave pública: ${CYAN}~/.ssh/${rel_path}${RESET} (${fsize})"
        else
            echo -e "    ${GREEN}✔${RESET} 📁 Arquivo SSH:   ~/.ssh/${rel_path} (${fsize})"
        fi
        ssh_files=$((ssh_files + 1))
    done < <(find "${HOME}/.ssh" -type f -print0 2>/dev/null | sort -z)
    if [[ "${ssh_files}" -eq 0 ]]; then
        echo -e "    ${DIM}Nenhum arquivo encontrado em ~/.ssh.${RESET}"
    fi
else
    echo -e "    ${DIM}Nenhum diretório ~/.ssh encontrado.${RESET}"
fi
echo ""

# 3. GnuPG
echo -e "  ${BOLD}${BLUE}[3/5] Exportando chaves e base de confiança GnuPG...${RESET}"
mkdir -p "${STAGE_DIR}/gnupg"
if command -v gpg &>/dev/null; then
    if gpg --list-keys 2>/dev/null | grep -q 'pub'; then
        gpg --armor --export > "${STAGE_DIR}/gnupg/chaves_publicas.asc" 2>/dev/null || true
        echo -e "    ${GREEN}✔${RESET} Chaves públicas GPG exportadas."
    else
        echo -e "    ${DIM}Nenhuma chave pública GPG encontrada.${RESET}"
    fi

    if gpg --list-secret-keys 2>/dev/null | grep -q 'sec'; then
        echo -e "    ${YELLOW}🔑 O GPG solicitará autorização para exportar as chaves privadas...${RESET}"
        if gpg --armor --export-secret-keys > "${STAGE_DIR}/gnupg/chaves_privadas.asc" 2>/dev/null; then
            echo -e "    ${GREEN}✔${RESET} Chaves privadas GPG exportadas."
        else
            echo -e "    ${RED}✖ Falha ou cancelamento na exportação das chaves privadas GPG.${RESET}"
        fi
    else
        echo -e "    ${DIM}Nenhuma chave privada GPG encontrada.${RESET}"
    fi

    gpg --export-ownertrust > "${STAGE_DIR}/gnupg/confianca_trust.txt" 2>/dev/null || true
    echo -e "    ${GREEN}✔${RESET} Base de confiança (ownertrust) exportada."
else
    echo -e "    ${RED}✖ Utilitário gpg não encontrado.${RESET}"
fi
echo ""

# 4. GNOME Keyring & Dumps Cirúrgicos Dconf
echo -e "  ${BOLD}${BLUE}[4/5] Coletando GNOME Keyring e preferências cirúrgicas do Desktop...${RESET}"
mkdir -p "${STAGE_DIR}/keyrings" "${STAGE_DIR}/gnome"

if [[ -d "${HOME}/.local/share/keyrings" ]]; then
    cp -a "${HOME}/.local/share/keyrings/." "${STAGE_DIR}/keyrings/"
    echo -e "    ${GREEN}✔${RESET} Chaveiros do GNOME Keyring coletados (~/.local/share/keyrings)"
fi

if command -v dconf &>/dev/null; then
    # Dumps pontuais e cirúrgicos (idênticos à granularidade do Ansible)
    dconf dump /org/gnome/shell/extensions/ > "${STAGE_DIR}/gnome/extensoes.dconf"
    dconf dump /org/gnome/desktop/background/ > "${STAGE_DIR}/gnome/background.dconf"
    dconf dump /org/gnome/desktop/interface/ > "${STAGE_DIR}/gnome/interface.dconf"
    dconf dump /org/gnome/desktop/wm/ > "${STAGE_DIR}/gnome/gerenciador_janelas.dconf"
    dconf dump /org/gnome/mutter/ > "${STAGE_DIR}/gnome/mutter.dconf"
    dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "${STAGE_DIR}/gnome/atalhos_customizados.dconf"
    echo -e "    ${GREEN}✔${RESET} Dumps cirúrgicos de dconf gerados (extensões, atalhos, barra e janelas)"
else
    echo -e "    ${DIM}Utilitário dconf não encontrado.${RESET}"
fi
echo ""

# 5. Compactação e Criptografia Simétrica com Senha
echo -e "  ${BOLD}${BLUE}[5/5] Compactando e protegendo com criptografia simétrica (AES-256)...${RESET}"
temp_tar=$(mktemp -t raw_sec_backup_XXXXXX.tar.bz2)
tar -cjf "${temp_tar}" -C "${STAGE_DIR}" .

echo -e "    ${YELLOW}🔑 Digite a senha mestra para proteger o arquivo de backup:${RESET}"
gpg --symmetric --cipher-algo AES256 --output "${archive_path}" "${temp_tar}"
rm -f "${temp_tar}"

# Geração de Checksum SHA-256
(
    cd "${BACKUP_BASE_DIR}"
    sha256sum "${encrypted_archive}" > "${encrypted_archive}.sha256"
)
echo -e "    ${GREEN}✔${RESET} Checksum SHA-256 gerado: ${encrypted_archive}.sha256"

# Assinatura digital GPG desanexada
if command -v gpg &>/dev/null; then
    if gpg --armor --detach-sign "${archive_path}" 2>/dev/null; then
        echo -e "    ${GREEN}✔${RESET} Assinatura digital GPG (.asc) criada."
    else
        echo -e "    ${DIM}Assinatura digital não gerada (chave indisponível ou cancelada).${RESET}"
    fi
fi

chmod 600 "${archive_path}" "${sha_path}" 2>/dev/null || true
if [[ -f "${sig_path}" ]]; then
    chmod 600 "${sig_path}"
fi

# Replicação para destino extra (apenas se informado explicitamente via argumento)
if [[ -n "${EXTRA_DEST_DIR}" ]]; then
    echo ""
    echo -e "  ${BOLD}Replicando cópia de segurança para o destino solicitado:${RESET} ${CYAN}${EXTRA_DEST_DIR}${RESET}"
    mkdir -p "${EXTRA_DEST_DIR}"
    cp -p "${archive_path}" "${sha_path}" "${EXTRA_DEST_DIR}/"
    if [[ -f "${sig_path}" ]]; then
        cp -p "${sig_path}" "${EXTRA_DEST_DIR}/"
    fi
    sync
    echo -e "    ${GREEN}✔${RESET} Cópia sincronizada em ${EXTRA_DEST_DIR}."
fi

echo ""
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}🎉 Backup concluído e criptografado com sucesso!    ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "  📦 Arquivo principal: ${BOLD}${archive_path}${RESET}"
ls -lh "${archive_path}" "${sha_path}" 2>/dev/null | awk '{printf "     - %-10s %s\n", $5, $9}'
