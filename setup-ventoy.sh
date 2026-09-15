#!/usr/bin/env bash
# ==============================================================================
# Script: setup-ventoy.sh
# Descrição: Sincroniza scripts, módulos do Calamares, repositório Ansible e
#            backups criptografados para a mídia Ventoy, gerando automaticamente
#            o pacote de Ventoy Injection Plugin e ventoy.json para boot 100% automático.
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
sudo mkdir -p "$VENTOY_MOUNT/scripts" "$VENTOY_MOUNT/scripts/modules" "$VENTOY_MOUNT/ventoy"

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
  # Sincroniza scripts raiz (apply-calamares.sh)
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

# -------------------------------------------------------------------------
# 6. Criação do pacote de Injeção do Ventoy (Ventoy Injection Plugin)
# -------------------------------------------------------------------------
echo "==> Gerando pacote do Ventoy Injection Plugin (/ventoy/scripts-injection.tar.gz)..."
TMP_STAGE=$(mktemp -d)
trap 'rm -rf "$TMP_STAGE"' EXIT

# Estrutura dentro do Live OS
INJECT_SCRIPTS_DIR="$TMP_STAGE/opt/ventoy-scripts"
mkdir -p "$INJECT_SCRIPTS_DIR" "$TMP_STAGE/etc/skel/Desktop" "$TMP_STAGE/home/user/Desktop"

# 1. Copia apply-calamares e módulos
cp "$VENTOY_SOURCE_DIR/apply-calamares.sh" "$INJECT_SCRIPTS_DIR/"
chmod +x "$INJECT_SCRIPTS_DIR/apply-calamares.sh"
cp -r "$VENTOY_SOURCE_DIR/modules" "$INJECT_SCRIPTS_DIR/"

# 2. Copia clone do repositório
cp -r "$REPO_TARGET" "$INJECT_SCRIPTS_DIR/"

# 3. Copia backups criptografados (se existirem)
if [ -d "$VENTOY_BACKUP_DIR" ] && [ "$(ls -A "$VENTOY_BACKUP_DIR" 2>/dev/null)" ]; then
  mkdir -p "$INJECT_SCRIPTS_DIR/backup"
  cp -p "$VENTOY_BACKUP_DIR"/* "$INJECT_SCRIPTS_DIR/backup/" 2>/dev/null || true
fi

# 4. Cria atalho de Desktop no Live CD
DESKTOP_ENTRY=$(cat << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=⚡ Instalar Debian Customizado (Calamares)
Comment=Aplica módulos declarativos e abre o instalador Calamares
Exec=sudo /opt/ventoy-scripts/apply-calamares.sh
Icon=system-software-install
Terminal=true
Categories=System;
EOF
)

echo "$DESKTOP_ENTRY" > "$TMP_STAGE/etc/skel/Desktop/instalar-debian.desktop"
echo "$DESKTOP_ENTRY" > "$TMP_STAGE/home/user/Desktop/instalar-debian.desktop"
chmod +x "$TMP_STAGE/etc/skel/Desktop/instalar-debian.desktop" "$TMP_STAGE/home/user/Desktop/instalar-debian.desktop"

# Compacta pacote para o Ventoy
sudo tar -czf "$VENTOY_MOUNT/ventoy/scripts-injection.tar.gz" -C "$TMP_STAGE" .

# -------------------------------------------------------------------------
# 7. Configuração declarativa do ventoy.json
# -------------------------------------------------------------------------
echo "==> Configurando /ventoy/ventoy.json..."
ISO_LIST=()
while IFS= read -r -d '' isopath; do
  rel_iso="/${isopath#$VENTOY_MOUNT/}"
  ISO_LIST+=("$rel_iso")
done < <(find "$VENTOY_MOUNT" -maxdepth 2 -type f -iname "*.iso" -print0 2>/dev/null)

TMP_JSON=$(mktemp)
cat << 'EOF' > "$TMP_JSON"
{
    "injection": [
EOF

first=true
if [ ${#ISO_LIST[@]} -gt 0 ]; then
  for iso in "${ISO_LIST[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      echo "," >> "$TMP_JSON"
    fi
    cat << EOF >> "$TMP_JSON"
        {
            "image": "$iso",
            "archive": "/ventoy/scripts-injection.tar.gz"
        }
EOF
  done
else
  cat << 'EOF' >> "$TMP_JSON"
        {
            "image": "/debian-live-13.7.0-amd64-gnome.iso",
            "archive": "/ventoy/scripts-injection.tar.gz"
        }
EOF
fi

cat << 'EOF' >> "$TMP_JSON"
    ]
}
EOF

sudo cp "$TMP_JSON" "$VENTOY_MOUNT/ventoy/ventoy.json"
rm -f "$TMP_JSON"

sync
echo "==> [Ventoy-Setup] Concluído com sucesso na mídia em $VENTOY_MOUNT."