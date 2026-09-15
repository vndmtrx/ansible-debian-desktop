#!/usr/bin/env bash
# ==============================================================================
# Script: setup-ventoy.sh
# Descrição: Sincroniza scripts e módulos do Calamares, repositório Ansible e
#            backups criptografados para a mídia Ventoy de forma declarativa e idempotente.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENTOY_SOURCE_DIR="$REPO_ROOT/ventoy"

echo "==> [Ventoy-Setup] Iniciando preparação e sincronização da mídia..."

# -------------------------------------------------------------------------
# 1. Detecção dinâmica do ponto de montagem do Ventoy
# -------------------------------------------------------------------------
VENTOY_MOUNT=""

# Verifica se já está montado pelo sistema operacional (ex: udisks2 / desktop)
DETECTED_MOUNT=$(findmnt -rn -S LABEL="Ventoy" -o TARGET 2>/dev/null | head -n 1 || true)
if [ -n "$DETECTED_MOUNT" ] && [ -d "$DETECTED_MOUNT" ]; then
  VENTOY_MOUNT="$DETECTED_MOUNT"
elif [ -d "/media/${USER:-$LOGNAME}/Ventoy" ]; then
  VENTOY_MOUNT="/media/${USER:-$LOGNAME}/Ventoy"
fi

# Se não estiver montado, tenta montar de forma controlada
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
sudo mkdir -p "$VENTOY_MOUNT/scripts" "$VENTOY_MOUNT/scripts/modules"

# -------------------------------------------------------------------------
# 2. Função declarativa de sincronização com comparação de hash MD5
# -------------------------------------------------------------------------
sync_declarative_file() {
  local src_file="$1"
  local dest_file="$2"

  if [ ! -f "$src_file" ]; then
    return 0
  fi

  if [ -f "$dest_file" ]; then
    local hash_src hash_dest
    hash_src=$(md5sum "$src_file" | awk '{print $1}')
    hash_dest=$(md5sum "$dest_file" | awk '{print $1}')

    if [ "$hash_src" = "$hash_dest" ]; then
      echo "  [=] Inalterado (MD5 idêntico): $(basename "$dest_file")"
      return 0
    else
      local timestamp backup_old
      timestamp=$(date +%y%m%d%H%M%S)
      backup_old="${dest_file}.old.${timestamp}"
      echo "  [~] Modificação detectada em $(basename "$dest_file")! Fazendo backup: $(basename "$backup_old")"
      sudo mv "$dest_file" "$backup_old"
    fi
  else
    echo "  [+] Criando novo arquivo: $(basename "$dest_file")"
  fi

  sudo cp "$src_file" "$dest_file"
}

# -------------------------------------------------------------------------
# 3. Sincronização dos scripts e módulos da pasta ventoy/
# -------------------------------------------------------------------------
echo "==> Sincronizando scripts e módulos do Calamares..."

if [ -d "$VENTOY_SOURCE_DIR" ]; then
  # Sincroniza scripts raiz (apply-calamares.sh, post-install.sh)
  for sfile in "$VENTOY_SOURCE_DIR"/*.sh; do
    [ -f "$sfile" ] || continue
    sync_declarative_file "$sfile" "$VENTOY_MOUNT/scripts/$(basename "$sfile")"
    sudo chmod +x "$VENTOY_MOUNT/scripts/$(basename "$sfile")"
  done

  # Sincroniza módulos .conf
  if [ -d "$VENTOY_SOURCE_DIR/modules" ]; then
    for cfile in "$VENTOY_SOURCE_DIR/modules"/*.conf; do
      [ -f "$cfile" ] || continue
      sync_declarative_file "$cfile" "$VENTOY_MOUNT/scripts/modules/$(basename "$cfile")"
    done
  fi
fi

# -------------------------------------------------------------------------
# 4. Sincronização do repositório Ansible no pendrive
# -------------------------------------------------------------------------
REPO_TARGET="$VENTOY_MOUNT/scripts/ansible-debian-desktop"
if [ ! -d "$REPO_TARGET" ]; then
  echo "==> Clonando repositório ansible-debian-desktop no pendrive..."
  sudo git clone https://github.com/vndmtrx/ansible-debian-desktop.git "$REPO_TARGET"
else
  echo "==> Repositório Ansible já presente no pendrive. Atualizando..."
  sudo git -C "$REPO_TARGET" pull || true
fi

# -------------------------------------------------------------------------
# 5. Sincronização segura de backups de ~/du/backups para o pendrive
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
  done < <(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f \( -name "*.tar.bz2.gpg" -o -name "*.tar.bz2" -o -name "*.sha256" -o -name "*.asc" \) -print0 2>/dev/null)

  if [ "$backup_count" -gt 0 ]; then
    echo "==> Sincronizado(s) $backup_count novo(s) arquivo(s) de backup."
  fi
fi

sync
echo "==> [Ventoy-Setup] Concluído com sucesso na mídia em $VENTOY_MOUNT."