#!/usr/bin/env bash
# ==============================================================================
# Script: setup-ventoy.sh
# Descrição: Sincroniza o repositório Ansible e backups criptografados
#            para a mídia Ventoy de forma declarativa e idempotente.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [Ventoy-Setup] Iniciando preparação e sincronização da mídia..."

# -------------------------------------------------------------------------
# 1. Detecção dinâmica do ponto de montagem do Ventoy
# -------------------------------------------------------------------------
VENTOY_MOUNT=""

DETECTED_MOUNT=$(findmnt -rn -S LABEL="Ventoy" -o TARGET 2>/dev/null | head -n 1 || true)
if [ -n "$DETECTED_MOUNT" ] && [ -d "$DETECTED_MOUNT" ]; then
  VENTOY_MOUNT="$DETECTED_MOUNT"
elif [ -d "/media/${USER:-$LOGNAME}/Ventoy" ]; then
  VENTOY_MOUNT="/media/${USER:-$LOGNAME}/Ventoy"
fi

if [ -z "$VENTOY_MOUNT" ] || [ ! -d "$VENTOY_MOUNT" ]; then
  VENTOY_DEV="/dev/disk/by-label/Ventoy"
  if [ ! -b "$VENTOY_DEV" ]; then
    echo "❌ Erro: Partição com LABEL 'Ventoy' não foi encontrada."
    echo "   Certifique-se de que o pendrive Ventoy está conectado ao computador."
    exit 1
  fi

  VENTOY_MOUNT="/mnt/ventoy"
  sudo mkdir -p "$VENTOY_MOUNT"
  if ! mountpoint -q "$VENTOY_MOUNT"; then
    echo "==> Montando $VENTOY_DEV em $VENTOY_MOUNT..."
    sudo mount "$VENTOY_DEV" "$VENTOY_MOUNT"
  fi
fi

echo "==> Mídia Ventoy ativa em: $VENTOY_MOUNT"

# -------------------------------------------------------------------------
# 2. Sincronização do repositório Ansible no pendrive
# -------------------------------------------------------------------------
REPO_TARGET="$VENTOY_MOUNT/scripts/ansible-debian-desktop"
sudo mkdir -p "$(dirname "$REPO_TARGET")"

if [ ! -d "$REPO_TARGET" ]; then
  echo "==> Clonando repositório ansible-debian-desktop no pendrive..."
  sudo git clone https://github.com/vndmtrx/ansible-debian-desktop.git "$REPO_TARGET"
else
  echo "==> Repositório Ansible já presente no pendrive. Atualizando..."
  sudo git -C "$REPO_TARGET" pull || true
fi

# -------------------------------------------------------------------------
# 3. Sincronização segura de backups de ~/du/backups para o pendrive
# -------------------------------------------------------------------------
LOCAL_BACKUP_DIR="${HOME}/du/backups"
VENTOY_BACKUP_DIR="$VENTOY_MOUNT/backup"

if [ -d "$LOCAL_BACKUP_DIR" ]; then
  echo "==> Verificando backups locais em $LOCAL_BACKUP_DIR..."
  sudo mkdir -p "$VENTOY_BACKUP_DIR"

  backup_count=0
  while IFS= read -r -d '' bfile; do
    fname=$(basename "$bfile")
    if [ ! -f "$VENTOY_BACKUP_DIR/$fname" ]; then
      echo "    [+] Copiando novo arquivo de backup para o Ventoy: $fname"
      sudo cp -p "$bfile" "$VENTOY_BACKUP_DIR/"
      backup_count=$((backup_count + 1))
    else
      echo "    [=] Arquivo de backup já existente no Ventoy (ignorado): $fname"
    fi
  done < <(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.bz2.gpg" -o -name "*.tar.gz.gpg" -o -name "*.sha256" -o -name "*.asc" \) -print0 2>/dev/null || true)

  echo "==> $backup_count novo(s) arquivo(s) de backup sincronizado(s)."
fi

echo ""
echo "✅ Preparação e sincronização concluídas com sucesso!"
echo "   Estrutura pronta em $VENTOY_MOUNT:"
echo "   - Scripts: $REPO_TARGET"
echo "   - Backups: $VENTOY_BACKUP_DIR"
