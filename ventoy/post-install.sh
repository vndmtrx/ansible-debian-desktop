#!/usr/bin/env bash
# ==============================================================================
# Script: post-install.sh
# Descrição: Otimizador pós-instalação idempotente para Debian 13 (Trixie)
#            Aplica configurações de baixo nível de NVMe, Btrfs, zswap e pacotes
# ==============================================================================
set -euo pipefail

TARGET="${1:-}" # Se passado um diretório (ex: /target ou chroot), aplica nele

if [ -n "$TARGET" ] && [ "$TARGET" != "/" ]; then
  ROOT_PREFIX="$TARGET"
else
  ROOT_PREFIX=""
fi

echo "==> [Post-Install] Iniciando otimizações de sistema em '${ROOT_PREFIX:-/}'..."

# 1. Ajustar flags de performance no crypttab (NVMe síncrono e TRIM)
CRYPTTAB="$ROOT_PREFIX/etc/crypttab"
if [ -f "$CRYPTTAB" ]; then
  if ! grep -q "no-read-workqueue" "$CRYPTTAB"; then
    echo "==> Otimizando /etc/crypttab com flags NVMe síncronas..."
    sed -i -E 's/(luks,initramfs|luks)/\1,discard,no-read-workqueue,no-write-workqueue/' "$CRYPTTAB"
  else
    echo "==> /etc/crypttab já possui flags NVMe otimizadas."
  fi
fi

# 2. Configurar zswap, timeout e remover splash no GRUB
GRUB_CONFIG="$ROOT_PREFIX/etc/default/grub"
GRUB_CHANGED=false

if [ -f "$GRUB_CONFIG" ]; then
  if ! grep -q "zswap.enabled=1" "$GRUB_CONFIG"; then
    echo "==> Ativando zswap com compressor zstd no GRUB..."
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20 zswap.zpool=zsmalloc"/' "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi

  if grep -q "splash" "$GRUB_CONFIG"; then
    echo "==> Removendo splash do GRUB..."
    sed -i 's/splash//g' "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi

  if ! grep -q '^GRUB_TIMEOUT=1' "$GRUB_CONFIG"; then
    echo "==> Ajustando timeout do GRUB para 1s..."
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$GRUB_CONFIG"
    GRUB_CHANGED=true
  fi
fi

# 3. Eliminar hooks residuais de resume de hibernação no initramfs
RESUME_CONF="$ROOT_PREFIX/etc/initramfs-tools/conf.d/resume"
INITRAMFS_CHANGED=false
if [ ! -f "$RESUME_CONF" ] || [ "$(cat "$RESUME_CONF" 2>/dev/null)" != "RESUME=none" ]; then
  echo "==> Desativando resume de hibernação no initramfs..."
  mkdir -p "$(dirname "$RESUME_CONF")"
  echo "RESUME=none" > "$RESUME_CONF"
  INITRAMFS_CHANGED=true
fi

# 4. Configurar sysctl para SSDs e memória (99-nvme-performance.conf)
SYSCTL_CONF="$ROOT_PREFIX/etc/sysctl.d/99-nvme-performance.conf"
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
  if [ -z "$ROOT_PREFIX" ]; then
    sysctl --system > /dev/null 2>&1 || true
  fi
fi

# 5. Configurar regra UDEV para scheduler 'none' em NVMe
UDEV_RULE="$ROOT_PREFIX/etc/udev/rules.d/60-nvme-scheduler.rules"
UDEV_CONTENT='ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"'
if [ ! -f "$UDEV_RULE" ] || [ "$(cat "$UDEV_RULE" 2>/dev/null)" != "$UDEV_CONTENT" ]; then
  echo "==> Configurando scheduler 'none' para NVMe em udev..."
  mkdir -p "$(dirname "$UDEV_RULE")"
  echo "$UDEV_CONTENT" > "$UDEV_RULE"
  if [ -z "$ROOT_PREFIX" ]; then
    udevadm control --reload-rules > /dev/null 2>&1 || true
  fi
fi

# 6. Atualizar initramfs e GRUB se executando dentro do sistema instalado ou via chroot
if [ -z "$ROOT_PREFIX" ]; then
  if [ "$INITRAMFS_CHANGED" = true ]; then
    echo "==> Atualizando initramfs..."
    update-initramfs -u
  fi
  if [ "$GRUB_CHANGED" = true ]; then
    echo "==> Atualizando GRUB..."
    update-grub
  fi
else
  if [ -x "$ROOT_PREFIX/usr/sbin/update-initramfs" ] && [ "$INITRAMFS_CHANGED" = true ]; then
    echo "==> Atualizando initramfs no target chroot..."
    chroot "$ROOT_PREFIX" update-initramfs -u 2>/dev/null || true
  fi
  if [ -x "$ROOT_PREFIX/usr/sbin/update-grub" ] && [ "$GRUB_CHANGED" = true ]; then
    echo "==> Atualizando GRUB no target chroot..."
    chroot "$ROOT_PREFIX" update-grub 2>/dev/null || true
  fi
fi

# 7. Dependências essenciais de bootstrap
if [ -z "$ROOT_PREFIX" ]; then
  echo "==> Verificando dependências essenciais de bootstrap (pipx, git, curl, sudo)..."
  if ! command -v pipx >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq pipx git curl sudo
  fi
fi

echo "==> [Post-Install] Otimizações de sistema aplicadas com sucesso!"
