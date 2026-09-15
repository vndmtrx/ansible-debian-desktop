#!/usr/bin/env bash
# ==============================================================================
# apply-calamares.sh: Injeta configurações modulares no Calamares do Debian Live
# Compara hash MD5 antes de substituir e executa o post-install no target
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENTOY_DIR="$(dirname "$SCRIPT_DIR")"
CALAMARES_MODULES_DIR="/etc/calamares/modules"

echo "==> [Calamares-Setup] Verificando e aplicando configurações declarativas..."

sudo mkdir -p "$CALAMARES_MODULES_DIR"

# 1. Injetar módulos comparando hash MD5
if [ -d "$SCRIPT_DIR/modules" ]; then
  for src_file in "$SCRIPT_DIR/modules"/*.conf; do
    [ -f "$src_file" ] || continue
    fname=$(basename "$src_file")
    dest_file="$CALAMARES_MODULES_DIR/$fname"

    if [ -f "$dest_file" ]; then
      src_hash=$(md5sum "$src_file" | awk '{print $1}')
      dest_hash=$(md5sum "$dest_file" | awk '{print $1}')

      if [ "$src_hash" = "$dest_hash" ]; then
        echo "  [=] Módulo inalterado (MD5 idêntico): $fname"
        continue
      else
        timestamp=$(date +%y%m%d%H%M%S)
        echo "  [~] Módulo $fname modificado. Fazendo backup do original..."
        sudo cp "$dest_file" "${dest_file}.old.${timestamp}"
      fi
    else
      echo "  [+] Injetando novo módulo: $fname"
    fi

    sudo cp "$src_file" "$dest_file"
  done
fi

# 2. Garantir disponibilidade do binário do shellprocess no Debian Live
sudo mkdir -p /usr/lib/calamares/modules
if [ -d "/usr/lib/x86_64-linux-gnu/calamares/modules/shellprocess" ] && [ ! -e "/usr/lib/calamares/modules/shellprocess" ]; then
  sudo ln -sf "/usr/lib/x86_64-linux-gnu/calamares/modules/shellprocess" "/usr/lib/calamares/modules/shellprocess"
fi

# 3. Injetar instâncias do shellprocess no settings.conf de forma declarativa
SETTINGS_CONF="/etc/calamares/settings.conf"
if [ -f "$SETTINGS_CONF" ]; then
  if ! grep -q "shellprocess@grubcrypt" "$SETTINGS_CONF"; then
    echo "  [+] Injetando shellprocess@grubcrypt após fstab no settings.conf..."
    sudo sed -i '/- fstab/a \  - shellprocess@grubcrypt' "$SETTINGS_CONF"
  fi

  if ! grep -q "shellprocess@initramfs" "$SETTINGS_CONF"; then
    echo "  [+] Injetando shellprocess@initramfs após bootloader no settings.conf..."
    sudo sed -i '/- bootloader/a \  - shellprocess@initramfs' "$SETTINGS_CONF"
  fi
fi

# 4. Iniciar o Calamares
echo "==> Iniciando Calamares em modo verbose..."
sudo calamares -d

# 5. Hook pós-instalação: Copiar repositório para o usuário no sistema instalado
TARGET_ROOT=$(findmnt -no TARGET /dev/mapper/luks-* 2>/dev/null | grep -E '^/tmp/' | head -n 1 || true)
if [ -z "$TARGET_ROOT" ]; then
  TARGET_ROOT=$(findmnt -no TARGET -T /target 2>/dev/null || true)
fi

if [ -n "$TARGET_ROOT" ] && [ -d "$TARGET_ROOT/etc" ]; then
  TARGET_USER=$(find "$TARGET_ROOT/home" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | grep -v 'lost+found' | head -n 1 || true)
  if [ -n "$TARGET_USER" ]; then
    echo "==> Copiando repositório Ansible para o usuário $TARGET_USER no sistema instalado..."
    USER_DEST="$TARGET_ROOT/home/$TARGET_USER/du/dev/github"
    mkdir -p "$USER_DEST"
    if [ -d "$VENTOY_DIR/scripts/ansible-debian-desktop" ]; then
      cp -r "$VENTOY_DIR/scripts/ansible-debian-desktop" "$USER_DEST/"
      chmod +x "$USER_DEST/ansible-debian-desktop/"*.sh 2>/dev/null || true
      chown -R 1000:1000 "$TARGET_ROOT/home/$TARGET_USER/du" 2>/dev/null || true
    fi
  fi
fi

echo "==> Processo finalizado com sucesso!"
