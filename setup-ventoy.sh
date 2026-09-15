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
sudo mkdir -p /mnt/ventoy/scripts/calamares/modules

# -------------------------------------------------------------------------
# Script auxiliar executado dentro do Debian Live
# -------------------------------------------------------------------------
sudo tee /mnt/ventoy/scripts/apply-calamares.sh > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

VENTOY_DEV=$(blkid -L Ventoy || echo "/dev/disk/by-label/Ventoy")
mkdir -p /mnt/ventoy
if ! mountpoint -q /mnt/ventoy; then
  mount "$VENTOY_DEV" /mnt/ventoy 2>/dev/null || true
fi

echo "Injetando configurações customizadas no Debian Live..."
sudo cp -r /mnt/ventoy/scripts/calamares/modules/* /etc/calamares/modules/
sudo cp /mnt/ventoy/scripts/calamares/settings.conf /etc/calamares/settings.conf

echo "Iniciando Calamares em modo verbose..."
sudo calamares -d
EOF
sudo chmod +x /mnt/ventoy/scripts/apply-calamares.sh

# -------------------------------------------------------------------------
# Calamares: settings.conf
# -------------------------------------------------------------------------
sudo tee /mnt/ventoy/scripts/calamares/settings.conf > /dev/null << 'EOF'
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
sudo tee /mnt/ventoy/scripts/calamares/modules/locale.conf > /dev/null << 'EOF'
---
region: "America"
zone: "Sao_Paulo"
locale: "pt_BR.UTF-8"
EOF

# -------------------------------------------------------------------------
# Calamares: keyboard.conf
# -------------------------------------------------------------------------
sudo tee /mnt/ventoy/scripts/calamares/modules/keyboard.conf > /dev/null << 'EOF'
---
selectedModel: pc105
selectedLayout: br
selectedVariant: abnt2
EOF

# -------------------------------------------------------------------------
# Calamares: users.conf
# -------------------------------------------------------------------------
sudo tee /mnt/ventoy/scripts/calamares/modules/users.conf > /dev/null << 'EOF'
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
sudo tee /mnt/ventoy/scripts/calamares/modules/partition.conf > /dev/null << 'EOF'
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
sudo tee /mnt/ventoy/scripts/calamares/modules/fstab.conf > /dev/null << 'EOF'
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
sudo tee /mnt/ventoy/scripts/calamares/modules/shellprocess-ansible-copy.conf > /dev/null << 'EOF'
---
dontChroot: true
timeout: 120
script:
  - name: "Copiar ansible-debian-desktop da mídia Ventoy para o sistema instalado"
    command: |
      TARGET_USER="${USER:-eu}"
      DEST_DIR="@@ROOT@@/home/$TARGET_USER/du/dev/github"
      mkdir -p "$DEST_DIR"
      if [ -d /mnt/ventoy/scripts/ansible-debian-desktop ]; then
        cp -r /mnt/ventoy/scripts/ansible-debian-desktop "$DEST_DIR/"
        chmod +x "$DEST_DIR/ansible-debian-desktop/bootstrap.sh" 2>/dev/null || true
      fi
EOF

# -------------------------------------------------------------------------
# Calamares: shellprocess-ansible.conf (Hooks de Baixo Nível no chroot)
# -------------------------------------------------------------------------
sudo tee /mnt/ventoy/scripts/calamares/modules/shellprocess-ansible.conf > /dev/null << 'EOF'
---
dontChroot: false
timeout: 600
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

  # 4. Configurar deb822 com repositórios oficiais e backports habilitado
  - name: "Configurar repositórios oficiais e backports em deb822"
    command: |
      cat << 'SOURCES' > /etc/apt/sources.list.d/debian.sources
      Types: deb deb-src
      URIs: http://deb.debian.org/debian/
      Suites: trixie trixie-updates trixie-backports
      Components: main contrib non-free non-free-firmware
      Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

      Types: deb deb-src
      URIs: http://security.debian.org/debian-security/
      Suites: trixie-security
      Components: main contrib non-free non-free-firmware
      Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
      SOURCES

  # 5. Otimizações de sysctl (swappiness para zswap e flushing contínuo) e scheduler NVMe
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

  # 6. Regenerar initramfs e menu do GRUB
  - name: "Regenerar initramfs e menu do GRUB"
    command: "update-initramfs -u -k all && update-grub"

  # 7. Instalar dependências base do sistema para o Day-2
  - name: "Instalar ferramentas base do sistema"
    command: "apt-get update && apt-get install -y pipx git curl sudo btrfs-progs parted udev fwupd openssh-server"

  # 8. Habilitar timers de integridade (Btrfs Scrub e TRIM semanal)
  - name: "Ativar timers de integridade do Btrfs e TRIM"
    command: |
      systemctl enable btrfs-scrub.timer
      systemctl enable fstrim.timer

  # 9. Mascarar Plymouth e desativar espera do NetworkManager
  - name: "Eliminar gargalos de espera no userspace"
    command: |
      systemctl mask plymouth-quit-wait.service
      systemctl disable NetworkManager-wait-online.service

  # 10. Garantir flag ESP na partição EFI para o fwupd/LVFS
  - name: "Conformidade da flag ESP para fwupd"
    command: |
      BOOT_DEV=$(findmnt -no SOURCE /boot/efi 2>/dev/null || true)
      if [ -n "$BOOT_DEV" ]; then
        DISK=$(echo "$BOOT_DEV" | sed -E 's/p?[0-9]+$//')
        PARTNUM=$(echo "$BOOT_DEV" | grep -o '[0-9]*$')
        parted -s "$DISK" set "$PARTNUM" esp on
      fi

  # 11. Ajustar permissões do repositório copiado
  - name: "Ajustar permissões do repositório Ansible"
    command: |
      TARGET_USER=$(id -nu 1000 2>/dev/null || echo "eu")
      if [ -d "/home/$TARGET_USER/du" ]; then
        chown -R 1000:1000 "/home/$TARGET_USER/du"
      fi

  # 12. Gerar chave SSH id_ed25519 com o e-mail solicitado
  - name: "Gerar novo par de chaves SSH id_ed25519"
    command: |
      TARGET_USER=$(id -nu 1000 2>/dev/null || echo "eu")
      USER_HOME="/home/$TARGET_USER"
      mkdir -p "$USER_HOME/.ssh"
      if [ ! -f "$USER_HOME/.ssh/id_ed25519" ]; then
        ssh-keygen -t ed25519 -N "" -C "vndmtrx@duck.com" -f "$USER_HOME/.ssh/id_ed25519"
      fi
      chmod 700 "$USER_HOME/.ssh"
      chmod 600 "$USER_HOME/.ssh/id_ed25519"
      chmod 644 "$USER_HOME/.ssh/id_ed25519.pub"
      chown -R 1000:1000 "$USER_HOME/.ssh"
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

sync
echo "==> Concluído com sucesso. Desmonte com: sudo umount /mnt/ventoy"