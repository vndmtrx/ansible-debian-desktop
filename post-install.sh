#!/usr/bin/env bash
# ==============================================================================
# Script: post-install.sh
# Descrição: Otimizador pós-instalação idempotente para Debian 13 (Trixie)
#            Executa no primeiro boot após instalação padrão do Calamares.
#            Aplica configurações de NVMe, GRUB, LUKS, ext4/btrfs, zram e bootstrap.
# ==============================================================================
set -euo pipefail

# Garantir execução como root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Este script deve ser executado como root (use sudo ./post-install.sh)" >&2
  exit 1
fi

echo "==> [Post-Install] Iniciando otimizações de sistema..."

GRUB_CONFIG="/etc/default/grub"
GRUB_CHANGED=false
INITRAMFS_CHANGED=false

# -------------------------------------------------------------------------
# 1. Habilitar suporte a cryptodisk e pré-carregar módulos no GRUB
# -------------------------------------------------------------------------
if [ -f "$GRUB_CONFIG" ]; then
  if grep -q "^GRUB_ENABLE_CRYPTODISK=" "$GRUB_CONFIG"; then
    if ! grep -q "^GRUB_ENABLE_CRYPTODISK=y" "$GRUB_CONFIG"; then
      sed -i 's/^GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' "$GRUB_CONFIG"
      GRUB_CHANGED=true
    fi
  else
    echo "GRUB_ENABLE_CRYPTODISK=y" >> "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi

  # Pré-carregar módulos LUKS na imagem EFI do GRUB
  PRELOAD_TARGET='GRUB_PRELOAD_MODULES="luks crypto gcry_rijndael gcry_sha256 btrfs"'
  if grep -q "^GRUB_PRELOAD_MODULES=" "$GRUB_CONFIG"; then
    CURRENT_PRELOAD=$(grep "^GRUB_PRELOAD_MODULES=" "$GRUB_CONFIG")
    if [ "$CURRENT_PRELOAD" != "$PRELOAD_TARGET" ]; then
      sed -i "s|^GRUB_PRELOAD_MODULES=.*|$PRELOAD_TARGET|" "$GRUB_CONFIG"
      GRUB_CHANGED=true
    fi
  else
    echo "$PRELOAD_TARGET" >> "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi

  # Remover parâmetros de zswap residuais (se existirem)
  if grep -q "zswap\.enabled" "$GRUB_CONFIG"; then
    echo "==> Removendo parâmetros de zswap do GRUB..."
    sed -i -E 's/zswap\.[^ "]+//g; s/  */ /g' "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi

  # Remover splash e ajustar timeout
  if grep -q "splash" "$GRUB_CONFIG"; then
    echo "==> Removendo splash do GRUB..."
    sed -i 's/\bsplash\b//g; s/  */ /g' "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi

  if ! grep -q '^GRUB_TIMEOUT=1' "$GRUB_CONFIG"; then
    echo "==> Ajustando timeout do GRUB para 1s..."
    if grep -q "^GRUB_TIMEOUT=" "$GRUB_CONFIG"; then
      sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$GRUB_CONFIG"
    else
      echo "GRUB_TIMEOUT=1" >> "$GRUB_CONFIG"
    fi
    GRUB_CHANGED=true
  fi
fi

# -------------------------------------------------------------------------
# 2. Desativar swap em disco e limpar referências (/etc/fstab, crypttab, resume)
# -------------------------------------------------------------------------
# Descobrir dispositivos ou partições de swap físicos (excluindo zram)
SWAP_DEVS=$(swapon --show=NAME --noheadings 2>/dev/null | grep -v 'zram' || true)
if [ -n "$SWAP_DEVS" ]; then
  echo "==> Desativando swap ativo em disco..."
  for dev in $SWAP_DEVS; do
    swapoff "$dev"
  done
fi

SWAP_MAPPER=""
if [ -f /etc/crypttab ] && grep -q 'swap' /etc/crypttab; then
  SWAP_MAPPER=$(grep 'swap' /etc/crypttab | awk '{print $1}' || true)
  echo "==> Removendo referências de swap do /etc/crypttab..."
  sed -i '/swap/d' /etc/crypttab
  INITRAMFS_CHANGED=true
fi

if grep -q '[[:space:]]swap[[:space:]]' /etc/fstab 2>/dev/null; then
  echo "==> Removendo referências de swap do /etc/fstab..."
  sed -i '/[[:space:]]swap[[:space:]]/d' /etc/fstab
fi

if [ -f "$GRUB_CONFIG" ] && grep -q 'resume=' "$GRUB_CONFIG"; then
  echo "==> Removendo parâmetro resume= do GRUB..."
  sed -i -E 's/resume=[^ "]+//g; s/  */ /g' "$GRUB_CONFIG"
  GRUB_CHANGED=true
fi

# Desativar resume de hibernação no initramfs (evita erro de cryptroot na compilação)
RESUME_CONF="/etc/initramfs-tools/conf.d/resume"
mkdir -p "$(dirname "$RESUME_CONF")"
if [ ! -f "$RESUME_CONF" ] || [ "$(cat "$RESUME_CONF" 2>/dev/null)" != "RESUME=none" ]; then
  echo "==> Configurando RESUME=none em $RESUME_CONF..."
  echo "RESUME=none" > "$RESUME_CONF"
  INITRAMFS_CHANGED=true
fi

# Fechar mapper de swap se aberto
if [ -n "$SWAP_MAPPER" ] && [ -b "/dev/mapper/$SWAP_MAPPER" ]; then
  echo "==> Fechando container LUKS da swap (/dev/mapper/$SWAP_MAPPER)..."
  cryptsetup close "$SWAP_MAPPER"
fi

# -------------------------------------------------------------------------
# 3. Redimensionar partição raiz (reivindicar espaço da partição de swap a quente)
# -------------------------------------------------------------------------
# Detectar disco onde a raiz reside
ROOT_SOURCE=$(findmnt -no SOURCE /)
ROOT_PARENT_DEV=""

if [ -n "$ROOT_SOURCE" ]; then
  # Identifica a partição física subjacente (ex: /dev/nvme0n1p2 ou /dev/sda2)
  ROOT_PARENT_DEV=$(lsblk -lnps -o NAME,TYPE "$ROOT_SOURCE" | grep 'part' | head -n 1 | awk '{print $1}' || true)
fi

if [ -n "$ROOT_PARENT_DEV" ]; then
  DISK_DEV=$(lsblk -lnps -o NAME,TYPE "$ROOT_PARENT_DEV" | grep 'disk' | head -n 1 | awk '{print $1}' || true)

  if [ -n "$DISK_DEV" ]; then
    # Listar partições no disco ordenadas por número
    PART_LIST=$(lsblk -lnp -o NAME,TYPE "$DISK_DEV" | grep 'part' | awk '{print $1}')
    PART_COUNT=$(echo "$PART_LIST" | wc -l)
    LAST_PART=$(echo "$PART_LIST" | tail -n 1)

    # Obter número da partição raiz e da última partição
    ROOT_PART_NUM=$(echo "$ROOT_PARENT_DEV" | grep -oP '[0-9]+$')
    LAST_PART_NUM=$(echo "$LAST_PART" | grep -oP '[0-9]+$')

    # Se existem 3+ partições e a raiz não é a última partição, a última é a partição de swap morta
    if [ "$PART_COUNT" -ge 3 ] && [ "$ROOT_PART_NUM" -lt "$LAST_PART_NUM" ]; then
      echo "==> Detectada partição morta $LAST_PART (p$LAST_PART_NUM). Redimensionando disco..."

      if ! command -v parted >/dev/null 2>&1; then
        echo "==> Instalando parted..."
        apt-get update -qq
        apt-get install -y -qq parted
      fi

      echo "==> Removendo partição $LAST_PART_NUM ($LAST_PART)..."
      parted -s "$DISK_DEV" rm "$LAST_PART_NUM"

      echo "==> Expandindo partição raiz $ROOT_PART_NUM para 100% do disco..."
      parted -s "$DISK_DEV" resizepart "$ROOT_PART_NUM" 100%

      # Redimensionar container LUKS a quente
      if [[ "$ROOT_SOURCE" == /dev/mapper/* ]]; then
        MAPPER_NAME="${ROOT_SOURCE##*/}"
        echo "==> Redimensionando container LUKS ($MAPPER_NAME) a quente..."
        cryptsetup resize "$MAPPER_NAME"
      fi

      # Redimensionar sistema de arquivos online
      ROOT_FSTYPE=$(findmnt -no FSTYPE /)
      echo "==> Expandindo sistema de arquivos ($ROOT_FSTYPE) a quente..."
      case "$ROOT_FSTYPE" in
        ext4)
          resize2fs "$ROOT_SOURCE"
          ;;
        btrfs)
          btrfs filesystem resize max /
          ;;
        *)
          echo "⚠️  Filesystem '$ROOT_FSTYPE' não suportado para expansão automática."
          ;;
      esac

      echo "==> Executando TRIM em blocos liberados..."
      fstrim -av
    else
      echo "==> Partição raiz já ocupa o espaço contíguo do disco (nenhuma partição residual)."
    fi
  fi
fi

# -------------------------------------------------------------------------
# 4. Otimizar /etc/crypttab com flags NVMe síncronas e TRIM
# -------------------------------------------------------------------------
CRYPTTAB="/etc/crypttab"
if [ -f "$CRYPTTAB" ] && [ -s "$CRYPTTAB" ]; then
  if ! grep -q "no-read-workqueue" "$CRYPTTAB"; then
    echo "==> Otimizando /etc/crypttab com flags NVMe síncronas..."
    sed -i -E 's/(luks,initramfs|luks)/\1,discard,no-read-workqueue,no-write-workqueue/' "$CRYPTTAB"
    INITRAMFS_CHANGED=true
  else
    echo "==> /etc/crypttab já possui flags NVMe otimizadas."
  fi
fi

# -------------------------------------------------------------------------
# 5. Configurar sysctl para SSDs e memória
# -------------------------------------------------------------------------
SYSCTL_CONF="/etc/sysctl.d/99-nvme-performance.conf"
SYSCTL_CONTENT=$(cat << 'EOF'
vm.swappiness = 100
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.vfs_cache_pressure = 50
EOF
)
if [ ! -f "$SYSCTL_CONF" ] || [ "$(cat "$SYSCTL_CONF" 2>/dev/null)" != "$SYSCTL_CONTENT" ]; then
  echo "==> Aplicando parâmetros de sysctl..."
  mkdir -p "$(dirname "$SYSCTL_CONF")"
  echo "$SYSCTL_CONTENT" > "$SYSCTL_CONF"
  sysctl --system > /dev/null
fi

# -------------------------------------------------------------------------
# 6. Configurar regra UDEV para scheduler 'none' em NVMe
# -------------------------------------------------------------------------
UDEV_RULE="/etc/udev/rules.d/60-nvme-scheduler.rules"
UDEV_CONTENT='ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"'
if [ ! -f "$UDEV_RULE" ] || [ "$(cat "$UDEV_RULE" 2>/dev/null)" != "$UDEV_CONTENT" ]; then
  echo "==> Configurando scheduler 'none' para NVMe em udev..."
  mkdir -p "$(dirname "$UDEV_RULE")"
  echo "$UDEV_CONTENT" > "$UDEV_RULE"
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=block
fi

# -------------------------------------------------------------------------
# 7. Atualizar initramfs e GRUB se houver alterações
# -------------------------------------------------------------------------
if [ "$INITRAMFS_CHANGED" = true ]; then
  echo "==> Atualizando initramfs..."
  update-initramfs -u -k all
fi
if [ "$GRUB_CHANGED" = true ]; then
  echo "==> Atualizando GRUB..."
  update-grub
fi

# -------------------------------------------------------------------------
# 8. Instalar e ativar zram (swap comprimido em RAM)
# -------------------------------------------------------------------------
if ! dpkg -l zram-tools 2>/dev/null | grep -q '^ii'; then
  echo "==> Instalando zram-tools para swap comprimido em RAM..."
  apt-get update -qq
  apt-get install -y zram-tools
  systemctl restart zramswap.service || true
else
  echo "==> zram-tools já instalado."
fi

# -------------------------------------------------------------------------
# 9. Dependências essenciais de bootstrap
# -------------------------------------------------------------------------
echo "==> Verificando dependências essenciais (pipx, git, curl, sudo)..."
if ! command -v pipx >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y pipx git curl sudo
fi

echo ""
echo "✅ [Post-Install] Otimizações aplicadas com sucesso!"
echo "   - Swap em disco eliminado e espaço absorvido pela raiz."
echo "   - zram ativo para paginação em RAM."
echo "   - GRUB e crypttab calibrados para NVMe + LUKS."
