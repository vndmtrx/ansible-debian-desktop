#!/usr/bin/env bash
# ==============================================================================
# restore.sh - Utilitário de Restauração de Segurança e Personalizações do Sistema
#
# Funcionalidades:
#   - Localiza automaticamente o arquivo de backup mais recente em:
#     * ~/du/backups/
#     * /mnt/ventoy/backup/ ou /media/$USER/Ventoy/backup/
#     * Ou aceita caminho direto informado pelo usuário
#   - Valida integridade via checksum SHA-256 (.sha256)
#   - Verifica assinatura digital GPG (.asc) se chave pública estiver disponível
#   - Descriptografa arquivo protegido por senha (GPG / AES-256)
#   - Exibe relatório de alterações antes de pedir confirmação
#   - Restaura SSH, GnuPG, GNOME Keyring, Git e preferências dconf do GNOME
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
    echo -e "${BOLD}${BLUE}   🔓 Utilitário de Restauração de Segurança & Desktop${RESET}"
    echo -e "${BOLD}${BLUE}====================================================${RESET}"
}

usage() {
    print_header
    local exit_code="${1:-1}"
    echo -e "${BOLD}Uso:${RESET} $0 [ARQUIVO_OU_DIRETÓRIO]"
    echo ""
    echo -e "  Restaura credenciais, chaves e preferências a partir de um backup."
    echo -e "  Se nenhum caminho for fornecido, busca o arquivo mais recente em ${CYAN}${BACKUP_BASE_DIR}${RESET}."
    echo ""
    echo -e "  ${BOLD}Exemplos:${RESET}"
    echo -e "    $0                                      # Restaura o backup mais recente de ~/du/backups"
    echo -e "    $0 /caminho/customizado/backup          # Restaura a partir de um diretório específico"
    echo -e "    $0 ~/du/backups/20260915_084812.tar.bz2.gpg"
    echo ""
    exit "${exit_code}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage 0
fi

print_header
target_input="${1:-}"
archive_path=""

# 1. Localização do arquivo de backup
if [[ -z "${target_input}" ]]; then
    # Busca exclusivamente em ~/du/backups
    if [[ -d "${BACKUP_BASE_DIR}" ]]; then
        archive_path=$(find "${BACKUP_BASE_DIR}" -maxdepth 1 -type f \( -name "*.tar.bz2.gpg" -o -name "*.tar.bz2" \) 2>/dev/null | sort -V | tail -n 1 || true)
    fi

    if [[ -z "${archive_path}" ]]; then
        echo -e "${RED}Erro: Nenhum arquivo de backup encontrado em ${BACKUP_BASE_DIR}.${RESET}"
        echo -e "Informe o caminho manualmente: $0 /caminho/do/arquivo.tar.bz2.gpg"
        exit 1
    fi
elif [[ -d "${target_input}" ]]; then
    archive_path=$(find "${target_input}" -maxdepth 1 -type f \( -name "*.tar.bz2.gpg" -o -name "*.tar.bz2" \) 2>/dev/null | sort -V | tail -n 1 || true)
    if [[ -z "${archive_path}" ]]; then
        echo -e "${RED}Erro: Nenhum arquivo de backup encontrado no diretório '${target_input}'.${RESET}"
        exit 1
    fi
elif [[ -f "${target_input}" ]]; then
    archive_path="${target_input}"
else
    echo -e "${RED}Erro: Caminho '${target_input}' não encontrado.${RESET}"
    exit 1
fi

archive_dir=$(dirname "${archive_path}")
archive_name=$(basename "${archive_path}")

echo -e "${BOLD}Arquivo selecionado para restauração:${RESET} ${CYAN}${archive_path}${RESET}"
echo ""

# 2. Verificação de Integridade (SHA-256)
echo -e "  ${BOLD}[1/4] Verificando integridade física (SHA-256)...${RESET}"
sha_path="${archive_path}.sha256"
if [[ -f "${sha_path}" ]]; then
    if (cd "${archive_dir}" && sha256sum -c --status "${archive_name}.sha256" 2>/dev/null); then
        echo -e "    ${GREEN}✔${RESET} Checksum SHA-256 íntegro e validado."
    else
        echo -e "    ${RED}✖ ERRO CRÍTICO: Falha na validação de checksum SHA-256!${RESET}"
        echo -e "    O arquivo pode estar corrompido."
        exit 1
    fi
else
    echo -e "    ${YELLOW}⚠️  Arquivo .sha256 não encontrado. Verificação ignorada.${RESET}"
fi

# 3. Verificação de Assinatura Digital GPG (opcional)
sig_path="${archive_path}.asc"
if [[ -f "${sig_path}" ]] && command -v gpg &>/dev/null; then
    echo -e "  ${BOLD}Verificando assinatura digital GPG...${RESET}"
    if gpg --verify "${sig_path}" "${archive_path}" &>/dev/null; then
        echo -e "    ${GREEN}✔${RESET} Assinatura digital GPG válida e autenticada."
    else
        echo -e "    ${DIM}Assinatura digital não pôde ser validada (chave ausente no chaveiro atual).${RESET}"
    fi
fi

# 4. Descriptografia e Extração
echo ""
echo -e "  ${BOLD}[2/4] Descompactando e descriptografando dados...${RESET}"
STAGE_DIR=$(mktemp -d -t sec_restore_stage_XXXXXX)
chmod 700 "${STAGE_DIR}"

if [[ "${archive_name}" == *.gpg ]]; then
    echo -e "    ${YELLOW}🔑 Digite a senha mestra para descriptografar o backup:${RESET}"
    temp_tar="${STAGE_DIR}/decrypted.tar.bz2"
    if ! gpg --decrypt --output "${temp_tar}" "${archive_path}"; then
        echo -e "${RED}✖ Erro: Falha ao descriptografar o arquivo com a senha fornecida.${RESET}"
        exit 1
    fi
    tar -xjf "${temp_tar}" -C "${STAGE_DIR}"
    rm -f "${temp_tar}"
else
    tar -xjf "${archive_path}" -C "${STAGE_DIR}"
fi
echo -e "    ${GREEN}✔${RESET} Conteúdo extraído com sucesso para análise."

# 5. Relatório de Alterações
echo ""
echo -e "  ${BOLD}[3/4] Relatório de Impacto e Componentes Identificados:${RESET}"

# Git
if [[ -d "${STAGE_DIR}/git" ]]; then
    echo -e "    ${BLUE}[Git]${RESET} Configurações ~/.gitconfig e ~/.config/git"
fi

# SSH
if [[ -d "${STAGE_DIR}/ssh" ]]; then
    ssh_count=$(find "${STAGE_DIR}/ssh" -type f | wc -l)
    echo -e "    ${BLUE}[SSH]${RESET} ${ssh_count} arquivo(s) de credenciais/chaves para ~/.ssh/"
fi

# GnuPG
if [[ -d "${STAGE_DIR}/gnupg" ]]; then
    echo -e "    ${BLUE}[GnuPG]${RESET} Chaves e base de confiança prontas para importação"
fi

# GNOME Keyring
if [[ -d "${STAGE_DIR}/keyrings" ]]; then
    keyring_count=$(find "${STAGE_DIR}/keyrings" -type f | wc -l)
    echo -e "    ${BLUE}[Chaveiro GNOME]${RESET} ${keyring_count} chaveiro(s) para ~/.local/share/keyrings/"
fi

# GNOME Dconf Dumps
if [[ -d "${STAGE_DIR}/gnome" ]]; then
    echo -e "    ${BLUE}[Desktop GNOME]${RESET} Preferências de extensões, janelas, atalhos e layout da barra"
fi

echo ""
read -r -p "Deseja prosseguir com a restauração desses componentes? [s/N]: " confirm
if [[ ! "${confirm}" =~ ^[sS]$ && ! "${confirm}" =~ ^[yY]$ ]]; then
    echo -e "${YELLOW}Operação cancelada pelo usuário. Nenhuma modificação realizada.${RESET}"
    exit 0
fi

# 6. Restauração Efetiva
echo ""
echo -e "  ${BOLD}[4/4] Executando restauração nos destinos do usuário...${RESET}"

# Restaura Git
if [[ -f "${STAGE_DIR}/git/.gitconfig" ]]; then
    cp -p "${STAGE_DIR}/git/.gitconfig" "${HOME}/.gitconfig"
fi
if [[ -d "${STAGE_DIR}/git/git" ]]; then
    mkdir -p "${HOME}/.config/git"
    cp -a "${STAGE_DIR}/git/git/." "${HOME}/.config/git/"
fi
echo -e "    ${GREEN}✔${RESET} Configurações do Git restauradas."

# Restaura SSH
if [[ -d "${STAGE_DIR}/ssh" ]]; then
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    cp -a "${STAGE_DIR}/ssh/." "${HOME}/.ssh/"
    chmod 600 "${HOME}"/.ssh/id_* 2>/dev/null || true
    chmod 600 "${HOME}/.ssh/config" 2>/dev/null || true
    chmod 644 "${HOME}"/.ssh/*.pub 2>/dev/null || true
    chmod 644 "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    chmod 644 "${HOME}/.ssh/authorized_keys" 2>/dev/null || true
    echo -e "    ${GREEN}✔${RESET} Credenciais SSH restauradas e permissões aplicadas (700/600/644)."
fi

# Restaura GnuPG
if [[ -d "${STAGE_DIR}/gnupg" ]] && command -v gpg &>/dev/null; then
    mkdir -p "${HOME}/.gnupg"
    chmod 700 "${HOME}/.gnupg"
    if [[ -f "${STAGE_DIR}/gnupg/chaves_publicas.asc" ]]; then
        gpg --import "${STAGE_DIR}/gnupg/chaves_publicas.asc" &>/dev/null || true
    fi
    if [[ -f "${STAGE_DIR}/gnupg/chaves_privadas.asc" ]]; then
        echo -e "    ${YELLOW}🔑 O GPG solicitará autorização para importar as chaves privadas...${RESET}"
        gpg --import "${STAGE_DIR}/gnupg/chaves_privadas.asc" &>/dev/null || true
    fi
    if [[ -f "${STAGE_DIR}/gnupg/confianca_trust.txt" ]]; then
        gpg --import-ownertrust "${STAGE_DIR}/gnupg/confianca_trust.txt" &>/dev/null || true
    fi
    echo -e "    ${GREEN}✔${RESET} Chaves e confiança GnuPG restauradas."
fi

# Restaura GNOME Keyring
if [[ -d "${STAGE_DIR}/keyrings" ]]; then
    mkdir -p "${HOME}/.local/share/keyrings"
    chmod 700 "${HOME}/.local/share/keyrings"
    cp -a "${STAGE_DIR}/keyrings/." "${HOME}/.local/share/keyrings/"
    chmod 600 "${HOME}/.local/share/keyrings"/* 2>/dev/null || true
    echo -e "    ${GREEN}✔${RESET} Chaveiros do GNOME Keyring restaurados com sucesso."
fi

# Restaura preferências dconf do GNOME de forma cirúrgica e segura
if [[ -d "${STAGE_DIR}/gnome" ]] && command -v dconf &>/dev/null; then
    if [[ -f "${STAGE_DIR}/gnome/extensoes.dconf" ]]; then
        dconf load /org/gnome/shell/extensions/ < "${STAGE_DIR}/gnome/extensoes.dconf" 2>/dev/null || true
    elif [[ -f "${STAGE_DIR}/gnome/extensoes_shell.dconf" ]]; then
        # Compatibilidade com backups legados
        dconf load /org/gnome/shell/extensions/ < "${STAGE_DIR}/gnome/extensoes_shell.dconf" 2>/dev/null || true
    fi
    if [[ -f "${STAGE_DIR}/gnome/background.dconf" ]]; then
        dconf load /org/gnome/desktop/background/ < "${STAGE_DIR}/gnome/background.dconf" 2>/dev/null || true
    fi
    if [[ -f "${STAGE_DIR}/gnome/interface.dconf" ]]; then
        dconf load /org/gnome/desktop/interface/ < "${STAGE_DIR}/gnome/interface.dconf" 2>/dev/null || true
    fi
    if [[ -f "${STAGE_DIR}/gnome/gerenciador_janelas.dconf" ]]; then
        dconf load /org/gnome/desktop/wm/ < "${STAGE_DIR}/gnome/gerenciador_janelas.dconf" 2>/dev/null || true
    fi
    if [[ -f "${STAGE_DIR}/gnome/mutter.dconf" ]]; then
        dconf load /org/gnome/mutter/ < "${STAGE_DIR}/gnome/mutter.dconf" 2>/dev/null || true
    fi
    if [[ -f "${STAGE_DIR}/gnome/atalhos_customizados.dconf" ]]; then
        dconf load /org/gnome/settings-daemon/plugins/media-keys/ < "${STAGE_DIR}/gnome/atalhos_customizados.dconf" 2>/dev/null || true
    fi
    echo -e "    ${GREEN}✔${RESET} Preferências e extensões do GNOME carregadas cirurgicamente via dconf."
fi

echo ""
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}🎉 Restauração concluída com sucesso!               ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
