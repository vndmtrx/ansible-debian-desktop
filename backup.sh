#!/usr/bin/env bash
#
# backup.sh - Utilitário de backup e restauração de segurança (Git, SSH, GnuPG)
#
# Uso:
#   ./backup.sh backup              # Cria um novo backup em ~/du/backups/YYYYMMDD_HHMM.tar.bz2
#   ./backup.sh restore [ARQUIVO]   # Restaura do backup mais recente (ou do arquivo informado)
#
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
trap cleanup_temp EXIT

print_header() {
    echo -e "${BOLD}${BLUE}====================================================${RESET}"
    echo -e "${BOLD}${BLUE}   🔒 Utilitário de Segurança (Git, SSH, GnuPG)    ${RESET}"
    echo -e "${BOLD}${BLUE}====================================================${RESET}"
}

usage() {
    print_header
    local exit_code="${1:-1}"
    echo -e "${BOLD}Uso:${RESET} $0 [backup | restore | add-keys] [opções]"
    echo ""
    echo -e "  ${CYAN}backup${RESET}              Exporta Git, SSH e chaves GPG, gerando:"
    echo -e "                      - Arquivo comprimido em .tar.bz2"
    echo -e "                      - Checksum de integridade em .sha256"
    echo -e "                      - Assinatura digital desanexada em .asc (GPG)"
    echo -e "                      Armazenado diretamente em: ${DIM}${BACKUP_BASE_DIR}/${RESET}"
    echo ""
    echo -e "  ${CYAN}restore [ARQUIVO]${RESET}   Restaura configurações e chaves."
    echo -e "                      Por padrão, seleciona o .tar.bz2 mais recente em ${DIM}${BACKUP_BASE_DIR}${RESET}."
    echo -e "                      Valida hash, assinatura e exibe relatório de alterações antes de confirmar."
    echo ""
    echo -e "  ${CYAN}add-keys${RESET}            Carrega automaticamente todas as chaves privadas de ~/.ssh no ssh-agent."
    echo ""
    exit "${exit_code}"
}

run_backup() {
    print_header
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M)
    local archive_name="${timestamp}.tar.bz2"
    local archive_path="${BACKUP_BASE_DIR}/${archive_name}"
    local sha_path="${archive_path}.sha256"
    local sig_path="${archive_path}.asc"

    echo -e "${BOLD}Iniciando rotina de backup...${RESET}"
    echo -e "  - Destino: ${CYAN}${archive_path}${RESET}"
    echo ""

    # Garante diretório base com permissão estrita
    mkdir -p "${BACKUP_BASE_DIR}"
    chmod 700 "${BACKUP_BASE_DIR}"

    # Cria diretório temporário restrito
    STAGE_DIR=$(mktemp -d -t sec_backup_stage_XXXXXX)
    chmod 700 "${STAGE_DIR}"

    # 1. Coleta de configurações do Git
    echo -e "  ${BOLD}${BLUE}[Etapa 1/6] Coletando configurações do Git...${RESET}"
    mkdir -p "${STAGE_DIR}/git"
    local git_found=0
    if [[ -f "${HOME}/.gitconfig" ]]; then
        cp -p "${HOME}/.gitconfig" "${STAGE_DIR}/git/"
        local git_user git_email
        git_user=$(git config --file "${HOME}/.gitconfig" user.name 2>/dev/null || echo "não definido")
        git_email=$(git config --file "${HOME}/.gitconfig" user.email 2>/dev/null || echo "não definido")
        echo -e "    ${GREEN}✔${RESET} ~/.gitconfig (${CYAN}${git_user} <${git_email}>${RESET})"
        git_found=1
    fi

    if [[ -d "${HOME}/.config/git" ]]; then
        cp -a "${HOME}/.config/git" "${STAGE_DIR}/git/"
        echo -e "    ${GREEN}✔${RESET} ~/.config/git (diretório adicional)"
        while IFS= read -r -d '' gfile; do
            echo -e "      📄 ${gfile#"${HOME}/"}"
        done < <(find "${HOME}/.config/git" -type f -print0 2>/dev/null)
        git_found=1
    fi

    if [[ "${git_found}" -eq 0 ]]; then
        echo -e "    ${DIM}Nenhuma configuração Git encontrada.${RESET}"
    fi

    echo ""

    # 2. Coleta de credenciais SSH
    echo -e "  ${BOLD}${BLUE}[Etapa 2/6] Coletando credenciais e configurações SSH...${RESET}"
    mkdir -p "${STAGE_DIR}/ssh"
    if [[ -d "${HOME}/.ssh" ]]; then
        cp -a "${HOME}/.ssh/." "${STAGE_DIR}/ssh/"
        local ssh_files=0
        while IFS= read -r -d '' sfile; do
            local rel_path="${sfile#"${HOME}/.ssh/"}"
            local fsize
            fsize=$(du -h "${sfile}" 2>/dev/null | awk '{print $1}')

            if [[ "${rel_path}" == id_* && "${rel_path}" != *.pub ]]; then
                echo -e "    ${GREEN}✔${RESET} 🔑 Chave privada: ${YELLOW}~/.ssh/${rel_path}${RESET} (${fsize})"
            elif [[ "${rel_path}" == *.pub ]]; then
                echo -e "    ${GREEN}✔${RESET} 📄 Chave pública: ${CYAN}~/.ssh/${rel_path}${RESET} (${fsize})"
            elif [[ "${rel_path}" == "config" ]]; then
                echo -e "    ${GREEN}✔${RESET} ⚙️  Configuração:   ${BOLD}~/.ssh/${rel_path}${RESET} (${fsize})"
            elif [[ "${rel_path}" == "known_hosts"* ]]; then
                echo -e "    ${GREEN}✔${RESET} 🌐 Known Hosts:   ${DIM}~/.ssh/${rel_path}${RESET} (${fsize})"
            elif [[ "${rel_path}" == "authorized_keys"* ]]; then
                echo -e "    ${GREEN}✔${RESET} 🔐 Authorized:    ~/.ssh/${rel_path} (${fsize})"
            else
                echo -e "    ${GREEN}✔${RESET} 📁 Arquivo SSH:   ~/.ssh/${rel_path} (${fsize})"
            fi
            ssh_files=$((ssh_files + 1))
        done < <(find "${HOME}/.ssh" -type f -print0 2>/dev/null | sort -z)

        if [[ "${ssh_files}" -eq 0 ]]; then
            echo -e "    ${DIM}Nenhum arquivo encontrado dentro de ~/.ssh.${RESET}"
        fi
    else
        echo -e "    ${DIM}Nenhum diretório ~/.ssh encontrado.${RESET}"
    fi

    echo ""

    # 3. Exportação de chaves e confiança GnuPG
    echo -e "  ${BOLD}${BLUE}[Etapa 3/6] Exportando chaves e base de confiança GnuPG...${RESET}"
    mkdir -p "${STAGE_DIR}/gnupg"
    if command -v gpg &>/dev/null; then
        # Lista as chaves encontradas
        echo -e "    🔍 Identificando chaves registradas no GnuPG:"
        local gpg_keys_found=0
        while IFS= read -r line; do
            if [[ -n "${line}" ]]; then
                echo -e "      ${CYAN}•${RESET} ${line}"
                gpg_keys_found=1
            fi
        done < <(gpg --list-keys --with-colons 2>/dev/null | awk -F: '$1=="uid" {print $10}' | sort -u)

        if [[ "${gpg_keys_found}" -eq 0 ]]; then
            echo -e "      ${DIM}Nenhum UID encontrado no chaveiro.${RESET}"
        fi

        # Exportação de Chaves públicas
        if gpg --list-keys 2>/dev/null | grep -q 'pub'; then
            gpg --armor --export > "${STAGE_DIR}/gnupg/chaves_publicas.asc" 2>/dev/null || true
            local pub_size
            pub_size=$(du -h "${STAGE_DIR}/gnupg/chaves_publicas.asc" 2>/dev/null | awk '{print $1}')
            echo -e "    ${GREEN}✔${RESET} Chaves públicas exportadas (${pub_size})"
        else
            echo -e "    ${DIM}Nenhuma chave pública GPG para exportar.${RESET}"
        fi

        # Exportação de Chaves secretas
        if gpg --list-secret-keys 2>/dev/null | grep -q 'sec'; then
            echo -e "    ${YELLOW}🔑 O GPG solicitará autorização/senha mestra para exportar as chaves privadas...${RESET}"
            if gpg --armor --export-secret-keys > "${STAGE_DIR}/gnupg/chaves_privadas.asc" 2>/dev/null; then
                local priv_size
                priv_size=$(du -h "${STAGE_DIR}/gnupg/chaves_privadas.asc" 2>/dev/null | awk '{print $1}')
                echo -e "    ${GREEN}✔${RESET} Chaves privadas exportadas com sucesso (${priv_size})"
            else
                echo -e "    ${RED}✖ Falha ou cancelamento na exportação das chaves privadas.${RESET}"
            fi
        else
            echo -e "    ${DIM}Nenhuma chave privada GPG encontrada.${RESET}"
        fi

        # Base de confiança (ownertrust)
        gpg --export-ownertrust > "${STAGE_DIR}/gnupg/confianca_trust.txt" 2>/dev/null || true
        echo -e "    ${GREEN}✔${RESET} Base de confiança (ownertrust) exportada."
    else
        echo -e "    ${RED}✖ Utilitário gpg não encontrado no sistema.${RESET}"
    fi

    echo ""

    # 4. Compactação Bzip2
    echo -e "  ${BOLD}${BLUE}[Etapa 4/6] Compactando pacote em Bzip2 (.tar.bz2)...${RESET}"
    tar -cjf "${archive_path}" -C "${STAGE_DIR}" .
    local archive_size
    archive_size=$(du -h "${archive_path}" 2>/dev/null | awk '{print $1}')
    echo -e "    ${GREEN}✔${RESET} Arquivo gerado: ${BOLD}${archive_name}${RESET} (${archive_size})"

    echo ""

    # 5. Geração de Hash SHA-256
    echo -e "  ${BOLD}${BLUE}[Etapa 5/6] Calculando hash de integridade SHA-256...${RESET}"
    local sha_val
    (
        cd "${BACKUP_BASE_DIR}"
        sha256sum "${archive_name}" > "${archive_name}.sha256"
    )
    sha_val=$(awk '{print $1}' "${sha_path}")
    echo -e "    ${GREEN}✔${RESET} Checksum gerado: ${archive_name}.sha256"
    echo -e "      ${DIM}Hash: ${sha_val}${RESET}"

    echo ""

    # 6. Assinatura Digital GPG
    echo -e "  ${BOLD}${BLUE}[Etapa 6/6] Assinando digitalmente com GPG...${RESET}"
    if command -v gpg &>/dev/null; then
        echo -e "    ${YELLOW}🔑 O GPG solicitará autorização para assinar digitalmente o pacote...${RESET}"
        if gpg --armor --detach-sign "${archive_path}" 2>/dev/null; then
            echo -e "    ${GREEN}✔${RESET} Assinatura digital desanexada criada: ${BOLD}${archive_name}.asc${RESET}"
        else
            echo -e "    ${YELLOW}⚠️  Assinatura digital não gerada (cancelada ou chave indisponível).${RESET}"
        fi
    else
        echo -e "    ${DIM}GPG não disponível para assinar.${RESET}"
    fi

    # Permissões restritas
    chmod 600 "${archive_path}" "${sha_path}" "${sig_path}" 2>/dev/null || true

    echo ""
    echo -e "${BOLD}${GREEN}====================================================${RESET}"
    echo -e "${BOLD}${GREEN}🎉 Backup de segurança finalizado com sucesso!      ${RESET}"
    echo -e "${BOLD}${GREEN}====================================================${RESET}"
    echo -e "  📁 Diretório de saída: ${BOLD}${BACKUP_BASE_DIR}/${RESET}"
    echo -e "  📦 Arquivos gerados:"
    ls -lh "${archive_path}" "${sha_path}" "${sig_path}" 2>/dev/null | awk '{printf "     - %-10s %s\n", $5, $9}'
}

run_restore() {
    print_header
    local target_input="${1:-}"
    local archive_path=""

    # 1. Resolução do arquivo a ser restaurado
    if [[ -z "${target_input}" ]]; then
        if [[ ! -d "${BACKUP_BASE_DIR}" ]]; then
            echo -e "${RED}Erro: Diretório de backups ${BACKUP_BASE_DIR} não encontrado.${RESET}"
            exit 1
        fi

        # Busca o .tar.bz2 mais recente na raiz de BACKUP_BASE_DIR
        archive_path=$(find "${BACKUP_BASE_DIR}" -maxdepth 1 -type f -name "*.tar.bz2" 2>/dev/null | sort -V | tail -n 1 || true)
        
        # Caso não haja na raiz, verifica em subpastas antigas
        if [[ -z "${archive_path}" ]]; then
            archive_path=$(find "${BACKUP_BASE_DIR}" -type f -name "*.tar.bz2" 2>/dev/null | sort -V | tail -n 1 || true)
        fi

        if [[ -z "${archive_path}" ]]; then
            echo -e "${RED}Erro: Nenhum arquivo .tar.bz2 encontrado em ${BACKUP_BASE_DIR}.${RESET}"
            exit 1
        fi
    elif [[ -d "${target_input}" ]]; then
        # Se foi passado um diretório, busca o .tar.bz2 dentro dele
        archive_path=$(find "${target_input}" -maxdepth 1 -type f -name "*.tar.bz2" | sort -V | tail -n 1 || true)
        if [[ -z "${archive_path}" ]]; then
            echo -e "${RED}Erro: Nenhum arquivo .tar.bz2 encontrado no diretório '${target_input}'.${RESET}"
            exit 1
        fi
    elif [[ -f "${target_input}" ]]; then
        archive_path="${target_input}"
    else
        echo -e "${RED}Erro: Caminho '${target_input}' não encontrado.${RESET}"
        exit 1
    fi

    local archive_dir
    archive_dir=$(dirname "${archive_path}")
    local archive_name
    archive_name=$(basename "${archive_path}")

    echo -e "${BOLD}Arquivo selecionado para restauração:${RESET} ${CYAN}${archive_path}${RESET}"
    echo ""

    # 2. Validação do Checksum SHA-256
    echo -e "  ${BOLD}[1/4] Verificando integridade (SHA-256)...${RESET}"
    local sha_path="${archive_path}.sha256"
    if [[ -f "${sha_path}" ]]; then
        if (cd "${archive_dir}" && sha256sum -c --status "${archive_name}.sha256"); then
            echo -e "    ${GREEN}✔${RESET} Checksum SHA-256 íntegro e validado."
        else
            echo -e "    ${RED}✖ ERRO CRÍTICO: Falha na verificação de checksum SHA-256!${RESET}"
            echo -e "    O arquivo pode estar corrompido ou ter sido alterado."
            exit 1
        fi
    else
        echo -e "    ${YELLOW}⚠️  Arquivo .sha256 não encontrado (${sha_path}). Verificação de integridade ignorada.${RESET}"
    fi

    # 3. Validação da Assinatura GPG
    echo -e "  ${BOLD}[2/4] Verificando assinatura digital GPG...${RESET}"
    local sig_path="${archive_path}.asc"
    if [[ -f "${sig_path}" ]] && command -v gpg &>/dev/null; then
        if gpg --verify "${sig_path}" "${archive_path}" &>/dev/null; then
            echo -e "    ${GREEN}✔${RESET} Assinatura digital GPG válida e confirmada."
        else
            echo -e "    ${YELLOW}⚠️  Aviso: Não foi possível verificar a assinatura digital (chave ausente ou inválida).${RESET}"
        fi
    else
        echo -e "    ${DIM}Assinatura .asc não encontrada ou GPG não disponível.${RESET}"
    fi

    # Extrai para diretório temporário restrito
    STAGE_DIR=$(mktemp -d -t sec_restore_stage_XXXXXX)
    chmod 700 "${STAGE_DIR}"

    tar -xjf "${archive_path}" -C "${STAGE_DIR}"

    # 4. Análise de impacto e substituições
    echo ""
    echo -e "  ${BOLD}[3/4] Relatório de Impacto e Substituições:${RESET}"
    local replacements=0
    local additions=0

    # Git
    if [[ -f "${STAGE_DIR}/git/.gitconfig" ]]; then
        if [[ -f "${HOME}/.gitconfig" ]]; then
            echo -e "    ${YELLOW}[SUBSTITUIÇÃO]${RESET} ~/.gitconfig existente será sobrescrito."
            replacements=$((replacements + 1))
        else
            echo -e "    ${GREEN}[NOVO]${RESET} ~/.gitconfig será criado."
            additions=$((additions + 1))
        fi
    fi

    if [[ -d "${STAGE_DIR}/git/git" ]]; then
        if [[ -d "${HOME}/.config/git" ]]; then
            echo -e "    ${YELLOW}[SUBSTITUIÇÃO]${RESET} ~/.config/git existente será mesclado/atualizado."
            replacements=$((replacements + 1))
        else
            echo -e "    ${GREEN}[NOVO]${RESET} ~/.config/git será criado."
            additions=$((additions + 1))
        fi
    fi

    # SSH
    if [[ -d "${STAGE_DIR}/ssh" ]]; then
        while IFS= read -r -d '' file; do
            local rel_file="${file#"${STAGE_DIR}/ssh/"}"
            local dest_file="${HOME}/.ssh/${rel_file}"
            if [[ -e "${dest_file}" ]]; then
                echo -e "    ${YELLOW}[SUBSTITUIÇÃO]${RESET} ~/.ssh/${rel_file} existente será substituído."
                replacements=$((replacements + 1))
            else
                echo -e "    ${GREEN}[NOVO]${RESET} ~/.ssh/${rel_file} será adicionado."
                additions=$((additions + 1))
            fi
        done < <(find "${STAGE_DIR}/ssh" -type f -print0 2>/dev/null)
    fi

    # GnuPG
    if [[ -d "${STAGE_DIR}/gnupg" ]]; then
        if [[ -f "${STAGE_DIR}/gnupg/chaves_publicas.asc" ]]; then
            echo -e "    ${BLUE}[CHAVE GPG]${RESET} Chaves públicas serão importadas para o chaveiro GnuPG."
        fi
        if [[ -f "${STAGE_DIR}/gnupg/chaves_privadas.asc" ]]; then
            echo -e "    ${BLUE}[CHAVE GPG]${RESET} Chaves privadas serão importadas para o chaveiro GnuPG."
        fi
        if [[ -f "${STAGE_DIR}/gnupg/confianca_trust.txt" ]]; then
            echo -e "    ${BLUE}[CHAVE GPG]${RESET} Base de confiança (ownertrust) será atualizada."
        fi
    fi

    echo ""
    echo -e "  Resumo: ${BOLD}${YELLOW}${replacements} arquivo(s) a substituir${RESET}, ${BOLD}${GREEN}${additions} novo(s) arquivo(s)${RESET}."
    echo ""

    # Confirmação do usuário
    read -r -p "Deseja prosseguir com a restauração? [s/N]: " confirm
    if [[ ! "${confirm}" =~ ^[sS]$ && ! "${confirm}" =~ ^[yY]$ ]]; then
        echo -e "${YELLOW}Operação cancelada pelo usuário. Nenhuma alteração foi realizada.${RESET}"
        exit 0
    fi

    # 5. Execução da restauração
    echo ""
    echo -e "  ${BOLD}[4/4] Executando restauração...${RESET}"

    # Restaura Git
    if [[ -f "${STAGE_DIR}/git/.gitconfig" ]]; then
        cp -p "${STAGE_DIR}/git/.gitconfig" "${HOME}/.gitconfig"
        echo -e "    ${GREEN}✔${RESET} ~/.gitconfig restaurado."
    fi
    if [[ -d "${STAGE_DIR}/git/git" ]]; then
        mkdir -p "${HOME}/.config/git"
        cp -a "${STAGE_DIR}/git/git/." "${HOME}/.config/git/"
        echo -e "    ${GREEN}✔${RESET} ~/.config/git restaurado."
    fi

    # Restaura SSH
    if [[ -d "${STAGE_DIR}/ssh" ]]; then
        mkdir -p "${HOME}/.ssh"
        chmod 700 "${HOME}/.ssh"
        cp -a "${STAGE_DIR}/ssh/." "${HOME}/.ssh/"

        # Ajuste obrigatório de permissões restritas
        chmod 600 "${HOME}"/.ssh/id_* 2>/dev/null || true
        chmod 600 "${HOME}/.ssh/config" 2>/dev/null || true
        chmod 644 "${HOME}"/.ssh/*.pub 2>/dev/null || true
        chmod 644 "${HOME}/.ssh/known_hosts" 2>/dev/null || true
        chmod 644 "${HOME}/.ssh/authorized_keys" 2>/dev/null || true
        echo -e "    ${GREEN}✔${RESET} Credenciais SSH restauradas e permissões (700/600/644) aplicadas."
    fi

    # Restaura GnuPG
    if [[ -d "${STAGE_DIR}/gnupg" ]] && command -v gpg &>/dev/null; then
        mkdir -p "${HOME}/.gnupg"
        chmod 700 "${HOME}/.gnupg"

        if [[ -f "${STAGE_DIR}/gnupg/chaves_publicas.asc" ]]; then
            gpg --import "${STAGE_DIR}/gnupg/chaves_publicas.asc" &>/dev/null || true
            echo -e "    ${GREEN}✔${RESET} Chaves públicas importadas com sucesso."
        fi
        if [[ -f "${STAGE_DIR}/gnupg/chaves_privadas.asc" ]]; then
            echo -e "    ${YELLOW}🔑 O GPG solicitará a autorização para importar as chaves privadas...${RESET}"
            gpg --import "${STAGE_DIR}/gnupg/chaves_privadas.asc" &>/dev/null || true
            echo -e "    ${GREEN}✔${RESET} Chaves privadas importadas com sucesso."
        fi
        if [[ -f "${STAGE_DIR}/gnupg/confianca_trust.txt" ]]; then
            gpg --import-ownertrust "${STAGE_DIR}/gnupg/confianca_trust.txt" &>/dev/null || true
            echo -e "    ${GREEN}✔${RESET} Base de confiança atualizada com sucesso."
        fi
    fi

    # 6. Carregamento de chaves no ssh-agent
    if [[ -d "${HOME}/.ssh" ]]; then
        echo ""
        read -r -p "Deseja carregar as chaves privadas no ssh-agent agora (ssh-add)? [S/n]: " add_keys_confirm
        if [[ -z "${add_keys_confirm}" || "${add_keys_confirm}" =~ ^[sS]$ || "${add_keys_confirm}" =~ ^[yY]$ ]]; then
            echo ""
            carregar_chaves_ssh
        fi
    fi

    echo ""
    echo -e "${BOLD}${GREEN}🎉 Restauração concluída com sucesso!${RESET}"
}

carregar_chaves_ssh() {
    echo -e "  ${BOLD}${BLUE}🔑 Importando chaves privadas no ssh-agent...${RESET}"

    # Garante que o ssh-agent está acessível
    local agent_started=0
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        echo -e "    ${YELLOW}ssh-agent não detectado na sessão atual. Inicializando agente...${RESET}"
        eval "$(ssh-agent -s)" >/dev/null
        agent_started=1
    elif ! ssh-add -l &>/dev/null && [[ $? -eq 2 ]]; then
        echo -e "    ${YELLOW}Não foi possível conectar ao ssh-agent. Inicializando novo agente...${RESET}"
        eval "$(ssh-agent -s)" >/dev/null
        agent_started=1
    fi

    # Localiza chaves privadas SSH em ~/.ssh (ignora .pub e chaves PGP .asc)
    local private_keys=()
    while IFS= read -r -d '' keyfile; do
        if ! [[ "${keyfile}" =~ \.pub$ ]] && grep -q "PRIVATE KEY" "${keyfile}" 2>/dev/null && ! grep -q "PGP PRIVATE KEY" "${keyfile}" 2>/dev/null; then
            private_keys+=("${keyfile}")
        fi
    done < <(find "${HOME}/.ssh" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)

    if [[ ${#private_keys[@]} -eq 0 ]]; then
        echo -e "    ${DIM}Nenhuma chave privada SSH encontrada em ~/.ssh.${RESET}"
        return 0
    fi

    echo -e "    Encontrada(s) ${BOLD}${#private_keys[@]}${RESET} chave(s) privada(s):"
    for k in "${private_keys[@]}"; do
        echo -e "      ${CYAN}•${RESET} ~/.ssh/$(basename "${k}")"
    done
    echo ""

    for key in "${private_keys[@]}"; do
        local key_name
        key_name=$(basename "${key}")
        echo -e "    🔑 Adicionando ${BOLD}~/.ssh/${key_name}${RESET}:"
        if ! ssh-add "${key}"; then
            echo -e "      ${YELLOW}⚠️  Não foi possível adicionar ~/.ssh/${key_name} (ou operação cancelada).${RESET}"
        fi
    done

    echo ""
    echo -e "    ${BOLD}Chaves atualmente ativas no agente:${RESET}"
    ssh-add -l 2>/dev/null || echo -e "      ${DIM}Nenhuma chave carregada.${RESET}"

    if [[ "${agent_started}" -eq 1 ]]; then
        echo ""
        echo -e "    ${YELLOW}💡 Dica:${RESET} Para manter o ssh-agent persistido no seu terminal atual, execute:"
        echo -e "       ${BOLD}eval \"\$(ssh-agent -s)\"${RESET}"
    fi
}

# Roteamento dos comandos
case "${1:-}" in
    backup)
        run_backup
        ;;
    restore)
        shift
        run_restore "${1:-}"
        ;;
    add-keys|load-keys|ssh-add)
        print_header
        carregar_chaves_ssh
        ;;
    -h|--help|help)
        usage 0
        ;;
    *)
        usage 1
        ;;
esac
