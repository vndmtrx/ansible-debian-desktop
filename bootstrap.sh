#!/usr/bin/env bash
#
# Script de bootstrap para Ansible no Debian
# Instala Ansible e ansible-lint via pipx de forma isolada e executa o playbook

set -euo pipefail

# 1. Garante que ~/.local/bin está no PATH da sessão atual
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# 2. Garante persistência do PATH no ~/.bashrc sem duplicar
if ! grep -qs '\.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# 3. Atualiza repositórios e instala pré-requisitos (pipx)
if ! command -v pipx &>/dev/null; then
    echo "Instalando pipx..."
    sudo apt-get update
    sudo apt-get install -y pipx
fi

# 4. Instala Ansible via pipx com os binários completos
if ! command -v ansible &>/dev/null; then
    echo "Instalando Ansible via pipx..."
    pipx install --include-deps ansible
fi

# 5. Injeta dependências auxiliares no ambiente virtual do Ansible
if ! command -v ansible-lint &>/dev/null; then
    echo "Injetando ansible-lint via pipx..."
    pipx inject ansible ansible-lint
fi

# Garante a biblioteca pipx dentro do ambiente Python do Ansible para módulos do community.general
if ! pipx list --include-injected 2>/dev/null | grep -q "pipx "; then
    echo "Injetando módulo pipx no ambiente do Ansible..."
    pipx inject ansible pipx 2>/dev/null || true
fi

# 6. Relatório do Sistema: Verificação de Runtimes e Antigravity
BOLD='\033[1m'
RESET='\033[0m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
RED='\033[31m'
DIM='\033[2m'

DEFAULTS_FILE="sistema/defaults/main.yaml"
VARS_FILE="sistema/vars/main.yaml"

get_conf_var() {
    local var_name="$1"
    local val=""
    if [[ -f "$DEFAULTS_FILE" ]]; then
        val=$(grep -E "^\s*${var_name}:" "$DEFAULTS_FILE" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d "'\"" || true)
    fi
    if [[ -z "$val" && -f "$VARS_FILE" ]]; then
        val=$(grep -E "^\s*${var_name}:" "$VARS_FILE" 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d "'\"" || true)
    fi
    echo "$val"
}

is_newer_version() {
    local v1="$1"
    local v2="$2"

    v1="${v1#v}"
    v1="${v1#OTP-}"
    v2="${v2#v}"
    v2="${v2#OTP-}"

    if [[ -z "$v1" || -z "$v2" || "$v1" == "$v2" ]]; then
        return 1
    fi

    if [[ "$v2" == "Não instalado" ]]; then
        return 0
    fi

    local highest
    highest=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V 2>/dev/null | tail -n 1)
    if [[ "$highest" == "$v1" && "$v1" != "$v2" ]]; then
        return 0
    else
        return 1
    fi
}

check_antigravity_report() {
    local download_dir="$HOME/Downloads"
    local bin_dir="$HOME/.local/bin"

    echo -e "${BOLD}${BLUE}=== [1/2] Status do Google Antigravity ===${RESET}"

    # Standalone
    local tar_standalone="$download_dir/Antigravity.tar.gz"
    local bin_standalone="$bin_dir/antigravity"
    echo -e "  ${BOLD}Antigravity Standalone:${RESET}"
    if [[ -f "$tar_standalone" ]]; then
        echo -e "    - Tarball:    ${GREEN}Presente${RESET} ($tar_standalone)"
        echo -e "    - Ação:       ${YELLOW}Será instalado/atualizado e o compactado será removido após instalação.${RESET}"
    else
        echo -e "    - Tarball:    ${DIM}Ausente em $download_dir${RESET}"
        if [[ -f "$bin_standalone" || -L "$bin_standalone" ]]; then
            echo -e "    - Instalado:  ${GREEN}Sim${RESET} ($bin_standalone)"
            echo -e "    - Ação:       ${CYAN}Nenhum arquivo para atualização. Mantendo a instalação atual.${RESET}"
        else
            echo -e "    - Instalado:  ${RED}Não${RESET}"
            echo -e "    - Ação:       ${DIM}Nenhum arquivo encontrado. Instalação não realizada.${RESET}"
        fi
    fi

    # IDE
    local tar_ide="$download_dir/Antigravity IDE.tar.gz"
    local bin_ide="$bin_dir/antigravity-ide"
    echo -e "  ${BOLD}Antigravity IDE:${RESET}"
    if [[ -f "$tar_ide" ]]; then
        echo -e "    - Tarball:    ${GREEN}Presente${RESET} ($tar_ide)"
        echo -e "    - Ação:       ${YELLOW}Será instalado/atualizado e o compactado será removido após instalação.${RESET}"
    else
        echo -e "    - Tarball:    ${DIM}Ausente em $download_dir${RESET}"
        if [[ -f "$bin_ide" || -L "$bin_ide" ]]; then
            echo -e "    - Instalado:  ${GREEN}Sim${RESET} ($bin_ide)"
            echo -e "    - Ação:       ${CYAN}Nenhum arquivo para atualização. Mantendo a instalação atual.${RESET}"
        else
            echo -e "    - Instalado:  ${RED}Não${RESET}"
            echo -e "    - Ação:       ${DIM}Nenhum arquivo encontrado. Instalação não realizada.${RESET}"
        fi
    fi
}

check_runtime_component() {
    local name="$1"
    local installed="$2"
    local configured="$3"
    local latest="$4"

    echo -e "  ${BOLD}${name}:${RESET}"
    echo -e "    - Instalado:    ${CYAN}${installed}${RESET}"
    echo -e "    - Configurado:  ${CYAN}${configured}${RESET} ${DIM}(playbook)${RESET}"
    if [[ -n "$latest" ]]; then
        echo -e "    - Mais recente: ${CYAN}${latest}${RESET} ${DIM}(upstream)${RESET}"
    else
        echo -e "    - Mais recente: ${DIM}Não foi possível consultar upstream${RESET}"
    fi

    if [[ "$installed" == "Não instalado" ]]; then
        echo -e "    - Status:       ${YELLOW}Não instalado. O playbook instalará a versão configurada (${configured}).${RESET}"
    elif [[ "$installed" != "$configured" ]]; then
        if is_newer_version "$configured" "$installed"; then
            echo -e "    - Status:       ${YELLOW}⚠️  Versão configurada (${configured}) é mais nova que a instalada (${installed}).${RESET}"
        else
            echo -e "    - Status:       ${YELLOW}⚠️  Versão instalada (${installed}) difere da configurada (${configured}).${RESET}"
        fi
    else
        echo -e "    - Status:       ${GREEN}✅ Em dia com a versão configurada no playbook (${configured}).${RESET}"
    fi

    if [[ -n "$latest" ]]; then
        if is_newer_version "$latest" "$installed" && is_newer_version "$latest" "$configured"; then
            echo -e "    - Alerta:       ${YELLOW}🔔 Existe versão mais recente upstream: ${BOLD}${latest}${RESET}${YELLOW}! (Considere atualizar vars/main.yaml)${RESET}"
        fi
    fi
}

check_runtimes_report() {
    echo -e "\n${BOLD}${BLUE}=== [2/2] Verificação de Runtimes e Versões ===${RESET}"

    # Java
    local installed_java=""
    if [[ -d "$HOME/.sdkman/candidates/java" ]]; then
        if [[ -L "$HOME/.sdkman/candidates/java/current" ]]; then
            installed_java=$(basename "$(readlink -f "$HOME/.sdkman/candidates/java/current")")
        else
            installed_java=$(ls -1 "$HOME/.sdkman/candidates/java" 2>/dev/null | grep -v 'current' | head -n 1 || true)
        fi
    fi
    if [[ -z "$installed_java" ]] && command -v java &>/dev/null; then
        installed_java=$(java -version 2>&1 | head -n 1 | sed -E 's/.*version "([^"]+)".*/\1/' || true)
    fi
    [[ -z "$installed_java" ]] && installed_java="Não instalado"

    local conf_java
    conf_java=$(get_conf_var "versao_java")
    [[ -z "$conf_java" ]] && conf_java=$(get_conf_var "java_sdkman")
    local latest_java
    latest_java=$(curl -sL --max-time 2 "https://api.sdkman.io/2/candidates/default/java" 2>/dev/null || true)

    check_runtime_component "Java" "$installed_java" "$conf_java" "$latest_java"

    # Maven
    local installed_maven=""
    if [[ -d "$HOME/.sdkman/candidates/maven" ]]; then
        if [[ -L "$HOME/.sdkman/candidates/maven/current" ]]; then
            installed_maven=$(basename "$(readlink -f "$HOME/.sdkman/candidates/maven/current")")
        else
            installed_maven=$(ls -1 "$HOME/.sdkman/candidates/maven" 2>/dev/null | grep -v 'current' | head -n 1 || true)
        fi
    fi
    if [[ -z "$installed_maven" ]] && command -v mvn &>/dev/null; then
        installed_maven=$(mvn -version 2>&1 | head -n 1 | awk '{print $3}' || true)
    fi
    [[ -z "$installed_maven" ]] && installed_maven="Não instalado"

    local conf_maven
    conf_maven=$(get_conf_var "versao_maven")
    [[ -z "$conf_maven" ]] && conf_maven=$(get_conf_var "maven_sdkman")
    local latest_maven
    latest_maven=$(curl -sL --max-time 2 "https://api.sdkman.io/2/candidates/default/maven" 2>/dev/null || true)

    check_runtime_component "Maven" "$installed_maven" "$conf_maven" "$latest_maven"

    # Erlang
    local installed_erlang=""
    if [[ -f "$HOME/.tool-versions" ]]; then
        installed_erlang=$(grep -E '^\s*erlang\s+' "$HOME/.tool-versions" 2>/dev/null | awk '{print $2}' || true)
    fi
    if [[ -z "$installed_erlang" && -d "$HOME/.asdf/installs/erlang" ]]; then
        installed_erlang=$(ls -1 "$HOME/.asdf/installs/erlang" 2>/dev/null | sort -V | tail -n 1 || true)
    fi
    [[ -z "$installed_erlang" ]] && installed_erlang="Não instalado"

    local conf_erlang
    conf_erlang=$(get_conf_var "versao_erlang")
    local latest_erlang=""
    if command -v asdf &>/dev/null || [[ -x "$HOME/.local/bin/asdf" ]]; then
        export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
        latest_erlang=$(timeout 2 asdf latest erlang 2>/dev/null || true)
    fi
    if [[ -z "$latest_erlang" ]]; then
        latest_erlang=$(curl -sL --max-time 2 "https://api.github.com/repos/erlang/otp/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"OTP-\([^"]*\)".*/\1/p' || true)
    fi

    check_runtime_component "Erlang (OTP)" "$installed_erlang" "$conf_erlang" "$latest_erlang"

    # Elixir
    local installed_elixir=""
    if [[ -f "$HOME/.tool-versions" ]]; then
        installed_elixir=$(grep -E '^\s*elixir\s+' "$HOME/.tool-versions" 2>/dev/null | awk '{print $2}' || true)
    fi
    if [[ -z "$installed_elixir" && -d "$HOME/.asdf/installs/elixir" ]]; then
        installed_elixir=$(ls -1 "$HOME/.asdf/installs/elixir" 2>/dev/null | sort -V | tail -n 1 || true)
    fi
    [[ -z "$installed_elixir" ]] && installed_elixir="Não instalado"

    local conf_elixir
    conf_elixir=$(get_conf_var "versao_elixir")
    local latest_elixir=""
    if command -v asdf &>/dev/null || [[ -x "$HOME/.local/bin/asdf" ]]; then
        export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
        latest_elixir=$(timeout 2 asdf latest elixir 2>/dev/null || true)
    fi
    if [[ -z "$latest_elixir" ]]; then
        latest_elixir=$(curl -sL --max-time 2 "https://api.github.com/repos/elixir-lang/elixir/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' || true)
    fi

    check_runtime_component "Elixir" "$installed_elixir" "$conf_elixir" "$latest_elixir"
}

# Exibição do Relatório do Sistema
echo -e "\n${BOLD}======================================================================${RESET}"
echo -e "                   ${BOLD}RELATÓRIO DO SISTEMA${RESET}"
echo -e "${BOLD}======================================================================${RESET}\n"

check_antigravity_report
check_runtimes_report

echo -e "\n${BOLD}======================================================================${RESET}\n"

# 7. Validação e execução do playbook
echo "Validando playbook com ansible-lint..."
ansible-lint

echo "Executando playbook..."
ansible-playbook playbook.yaml --ask-become-pass "$@"