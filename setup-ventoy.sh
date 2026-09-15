#!/usr/bin/env bash
# ==============================================================================
# setup-ventoy.sh: Preparação declarativa de mídia Ventoy com Debian Live e Calamares
# Day-0 / Day-1: Particionamento Btrfs, LUKS2 PBKDF2 500ms, zswap e sincronização Ansible
# ==============================================================================
set -euo pipefail

echo "==> Verificando montagem da partição de dados do Ventoy (/dev/sda1)..."
sudo mkdir -p /mnt/ventoy
if ! mountpoint -q /mnt/ventoy; then
  sudo mount /dev/sda1 /mnt/ventoy
fi

echo "==> Criando árvore de diretórios..."
sudo mkdir -p /mnt/ventoy/scripts/calamares/modules /mnt/ventoy/backup

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
# Script auxiliar executado dentro do Debian Live
# -------------------------------------------------------------------------
echo "==> Gerando scripts e configurações do Calamares..."

write_declarative_file /mnt/ventoy/scripts/apply-calamares.sh << 'EOF'
#!/usr/bin/env bash
# ==============================================================================
# apply-calamares.sh: Injeta configurações customizadas no ambiente Debian Live
# ==============================================================================
set -euo pipefail

VENTOY_DEV=$(blkid -L Ventoy 2>/dev/null || echo "/dev/disk/by-label/Ventoy")
sudo mkdir -p /mnt/ventoy
if ! mountpoint -q /mnt/ventoy; then
  sudo mount "$VENTOY_DEV" /mnt/ventoy 2>/dev/null || true
fi

echo "==> Injetando configurações customizadas no Debian Live..."
sudo cp -r /mnt/ventoy/scripts/calamares/modules/* /etc/calamares/modules/
sudo cp /mnt/ventoy/scripts/calamares/settings.conf /etc/calamares/settings.conf

echo "==> Iniciando Calamares em modo verbose..."
sudo calamares -d
EOF
sudo chmod +x /mnt/ventoy/scripts/apply-calamares.sh

# -------------------------------------------------------------------------
# Calamares: settings.conf
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/settings.conf << 'EOF'
---
modules-search: [ local, /usr/lib/x86_64-linux-gnu/calamares/modules ]

instances:
  - id:       ansible_copy
    module:   shellprocess
    config:   shellprocess-ansible-copy.conf
  - id:       ansible
    module:   shellprocess
    config:   shellprocess-ansible.conf

sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
      - users
      - summary
  - exec:
      - partition
      - mount
      - unpackfs
      - machineid
      - fstab
      - locale
      - keyboard
      - localecfg
      - users
      - networkcfg
      - hwclock
      - shellprocess@ansible_copy
      - shellprocess@ansible
      - initramfs
      - grubcfg
      - bootloader
      - umount
  - show:
      - finished

branding: debian
prompt-install: false
dont-chroot: false
oem-setup: false
disable-cancel: false
EOF

# -------------------------------------------------------------------------
# Calamares: locale.conf
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/modules/locale.conf << 'EOF'
---
region: "America"
zone: "Sao_Paulo"
locale: "pt_BR.UTF-8"
EOF

# -------------------------------------------------------------------------
# Calamares: keyboard.conf
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/modules/keyboard.conf << 'EOF'
---
selectedModel: pc105
selectedLayout: br
selectedVariant: abnt2
EOF

# -------------------------------------------------------------------------
# Calamares: users.conf
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/modules/users.conf << 'EOF'
---
defaultGroups:
  - sudo
  - users
  - audio
  - video
  - dialout
  - plugdev
  - netdev
  - kvm

autologinGroup: autologin
doAutologin: false
sudoersGroup: sudo
setRootPassword: false
doReusePassword: true

defaultUsername: eu
defaultHostname: fantasma
EOF

# -------------------------------------------------------------------------
# Calamares: partition.conf
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/modules/partition.conf << 'EOF'
---
userSwapChoices:
  - none

initialSwapChoice: none

defaultFileSystemType: "btrfs"

luksGeneration: luks2

luksKeyslotPBKDF:
  type: pbkdf2
  time: 500
EOF

# -------------------------------------------------------------------------
# Calamares: fstab.conf
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/modules/fstab.conf << 'EOF'
---
mountOptions:
  default: defaults,noatime
  btrfs: defaults,noatime,compress=zstd:1,ssd,discard=async

btrfsSubvolumes:
  - mountPoint: /
    subvolume: /@
  - mountPoint: /home
    subvolume: /@home
  - mountPoint: /var/log
    subvolume: /@log
  - mountPoint: /.snapshots
    subvolume: /@snapshots
EOF

# -------------------------------------------------------------------------
# Calamares: shellprocess-ansible-copy.conf (Executa FORA do chroot)
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/modules/shellprocess-ansible-copy.conf << 'EOF'
---
dontChroot: true
timeout: 120
script:
  - name: "Copiar ansible-debian-desktop da mídia Ventoy para o sistema instalado"
    command: |
      # Identifica dinamicamente o usuário alvo na pasta /home do sistema instalado
      TARGET_USER=$(find @@ROOT@@/home -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | grep -v 'lost+found' | head -n 1 || true)
      if [ -z "$TARGET_USER" ]; then
        TARGET_USER="eu"
      fi

      DEST_DIR="@@ROOT@@/home/$TARGET_USER/du/dev/github"
      mkdir -p "$DEST_DIR"

      if [ -d /mnt/ventoy/scripts/ansible-debian-desktop ]; then
        cp -r /mnt/ventoy/scripts/ansible-debian-desktop "$DEST_DIR/"
        chmod +x "$DEST_DIR/ansible-debian-desktop/"*.sh 2>/dev/null || true
        # Garante a propriedade dos arquivos para o primeiro UID (1000)
        chown -R 1000:1000 "@@ROOT@@/home/$TARGET_USER/du" 2>/dev/null || true
      fi
EOF

# -------------------------------------------------------------------------
# Calamares: shellprocess-ansible.conf (Hooks de Baixo Nível no chroot)
# Configurações essenciais para antes da geração de initramfs e bootloader
# -------------------------------------------------------------------------
write_declarative_file /mnt/ventoy/scripts/calamares/modules/shellprocess-ansible.conf << 'EOF'
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

  # 4. Otimizações de sysctl (swappiness para zswap e flushing contínuo) e scheduler NVMe
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
EOF

# -------------------------------------------------------------------------
# Sincronização do repositório no pendrive (sem reter diretório aberto)
# -------------------------------------------------------------------------
REPO_TARGET="/mnt/ventoy/scripts/ansible-debian-desktop"
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
VENTOY_BACKUP_DIR="/mnt/ventoy/backup"

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
echo "==> Concluído com sucesso. Desmonte com: sudo umount /mnt/ventoy"