#!/usr/bin/env bash
# ==============================================================================
# setup-ventoy.sh: Preparação declarativa de mídia Ventoy com Debian Live e Calamares
# Day-0 / Day-1: Particionamento Btrfs, LUKS2 PBKDF2 500ms, zswap e sincronização Ansible
# ==============================================================================
set -euo pipefail

echo "==> Localizando ponto de montagem do pendrive Ventoy..."

# 1. Verifica se já está montado pelo desktop (/media/$USER/Ventoy, /mnt/ventoy, etc.)
VENTOY_MOUNT=$(findmnt -no TARGET -S LABEL=Ventoy 2>/dev/null | head -n 1 || true)

if [ -z "$VENTOY_MOUNT" ]; then
  # Se não achou por LABEL, tenta por dispositivo /dev/disk/by-label/Ventoy
  VENTOY_DEV=$(blkid -L Ventoy 2>/dev/null || lsblk -lpo NAME,LABEL 2>/dev/null | grep -i "Ventoy" | awk '{print $1}' | head -n 1 || true)

  if [ -n "$VENTOY_DEV" ]; then
    VENTOY_MOUNT=$(findmnt -no TARGET "$VENTOY_DEV" 2>/dev/null | head -n 1 || true)
  fi
fi

# 2. Se não estiver montado em lugar nenhum, monta em /mnt/ventoy
if [ -z "$VENTOY_MOUNT" ]; then
  VENTOY_DEV=$(blkid -L Ventoy 2>/dev/null || lsblk -lpo NAME,LABEL 2>/dev/null | grep -i "Ventoy" | awk '{print $1}' | head -n 1 || true)
  if [ -z "$VENTOY_DEV" ]; then
    VENTOY_DEV="/dev/sda1"
  fi

  VENTOY_MOUNT="/mnt/ventoy"
  echo "    Mídia não montada. Montando $VENTOY_DEV em $VENTOY_MOUNT..."
  sudo mkdir -p "$VENTOY_MOUNT"
  if ! mountpoint -q "$VENTOY_MOUNT"; then
    sudo mount "$VENTOY_DEV" "$VENTOY_MOUNT"
  fi
fi

echo "==> Utilizando partição Ventoy em: $VENTOY_MOUNT"

echo "==> Criando árvore de diretórios..."
sudo mkdir -p "$VENTOY_MOUNT/scripts" "$VENTOY_MOUNT/backup"

# -------------------------------------------------------------------------
# Função auxiliar para criação declarativa e versionamento seguro de arquivos
# - Inalterado (md5 igual): Não modifica e preserva a mídia Flash.
# - Modificado (md5 diferente): Move o antigo para .old.YYMMDDHHMMSS e grava o novo.
# - Inexistente: Cria diretamente o novo arquivo.
# -------------------------------------------------------------------------
write_declarative_file() {
  local target_file="$1"
  local temp_file
  temp_file=$(mktemp)

  # Lê o stdin para o arquivo temporário
  cat > "$temp_file"

  if [ -f "$target_file" ]; then
    local hash_target hash_temp
    hash_target=$(md5sum "$target_file" | awk '{print $1}')
    hash_temp=$(md5sum "$temp_file" | awk '{print $1}')

    if [ "$hash_target" = "$hash_temp" ]; then
      echo "  [=] Inalterado (MD5 idêntico): $target_file"
      rm -f "$temp_file"
      return 0
    else
      local timestamp backup_old
      timestamp=$(date +%y%m%d%H%M%S)
      backup_old="${target_file}.old.${timestamp}"
      echo "  [~] Modificação detectada! Fazendo backup para: $(basename "$backup_old")"
      sudo mv "$target_file" "$backup_old"
    fi
  else
    echo "  [+] Criando novo arquivo: $target_file"
  fi

  sudo cp "$temp_file" "$target_file"
  rm -f "$temp_file"
}

# -------------------------------------------------------------------------
# Script auxiliar executado dentro do Debian Live (Injetor Cirúrgico)
# -------------------------------------------------------------------------
echo "==> Gerando injetor apply-calamares.sh..."

write_declarative_file "$VENTOY_MOUNT/scripts/apply-calamares.sh" << 'EOF'
#!/usr/bin/env bash
# ==============================================================================
# apply-calamares.sh: Injeta otimizações no Calamares nativo do Debian Live
# Preserva a integridade do settings.conf original e customiza via sed/conf
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENTOY_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Injetando configurações de baixo nível no Calamares do Debian Live..."

# 1. Configurar partition.conf (Btrfs padrão + LUKS2 PBKDF2 500ms)
sudo tee /etc/calamares/modules/partition.conf > /dev/null << 'PART_CONF'
---
userSwapChoices:
  - none
initialSwapChoice: none
defaultFileSystemType: "btrfs"
luksGeneration: luks2
luksKeyslotPBKDF:
  type: pbkdf2
  time: 500
PART_CONF

# 2. Configurar fstab.conf com subvolumes Btrfs, compressão zstd e flags crypttab
sudo tee /etc/calamares/modules/fstab.conf > /dev/null << 'FSTAB_CONF'
---
mountOptions:
  default: defaults,noatime
  btrfs: defaults,noatime,compress=zstd:1,ssd,discard=async

ssdExtraMountOptions:
  btrfs: discard=async,compress=zstd:1

crypttabOptions: luks,discard,no-read-workqueue,no-write-workqueue

btrfsSubvolumes:
  - mountPoint: /
    subvolume: /@
  - mountPoint: /home
    subvolume: /@home
  - mountPoint: /var/log
    subvolume: /@log
  - mountPoint: /.snapshots
    subvolume: /@snapshots
FSTAB_CONF

# 3. Configurar users.conf com grupos modernos
sudo tee /etc/calamares/modules/users.conf > /dev/null << 'USERS_CONF'
---
userGroup: users
defaultGroups:
  - sudo
  - users
  - audio
  - video
  - dialout
  - plugdev
  - netdev
  - kvm
  - bluetooth
autologinGroup: autologin
sudoersGroup: sudo
setRootPassword: false
doReusePassword: true

defaultUsername: eu
defaultHostname: fantasma

passwordRequirements:
  nonempty: true
  minLength: -1
  maxLength: -1
  libpwquality:
    - minlen=0
    - minclass=0
USERS_CONF

# 4. Configurar módulo nativo shellprocess com os hooks de baixo nível
sudo tee /etc/calamares/modules/shellprocess.conf > /dev/null << 'SHELL_CONF'
---
dontChroot: false
timeout: 300
script:
  # 1. Pipeline NVMe síncrono e TRIM no crypttab
  - name: "Configurar flags síncronas no crypttab"
    command: "sed -i -E 's/(luks,initramfs|luks)/\1,discard,no-read-workqueue,no-write-workqueue/' /etc/crypttab"

  # 2. Configurar zswap, remover splash e ajustar timeout do GRUB para 1s
  - name: "Ativar zswap e otimizar GRUB"
    command: |
      sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20 zswap.zpool=zsmalloc"/' /etc/default/grub
      sed -i 's/splash//g' /etc/default/grub
      sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub

  # 3. Eliminar hooks residuais de resume de hibernação
  - name: "Desativar resume no initramfs"
    command: "echo 'RESUME=none' > /etc/initramfs-tools/conf.d/resume"

  # 4. Otimizações de sysctl e scheduler NVMe
  - name: "Aplicar regras de sysctl e scheduler none para NVMe"
    command: |
      cat << 'SYSCTL' > /etc/sysctl.d/99-nvme-performance.conf
      vm.swappiness = 100
      vm.dirty_background_ratio = 5
      vm.dirty_ratio = 10
      vm.vfs_cache_pressure = 50
      SYSCTL

      cat << 'UDEV' > /etc/udev/rules.d/60-nvme-scheduler.rules
      ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
      UDEV

  # 5. Instalar dependências mínimas para o bootstrap pós-instalação
  - name: "Garantir dependências mínimas de bootstrap"
    command: "apt-get update && apt-get install -y pipx git curl sudo"
SHELL_CONF

# 4. Injetar o job nativo shellprocess no settings.conf original (antes de initramfs/umount)
if ! grep -q "shellprocess" /etc/calamares/settings.conf; then
  sudo sed -i '/- initramfscfg/i \  - shellprocess' /etc/calamares/settings.conf
fi

echo "==> Iniciando Calamares em modo verbose..."
sudo calamares -d

# 5. Hook pós-instalação: Copiar repositório para a partição target instalada
TARGET_ROOT=$(findmnt -no TARGET /dev/mapper/luks-* 2>/dev/null | grep -E '^/tmp/' | head -n 1 || true)
if [ -z "$TARGET_ROOT" ]; then
  TARGET_ROOT=$(findmnt -no TARGET -T /target 2>/dev/null || true)
fi

if [ -n "$TARGET_ROOT" ] && [ -d "$TARGET_ROOT/home" ]; then
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
EOF
sudo chmod +x "$VENTOY_MOUNT/scripts/apply-calamares.sh"

# -------------------------------------------------------------------------
# Sincronização do repositório no pendrive (sem reter diretório aberto)
# -------------------------------------------------------------------------
REPO_TARGET="$VENTOY_MOUNT/scripts/ansible-debian-desktop"
if [ ! -d "$REPO_TARGET" ]; then
  echo "==> Clonando ansible-debian-desktop..."
  sudo git clone https://github.com/vndmtrx/ansible-debian-desktop.git "$REPO_TARGET"
else
  echo "==> Repositório Ansible já presente. Atualizando..."
  sudo git -C "$REPO_TARGET" pull || true
fi

# -------------------------------------------------------------------------
# Sincronização segura de backups de ~/du/backups para a mídia Ventoy
# -------------------------------------------------------------------------
LOCAL_BACKUP_DIR="${HOME}/du/backups"
VENTOY_BACKUP_DIR="$VENTOY_MOUNT/backup"

if [ -d "$LOCAL_BACKUP_DIR" ]; then
  echo "==> Verificando backups locais em $LOCAL_BACKUP_DIR..."
  sudo mkdir -p "$VENTOY_BACKUP_DIR"

  # Copia apenas arquivos que ainda não existem no pendrive (-n / no-clobber)
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
echo "==> Concluído com sucesso na mídia em $VENTOY_MOUNT."