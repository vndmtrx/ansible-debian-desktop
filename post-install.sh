#!/usr/bin/env bash
# ==============================================================================
# Script: post-install.sh
# Descrição: Otimizador pós-instalação idempotente para Debian 13 (Trixie)
#            Executa no primeiro boot após instalação padrão do Calamares.
#            Aplica configurações de NVMe, GRUB, Btrfs/LUKS, zram e bootstrap.
# ==============================================================================
set -euo pipefail

echo "==> [Post-Install] Iniciando otimizações de sistema..."

GRUB_CONFIG="/etc/default/grub"
GRUB_CHANGED=false
INITRAMFS_CHANGED=false

# -------------------------------------------------------------------------
# 1. Habilitar suporte a cryptodisk no GRUB
# -------------------------------------------------------------------------
if [ -f "$GRUB_CONFIG" ]; then
  if grep -q "^GRUB_ENABLE_CRYPTODISK=" "$GRUB_CONFIG"; then
    sed -i 's/^GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' "$GRUB_CONFIG"
  else
    echo "GRUB_ENABLE_CRYPTODISK=y" >> "$GRUB_CONFIG"
  fi

  # Pré-carregar módulos LUKS/Btrfs na imagem EFI do GRUB
  if grep -q "^GRUB_PRELOAD_MODULES=" "$GRUB_CONFIG"; then
    sed -i 's/^GRUB_PRELOAD_MODULES=.*/GRUB_PRELOAD_MODULES="luks crypto gcry_rijndael gcry_sha256 btrfs"/' "$GRUB_CONFIG"
  else
    echo 'GRUB_PRELOAD_MODULES="luks crypto gcry_rijndael gcry_sha256 btrfs"' >> "$GRUB_CONFIG"
  fi

  # Remover parâmetros de zswap residuais (se existirem de uma execução anterior)
  if grep -q "zswap\.enabled" "$GRUB_CONFIG"; then
    echo "==> Removendo parâmetros de zswap do GRUB (substituído por zram)..."
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
# 2. Desativar swap em disco e eliminar partição de swap
# -------------------------------------------------------------------------
SWAP_ACTIVE=$(swapon --show --noheadings 2>/dev/null | grep -v zram | head -n 1 || true)
SWAP_PARTITION=$(lsblk -lnp -o NAME,FSTYPE | grep -i 'swap' | awk '{print $1}' | head -n 1 || true)
SWAP_LUKS_PARENT=""

# Detectar se existe partição de swap (criptografada ou não)
if [ -n "$SWAP_ACTIVE" ] || grep -q 'swap' /etc/fstab 2>/dev/null; then
  echo "==> Desativando swap em disco..."

  # Desativar swap ativo
  swapoff -a 2>/dev/null || true

  # Identificar o container LUKS pai da swap (se existir)
  if [ -n "$SWAP_PARTITION" ]; then
    SWAP_LUKS_PARENT=$(lsblk -lnps -o NAME,TYPE "$SWAP_PARTITION" | grep 'part' | awk '{print $1}' | head -n 1 || true)
  fi

  # Remover linhas de swap do fstab
  if grep -q 'swap' /etc/fstab; then
    echo "==> Removendo referências de swap do /etc/fstab..."
    sed -i '/swap/d' /etc/fstab
  fi

  # Remover linhas de swap do crypttab
  if grep -q 'swap' /etc/crypttab 2>/dev/null; then
    echo "==> Removendo referências de swap do /etc/crypttab..."
    # Identificar o nome do mapper da swap pra fechar depois
    SWAP_MAPPER=$(grep 'swap' /etc/crypttab | awk '{print $1}' || true)
    sed -i '/swap/d' /etc/crypttab
    INITRAMFS_CHANGED=true
  fi

  # Remover parâmetro resume= do GRUB
  if grep -q 'resume=' "$GRUB_CONFIG" 2>/dev/null; then
    echo "==> Removendo parâmetro resume= do GRUB..."
    sed -i -E 's/resume=[^ "]+//g; s/  */ /g' "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi

  # Fechar container LUKS da swap (se aberto)
  if [ -n "$SWAP_MAPPER" ] && [ -b "/dev/mapper/$SWAP_MAPPER" ]; then
    echo "==> Fechando container LUKS da swap ($SWAP_MAPPER)..."
    cryptsetup close "$SWAP_MAPPER" 2>/dev/null || true
  fi
fi

# -------------------------------------------------------------------------
# 3. Redimensionar partição raiz (absorver espaço da swap removida)
# -------------------------------------------------------------------------
# Detecta o disco NVMe principal
NVME_DISK=$(lsblk -dnp -o NAME,TYPE | grep 'disk' | grep 'nvme' | awk '{print $1}' | head -n 1 || true)

if [ -n "$NVME_DISK" ] && [ -n "$SWAP_LUKS_PARENT" ]; then
  # Contar partições no disco (excluindo a EFI e a raiz)
  PART_COUNT=$(lsblk -lnp -o NAME,TYPE "$NVME_DISK" | grep 'part' | wc -l)
  ROOT_MAPPER=$(findmnt -no SOURCE /)

  if [ "$PART_COUNT" -ge 3 ]; then
    echo "==> Detectada partição de swap em $SWAP_LUKS_PARENT. Redimensionando disco..."

    # Instalar parted se necessário
    if ! command -v parted >/dev/null 2>&1; then
      apt-get update -qq
      apt-get install -y -qq parted
    fi

    # Número da partição swap (último segmento: nvme0n1p3 -> 3)
    SWAP_PART_NUM=$(echo "$SWAP_LUKS_PARENT" | grep -oP 'p\K[0-9]+$')
    # Número da partição raiz (penúltima: nvme0n1p2 -> 2)
    ROOT_PART_NUM=$((SWAP_PART_NUM - 1))

    echo "==> Removendo partição $SWAP_PART_NUM e expandindo partição $ROOT_PART_NUM..."
    parted -s "$NVME_DISK" rm "$SWAP_PART_NUM"
    parted -s "$NVME_DISK" resizepart "$ROOT_PART_NUM" 100%

    # Expandir container LUKS e filesystem a quente
    if [ -n "$ROOT_MAPPER" ]; then
      MAPPER_NAME="${ROOT_MAPPER##*/}"
      echo "==> Expandindo container LUKS ($MAPPER_NAME)..."
      cryptsetup resize "$MAPPER_NAME"

      # Detectar filesystem e expandir adequadamente
      ROOT_FSTYPE=$(findmnt -no FSTYPE /)
      case "$ROOT_FSTYPE" in
        ext4)
          echo "==> Expandindo ext4 em $ROOT_MAPPER..."
          resize2fs "$ROOT_MAPPER"
          ;;
        btrfs)
          echo "==> Expandindo btrfs em /..."
          btrfs filesystem resize max /
          ;;
        *)
          echo "⚠️  Filesystem '$ROOT_FSTYPE' não suportado para resize automático."
          ;;
      esac
    fi

    echo "==> Executando TRIM nos blocos recém-liberados..."
    fstrim -av 2>/dev/null || true
  fi
else
  if [ -n "$NVME_DISK" ]; then
    echo "==> Nenhuma partição de swap separada detectada. Redimensionamento não necessário."
  fi
fi

# -------------------------------------------------------------------------
# 4. Otimizar crypttab com flags NVMe síncronas e TRIM
# -------------------------------------------------------------------------
CRYPTTAB="/etc/crypttab"
if [ -f "$CRYPTTAB" ]; then
  if ! grep -q "no-read-workqueue" "$CRYPTTAB"; then
    echo "==> Otimizando /etc/crypttab com flags NVMe síncronas..."
    sed -i -E 's/(luks,initramfs|luks)/\1,discard,no-read-workqueue,no-write-workqueue/' "$CRYPTTAB"
    INITRAMFS_CHANGED=true
  else
    echo "==> /etc/crypttab já possui flags NVMe otimizadas."
  fi
fi

# -------------------------------------------------------------------------
# 5. Desativar resume de hibernação no initramfs
# -------------------------------------------------------------------------
RESUME_CONF="/etc/initramfs-tools/conf.d/resume"
if [ ! -f "$RESUME_CONF" ] || [ "$(cat "$RESUME_CONF" 2>/dev/null)" != "RESUME=none" ]; then
  echo "==> Desativando resume de hibernação no initramfs..."
  mkdir -p "$(dirname "$RESUME_CONF")"
  echo "RESUME=none" > "$RESUME_CONF"
  INITRAMFS_CHANGED=true
fi

# -------------------------------------------------------------------------
# 6. Configurar sysctl para SSDs e memória
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
  echo "==> Aplicando parâmetros de sysctl para NVMe..."
  mkdir -p "$(dirname "$SYSCTL_CONF")"
  echo "$SYSCTL_CONTENT" > "$SYSCTL_CONF"
  sysctl --system > /dev/null 2>&1 || true
fi

# -------------------------------------------------------------------------
# 7. Configurar regra UDEV para scheduler 'none' em NVMe
# -------------------------------------------------------------------------
UDEV_RULE="/etc/udev/rules.d/60-nvme-scheduler.rules"
UDEV_CONTENT='ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"'
if [ ! -f "$UDEV_RULE" ] || [ "$(cat "$UDEV_RULE" 2>/dev/null)" != "$UDEV_CONTENT" ]; then
  echo "==> Configurando scheduler 'none' para NVMe em udev..."
  mkdir -p "$(dirname "$UDEV_RULE")"
  echo "$UDEV_CONTENT" > "$UDEV_RULE"
  udevadm control --reload-rules > /dev/null 2>&1 || true
fi

# -------------------------------------------------------------------------
# 8. Atualizar initramfs e GRUB
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
# 9. Instalar e ativar zram (swap comprimido em RAM)
# -------------------------------------------------------------------------
if ! dpkg -l zram-tools 2>/dev/null | grep -q '^ii'; then
  echo "==> Instalando zram-tools para swap comprimido em RAM..."
  apt-get update -qq
  apt-get install -y -qq zram-tools
  # O serviço zramswap.service é habilitado automaticamente na instalação
else
  echo "==> zram-tools já instalado."
fi

# -------------------------------------------------------------------------
# 10. Dependências essenciais de bootstrap
# -------------------------------------------------------------------------
echo "==> Verificando dependências essenciais (pipx, git, curl, sudo)..."
if ! command -v pipx >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq pipx git curl sudo
fi

echo "==> [Post-Install] Otimizações aplicadas com sucesso!"
