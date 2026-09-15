#!/usr/bin/env bash
# ==============================================================================
# Script: post-install.sh
# Descrição: Otimizador pós-instalação idempotente para Debian 13 (Trixie)
#            Executa no primeiro boot após instalação padrão do Calamares.
#            Aplica configurações de NVMe, GRUB, LUKS, ext4/btrfs, zram e bootstrap.
# ==============================================================================
set -euo pipefail

# Cores e formatação
BOLD='\033[1m'
RESET='\033[0m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
RED='\033[31m'
DIM='\033[2m'

log_info()    { echo -e "${BLUE}==>${RESET} ${BOLD}$1${RESET}"; }
log_step()    { echo -e "  ${CYAN}[*]${RESET} $1"; }
log_applied() { echo -e "  ${GREEN}[+] APLICADO:${RESET} $1"; }
log_ok()      { echo -e "  ${DIM}[=] JÁ CONFIGURADO:${RESET} $1"; }
log_warn()    { echo -e "  ${YELLOW}[!] AVISO:${RESET} $1"; }
log_err()     { echo -e "  ${RED}[x] ERRO:${RESET} $1" >&2; }

# Garantir execução como root
if [ "$(id -u)" -ne 0 ]; then
  log_err "Este script deve ser executado como root (use: sudo ./post-install.sh)"
  exit 1
fi

echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${BLUE}   ⚡ Otimizador Pós-Instalação Debian 13 (Day-0)${RESET}"
echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo ""

GRUB_CONFIG="/etc/default/grub"
GRUB_CHANGED=false
INITRAMFS_CHANGED=false
ACTIONS_COUNT=0

record_action() {
  ACTIONS_COUNT=$((ACTIONS_COUNT + 1))
}

# -------------------------------------------------------------------------
# 1. Habilitar suporte a cryptodisk e pré-carregar módulos no GRUB
# -------------------------------------------------------------------------
log_info "1/9 Verificando configurações do GRUB (/etc/default/grub)..."

if [ -f "$GRUB_CONFIG" ]; then
  # 1.1 GRUB_ENABLE_CRYPTODISK
  if grep -q "^GRUB_ENABLE_CRYPTODISK=y" "$GRUB_CONFIG"; then
    log_ok "GRUB_ENABLE_CRYPTODISK já está ativo (y)."
  else
    log_step "Ativando GRUB_ENABLE_CRYPTODISK=y..."
    if grep -q "^GRUB_ENABLE_CRYPTODISK=" "$GRUB_CONFIG"; then
      sed -i 's/^GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' "$GRUB_CONFIG"
    else
      echo "GRUB_ENABLE_CRYPTODISK=y" >> "$GRUB_CONFIG"
    fi
    log_applied "GRUB_ENABLE_CRYPTODISK=y configurado."
    GRUB_CHANGED=true
    record_action
  fi

  # 1.2 GRUB_PRELOAD_MODULES
  PRELOAD_TARGET='GRUB_PRELOAD_MODULES="luks crypto gcry_rijndael gcry_sha256 btrfs"'
  if grep -q "^GRUB_PRELOAD_MODULES=" "$GRUB_CONFIG"; then
    CURRENT_PRELOAD=$(grep "^GRUB_PRELOAD_MODULES=" "$GRUB_CONFIG")
    if [ "$CURRENT_PRELOAD" = "$PRELOAD_TARGET" ]; then
      log_ok "Módulos de criptografia e filesystem já pré-carregados no GRUB."
    else
      log_step "Atualizando módulos em GRUB_PRELOAD_MODULES..."
      sed -i "s|^GRUB_PRELOAD_MODULES=.*|$PRELOAD_TARGET|" "$GRUB_CONFIG"
      log_applied "GRUB_PRELOAD_MODULES atualizado."
      GRUB_CHANGED=true
      record_action
    fi
  else
    log_step "Inserindo GRUB_PRELOAD_MODULES..."
    echo "$PRELOAD_TARGET" >> "$GRUB_CONFIG"
    log_applied "GRUB_PRELOAD_MODULES inserido."
    GRUB_CHANGED=true
    record_action
  fi

  # 1.3 Limpar zswap residual (se existir)
  if grep -q "zswap\.enabled" "$GRUB_CONFIG"; then
    log_step "Removendo parâmetros residuais de zswap da linha do kernel..."
    sed -i -E 's/zswap\.[^ "]+//g; s/  */ /g' "$GRUB_CONFIG"
    log_applied "Parâmetros de zswap removidos do GRUB."
    GRUB_CHANGED=true
    record_action
  else
    log_ok "Nenhum parâmetro residual de zswap no GRUB."
  fi

  # 1.4 Remover splash
  if grep -q "splash" "$GRUB_CONFIG"; then
    log_step "Removendo splash da linha do kernel para boot limpo e rápido..."
    sed -i 's/\bsplash\b//g; s/  */ /g' "$GRUB_CONFIG"
    log_applied "Splash removido do GRUB."
    GRUB_CHANGED=true
    record_action
  else
    log_ok "Splash já ausente no GRUB."
  fi

  # 1.5 GRUB_TIMEOUT=1
  if grep -q '^GRUB_TIMEOUT=1' "$GRUB_CONFIG"; then
    log_ok "Timeout do GRUB já configurado para 1s."
  else
    log_step "Ajustando timeout do GRUB para 1s..."
    if grep -q "^GRUB_TIMEOUT=" "$GRUB_CONFIG"; then
      sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$GRUB_CONFIG"
    else
      echo "GRUB_TIMEOUT=1" >> "$GRUB_CONFIG"
    fi
    log_applied "GRUB_TIMEOUT=1 configurado."
    GRUB_CHANGED=true
    record_action
  fi
else
  log_warn "Arquivo $GRUB_CONFIG não encontrado. Etapa do GRUB ignorada."
fi

# -------------------------------------------------------------------------
# 2. Desativar swap em disco e limpar referências (/etc/fstab, crypttab, resume)
# -------------------------------------------------------------------------
log_info "2/9 Verificando swap em disco e configurações de hibernação..."

# 2.1 Desativar swap ativo em disco
SWAP_DEVS=$(swapon --show=NAME --noheadings 2>/dev/null | grep -v 'zram' || true)
if [ -n "$SWAP_DEVS" ]; then
  for dev in $SWAP_DEVS; do
    log_step "Desativando swap ativo em disco: $dev..."
    swapoff "$dev"
    log_applied "Swap em $dev desativado."
    record_action
  done
else
  log_ok "Nenhum swap ativo em disco físico."
fi

# 2.2 Fechar containers de swap mapeados pelo device mapper
# Busca pelo crypttab ou por mapeamentos abertos em dispositivos de bloco
SWAP_MAPPERS=()
if [ -f /etc/crypttab ]; then
  while read -r name _; do
    if [ -n "$name" ]; then
      SWAP_MAPPERS+=("$name")
    fi
  done < <(grep 'swap' /etc/crypttab || true)
fi

# Adiciona qualquer mapper ativo associado a partição swap
while read -r mname; do
  if [ -n "$mname" ] && [[ ! " ${SWAP_MAPPERS[*]:-} " =~ " ${mname} " ]]; then
    SWAP_MAPPERS+=("$mname")
  fi
done < <(lsblk -lnp -o NAME,TYPE,FSTYPE | grep -i 'swap' | grep 'crypt' | awk '{print $1}' | sed 's|/dev/mapper/||' || true)

# 2.3 Fechar cada container LUKS de swap antes de mexer nas partições
for mapper in "${SWAP_MAPPERS[@]:-}"; do
  if [ -b "/dev/mapper/$mapper" ]; then
    log_step "Fechando container LUKS da swap (/dev/mapper/$mapper)..."
    cryptsetup close "$mapper"
    log_applied "Container /dev/mapper/$mapper fechado."
    record_action
  fi
done

# 2.4 Limpar /etc/crypttab
if [ -f /etc/crypttab ] && grep -q 'swap' /etc/crypttab; then
  log_step "Removendo entrada de swap do /etc/crypttab..."
  sed -i '/swap/d' /etc/crypttab
  log_applied "Entradas de swap removidas do /etc/crypttab."
  INITRAMFS_CHANGED=true
  record_action
else
  log_ok "/etc/crypttab já não possui entradas de swap."
fi

# 2.5 Limpar /etc/fstab
if grep -q '[[:space:]]swap[[:space:]]' /etc/fstab 2>/dev/null; then
  log_step "Removendo entrada de swap do /etc/fstab..."
  sed -i '/[[:space:]]swap[[:space:]]/d' /etc/fstab
  log_applied "Entrada de swap removida do /etc/fstab."
  record_action
else
  log_ok "/etc/fstab já não possui entradas de swap."
fi

# 2.6 Remover resume= do GRUB
if [ -f "$GRUB_CONFIG" ] && grep -q 'resume=' "$GRUB_CONFIG"; then
  log_step "Removendo parâmetro de resume de hibernação do GRUB..."
  sed -i -E 's/resume=[^ "]+//g; s/  */ /g' "$GRUB_CONFIG"
  log_applied "Parâmetro resume= removido do GRUB."
  GRUB_CHANGED=true
  record_action
else
  log_ok "GRUB já não possui parâmetro resume=."
fi

# 2.7 Configurar RESUME=none no initramfs
RESUME_CONF="/etc/initramfs-tools/conf.d/resume"
mkdir -p "$(dirname "$RESUME_CONF")"
if [ ! -f "$RESUME_CONF" ] || [ "$(cat "$RESUME_CONF" 2>/dev/null)" != "RESUME=none" ]; then
  log_step "Configurando RESUME=none em $RESUME_CONF..."
  echo "RESUME=none" > "$RESUME_CONF"
  log_applied "RESUME=none configurado (previne falhas do cryptroot no initramfs)."
  INITRAMFS_CHANGED=true
  record_action
else
  log_ok "Initramfs já configurado com RESUME=none."
fi

# -------------------------------------------------------------------------
# 3. Redimensionar partição raiz (reivindicar espaço da partição de swap a quente)
# -------------------------------------------------------------------------
log_info "3/9 Verificando topologia de disco e redimensionamento online..."

ROOT_SOURCE=$(findmnt -no SOURCE /)
ROOT_PARENT_DEV=""

if [ -n "$ROOT_SOURCE" ]; then
  ROOT_PARENT_DEV=$(lsblk -lnps -o NAME,TYPE "$ROOT_SOURCE" | grep 'part' | head -n 1 | awk '{print $1}' || true)
fi

if [ -n "$ROOT_PARENT_DEV" ]; then
  DISK_DEV=$(lsblk -lnps -o NAME,TYPE "$ROOT_PARENT_DEV" | grep 'disk' | head -n 1 | awk '{print $1}' || true)

  if [ -n "$DISK_DEV" ]; then
    PART_LIST=$(lsblk -lnp -o NAME,TYPE "$DISK_DEV" | grep 'part' | awk '{print $1}')
    PART_COUNT=$(echo "$PART_LIST" | wc -l)
    LAST_PART=$(echo "$PART_LIST" | tail -n 1)

    ROOT_PART_NUM=$(echo "$ROOT_PARENT_DEV" | grep -oP '[0-9]+$')
    LAST_PART_NUM=$(echo "$LAST_PART" | grep -oP '[0-9]+$')

    if [ "$PART_COUNT" -ge 3 ] && [ "$ROOT_PART_NUM" -lt "$LAST_PART_NUM" ]; then
      log_step "Detectada partição residual pós-raiz: $LAST_PART (p$LAST_PART_NUM) no disco $DISK_DEV."

      # Assegurar que qualquer mapper ou holder preso na partição residual seja desativado
      if [ -b "$LAST_PART" ]; then
        HOLDERS=$(lsblk -lnp -o NAME "$LAST_PART" | grep -v "^${LAST_PART}$" || true)
        for h in $HOLDERS; do
          if [[ "$h" == /dev/mapper/* ]]; then
            hname="${h##*/}"
            log_step "Fechando holder ativo $h..."
            cryptsetup close "$hname" 2>/dev/null || dmsetup remove -f "$hname" 2>/dev/null || true
          fi
        done
      fi

      if ! command -v parted >/dev/null 2>&1; then
        log_step "Instalando pacote parted..."
        apt-get update -qq
        apt-get install -y -qq parted
      fi

      log_step "Deletando partição residual $LAST_PART_NUM ($LAST_PART)..."
      parted -s "$DISK_DEV" rm "$LAST_PART_NUM" || true
      log_applied "Comando parted rm executado na partição $LAST_PART_NUM."

      log_step "Expandindo partição física $ROOT_PART_NUM para 100% do disco..."
      parted -s "$DISK_DEV" resizepart "$ROOT_PART_NUM" 100% || true
      log_applied "Comando parted resizepart executado para 100%."

      # Notificar o kernel sobre a nova geometria da partição
      if command -v partprobe >/dev/null 2>&1; then
        partprobe "$DISK_DEV" 2>/dev/null || true
      fi

      # Redimensionar LUKS a quente
      if [[ "$ROOT_SOURCE" == /dev/mapper/* ]]; then
        MAPPER_NAME="${ROOT_SOURCE##*/}"
        log_step "Expandindo container LUKS ($MAPPER_NAME) a quente..."
        cryptsetup resize "$MAPPER_NAME"
        log_applied "Container LUKS $MAPPER_NAME redimensionado."
      fi

      # Redimensionar filesystem a quente
      ROOT_FSTYPE=$(findmnt -no FSTYPE /)
      log_step "Expandindo filesystem online ($ROOT_FSTYPE) em $ROOT_SOURCE..."
      case "$ROOT_FSTYPE" in
        ext4)
          resize2fs "$ROOT_SOURCE"
          log_applied "Filesystem ext4 expandido com sucesso a quente."
          ;;
        btrfs)
          btrfs filesystem resize max /
          log_applied "Filesystem btrfs expandido com sucesso a quente."
          ;;
        *)
          log_warn "Filesystem '$ROOT_FSTYPE' não suportado para expansão automática."
          ;;
      esac

      log_step "Executando TRIM geral nos blocos recém-liberados..."
      fstrim -av
      log_applied "TRIM executado com sucesso."
      record_action
    else
      log_ok "Partição raiz ($ROOT_PARENT_DEV) já ocupa o espaço final do disco ($DISK_DEV). Nenhum resize necessário."
    fi
  else
    log_warn "Não foi possível determinar o disco físico subjacente à partição raiz."
  fi
else
  log_warn "Não foi possível determinar a partição física do ponto de montagem /."
fi

# -------------------------------------------------------------------------
# 4. Otimizar /etc/crypttab com flags NVMe síncronas e TRIM
# -------------------------------------------------------------------------
log_info "4/9 Verificando flags de desempenho NVMe no /etc/crypttab..."

CRYPTTAB="/etc/crypttab"
if [ -f "$CRYPTTAB" ] && [ -s "$CRYPTTAB" ]; then
  if ! grep -q "no-read-workqueue" "$CRYPTTAB"; then
    log_step "Aplicando flags 'discard,no-read-workqueue,no-write-workqueue' no $CRYPTTAB..."
    sed -i -E 's/(luks,initramfs|luks)/\1,discard,no-read-workqueue,no-write-workqueue/' "$CRYPTTAB"
    log_applied "/etc/crypttab otimizado para despacho direto no NVMe."
    INITRAMFS_CHANGED=true
    record_action
  else
    log_ok "/etc/crypttab já possui flags NVMe síncronas configuradas."
  fi
else
  log_ok "/etc/crypttab vazio ou inexistente (criptografia não ativa via crypttab)."
fi

# -------------------------------------------------------------------------
# 5. Configurar sysctl para SSDs e memória
# -------------------------------------------------------------------------
log_info "5/9 Verificando parâmetros de sysctl (/etc/sysctl.d/99-nvme-performance.conf)..."

SYSCTL_CONF="/etc/sysctl.d/99-nvme-performance.conf"
SYSCTL_CONTENT=$(cat << 'EOF'
vm.swappiness = 100
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.vfs_cache_pressure = 50
EOF
)
if [ ! -f "$SYSCTL_CONF" ] || [ "$(cat "$SYSCTL_CONF" 2>/dev/null)" != "$SYSCTL_CONTENT" ]; then
  log_step "Gravando parâmetros de sysctl em $SYSCTL_CONF..."
  mkdir -p "$(dirname "$SYSCTL_CONF")"
  echo "$SYSCTL_CONTENT" > "$SYSCTL_CONF"
  sysctl --system > /dev/null
  log_applied "Parâmetros de sysctl aplicados no kernel."
  record_action
else
  log_ok "Parâmetros de sysctl já sincronizados."
fi

# -------------------------------------------------------------------------
# 6. Configurar regra UDEV para scheduler 'none' em NVMe
# -------------------------------------------------------------------------
log_info "6/9 Verificando regra UDEV de scheduler NVMe (/etc/udev/rules.d/60-nvme-scheduler.rules)..."

UDEV_RULE="/etc/udev/rules.d/60-nvme-scheduler.rules"
UDEV_CONTENT='ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"'
if [ ! -f "$UDEV_RULE" ] || [ "$(cat "$UDEV_RULE" 2>/dev/null)" != "$UDEV_CONTENT" ]; then
  log_step "Configurando scheduler 'none' para filas NVMe em $UDEV_RULE..."
  mkdir -p "$(dirname "$UDEV_RULE")"
  echo "$UDEV_CONTENT" > "$UDEV_RULE"
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=block
  log_applied "Regra UDEV criada e recarregada."
  record_action
else
  log_ok "Regra UDEV de scheduler NVMe já configurada."
fi

# -------------------------------------------------------------------------
# 7. Atualizar initramfs e GRUB se houver alterações
# -------------------------------------------------------------------------
log_info "7/9 Verificando necessidade de compilação de initramfs e GRUB..."

if [ "$INITRAMFS_CHANGED" = true ]; then
  log_step "Regerando imagens do initramfs (update-initramfs -u -k all)..."
  update-initramfs -u -k all
  log_applied "Initramfs regerado com sucesso."
  record_action
else
  log_ok "Nenhuma alteração de subsistema de boot pendente para o initramfs."
fi

if [ "$GRUB_CHANGED" = true ]; then
  log_step "Regerando menu de boot do GRUB (update-grub)..."
  update-grub
  log_applied "GRUB atualizado com sucesso."
  record_action
else
  log_ok "Nenhuma alteração pendente no GRUB."
fi

# -------------------------------------------------------------------------
# 8. Instalar e ativar zram (swap comprimido em RAM)
# -------------------------------------------------------------------------
log_info "8/9 Verificando serviço de swap em RAM (zram-tools)..."

if ! dpkg -l zram-tools 2>/dev/null | grep -q '^ii'; then
  log_step "Instalando zram-tools para paginação comprimida em RAM..."
  apt-get update -qq
  apt-get install -y zram-tools
  systemctl restart zramswap.service || true
  log_applied "zram-tools instalado e ativado."
  record_action
else
  log_ok "Pacote zram-tools já instalado e ativo."
fi

# -------------------------------------------------------------------------
# 9. Dependências essenciais de bootstrap
# -------------------------------------------------------------------------
log_info "9/9 Verificando ferramentas essenciais (pipx, git, curl, sudo)..."

MISSING_PKGS=()
for pkg in pipx git curl sudo; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  log_step "Instalando ferramentas ausentes: ${MISSING_PKGS[*]}..."
  apt-get update -qq
  apt-get install -y "${MISSING_PKGS[@]}"
  log_applied "Ferramentas essenciais instaladas: ${MISSING_PKGS[*]}."
  record_action
else
  log_ok "Todas as ferramentas essenciais já estão instaladas."
fi

# -------------------------------------------------------------------------
# Relatório Final
# -------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${BLUE}   📊 Relatório de Execução do Post-Install${RESET}"
echo -e "${BOLD}${BLUE}====================================================${RESET}"

if [ "$ACTIONS_COUNT" -gt 0 ]; then
  echo -e "${GREEN}${BOLD}✔ Total de ações aplicadas:${RESET} $ACTIONS_COUNT"
  echo -e "${CYAN}O sistema foi calibrado com sucesso.${RESET}"
  echo "Próximos passos sugeridos:"
  echo "  1. (Opcional) Restaurar backups com: ./restore.sh"
  echo "  2. Disparar o Ansible com: ./bootstrap.sh"
else
  echo -e "${GREEN}${BOLD}✔ Nenhuma alteração foi necessária!${RESET}"
  echo -e "${DIM}Todas as otimizações já estavam previamente aplicadas e ativas (idempotência 100%).${RESET}"
fi
echo ""
