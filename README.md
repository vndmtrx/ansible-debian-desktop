# 🔧 Ansible Debian Desktop (Debian 13 Trixie)

Playbook Ansible moderno, modular e **100% idempotente** para provisionamento e padronização completa de ambientes desktop no **Debian 13 (Trixie)**.

Este projeto automatiza a configuração do sistema operacional do zero, garantindo que qualquer máquina recém-formatada fique pronta, segura e com todas as ferramentas de desenvolvimento e customizações visuais exatamente como desejado.

---

## 🚀 O que este Playbook configura

### 0. Bootstrap com Relatório do Sistema (`bootstrap.sh`)
- **Instalação Isolada (PEP 668):** Instala `pipx` e `ansible` de forma segura no perfil do usuário, sem conflitos com pacotes do sistema.
- **Relatório Pré-Execução:**
  - **Status do Google Antigravity:** Detecta compactados em `~/Downloads`, reportando se a instalação atual foi mantida, se a instalação foi ignorada por ausência de arquivos ou se uma nova atualização será aplicada (com remoção posterior dos tarballs).
  - **Verificação de Runtimes:** Inspeciona as versões instaladas de **Java, Maven, Erlang e Elixir**, compara com o playbook (`sistema/defaults/main.yaml`) e consulta novidades upstream, alertando caso existam versões mais recentes disponíveis.
- **Execução Direta:** Invoca o playbook com `--ask-become-pass` e suporte a repasse de flags CLI (`"$@"`).

### 1. Base do Sistema & Segurança (`00-base.yaml`)
- **Fuso Horário, NTP & SSD TRIM:** `America/Sao_Paulo` com sincronização automática via `systemd-timesyncd` e manutenção periódica de descarte de blocos SSD via `fstrim.timer`.
- **Firewall & SSH:** Firewall UFW ativo com regras para OpenSSH e interface gráfica (`gufw`).
- **Terminal & CLI Moderna:**
  - `eza` (substituto moderno do `ls` com suporte a git e ícones)
  - `bat` / `batcat` (visualizador de arquivos moderno com syntax highlighting e paginação)
  - `fd-find` / `fdfind` (busca ultrarrápida de arquivos e diretórios)
  - `du-dust` / `dust` (análise gráfica e intuitiva de uso de disco)
  - `procs` (visualizador moderno de processos com filtros e cores)
  - `duf` (painel moderno e colorido de monitoramento de sistemas de arquivos)
  - `btop` e `glances` (monitores avançados de hardware e processos)
  - `fzf` (fuzzy finder interativo de terminal)
  - `tailspin` (`tspin` nativo do Debian para colorização inteligente de logs)
  - `gdu` (analisador de uso de disco)
  - `mtr-tiny` (diagnóstico de rotas e rede em tempo real)
  - `neowofetch` (sumário visual do sistema)
- **Inspeção de Hardware, Firmware & Diagnóstico:**
  - `fwupd` (Linux Vendor Firmware Service / `fwupdmgr` para detecção e atualização de firmware de UEFI, SSDs NVMe e periféricos)
  - `parted` (manipulação, expansão online e inspeção de tabelas de partição GPT/MBR)
  - `cryptsetup` (utilitários de gerenciamento de volumes criptografados LUKS e dm-crypt)
  - `zram-tools` (gerenciamento automático de swap dinâmico comprimido na memória RAM via `zramswap.service`)
  - `nvme-cli` (ferramenta oficial de telemetria SMART, logs de desgaste e diagnóstico de SSDs NVMe)
  - `hdparm` (medição de taxa de leitura e benchmark de desempenho de I/O em discos e mappers)
  - `usbutils` (fornece `lsusb` para listagem e inspeção de barramento USB)
  - `pciutils` (fornece `lspci` para barramento PCI)
  - `lshw` e `dmidecode` (inventário detalhado de hardware, BIOS, placas e memórias)
  - `lm-sensors` (temperaturas e sensores)
  - `smartmontools` (`smartctl` para telemetria e integridade de discos/SSDs)
  - `psmisc` (`killall`, `fuser`, `pstree`)
  - `curl` e `wget` (ferramentas padrão de download e requisições via terminal)
- **Suporte a Biometria (Impressão Digital):**
  - Instalação de `fprintd` e `libpam-fprintd` para integração nativa com leitores biométricos compatíveis com a `libfprint`, disponibilizando o cadastro e uso de digitais nas configurações de usuários do GNOME e diálogos visuais sem interceptar o `sudo` no terminal com esperas de timeout.
- **Flatpak & Flathub:** Suporte nativo ao Flathub integrado ao GNOME Software (`gnome-software-plugin-flatpak`, `xdg-desktop-portal-gnome`), suporte a FUSE (`libfuse2t64`), temas Adwaita/Adw-gtk3, cliente VPN **Trayscale** (`dev.deedles.Trayscale`) e utilitários (`Flatseal`, `Warehouse`, `Extension Manager`).

### 2. Repositórios Upstream Oficiais (`01-extrepo.yaml`)
- Configuração do `extrepo` para Debian Trixie habilitando os repositórios oficiais:
  - **LibreWolf:** Navegador principal focado em privacidade.
  - **VSCodium:** Editor de código com telemetria desativada.
  - **Docker CE:** Repositório oficial utilizado na stack de virtualização e containers.
  - **Tailscale:** Repositório oficial para a VPN Mesh.

### 3. Ambiente do Usuário & Shell (`02-usuario.yaml`)
- **Elevação de Privilégios Fluida (`sudoers.d`):**
  - Configuração do drop-in `/etc/sudoers.d/99-{{ ansible_user_id }}-nopasswd` com permissões seguras `0440` e validação atômica via `visudo`.
  - Garante `NOPASSWD:ALL` para o usuário logado com precedência sobre as regras do instalador/grupo sudo, eliminando prompts repetitivos de senha em rotinas de automação e desenvolvimento.
- **Padrão XDG & Estrutura de Trabalho:**
  - Binários locais consolidados em `~/.local/bin` (integrado ao `$PATH`).
  - Criação automática dos diretórios de trabalho: `~/du/dev`, `~/du/conf`, `~/du/backups`, `~/du/dev/tensor`, `~/du/dev/github` e `~/du/dev/docker-stacks`.
- **Tilix:** Terminal em mosaico com suporte à integração VTE (`/etc/profile.d/vte-2.91.sh` e link `/etc/profile.d/vte.sh`).
- **Backup & Restauração de Segurança (`backup.sh` & `restore.sh`):**
  - **`./backup.sh` (`backup-seguranca`):** Coleta seletiva e segura de credenciais SSH (`~/.ssh/`), chaveiros GnuPG (chaves públicas, secretas e ownertrust), chaveiros do desktop GNOME (`~/.local/share/keyrings/`), Git e dumps cirúrgicos do `dconf` (extensões, atalhos de janelas e interface). O arquivo é compactado em `.tar.bz2`, criptografado simetricamente por senha via **GPG AES-256** gerando `~/du/backups/YYYYMMDD_HHMMSS.tar.bz2.gpg`, acompanhado de checksum `*.sha256` e assinatura digital `*.asc`.
  - **`./restore.sh` (`restore-seguranca`):** Localiza automaticamente o backup mais recente em `~/du/backups/` (ou em caminho informado explicitamente como argumento), valida o checksum SHA-256, solicita a senha para descriptografar sem exigir chave privada pré-instalada, exibe relatório de componentes e restaura tudo com permissões restritas (`0700`, `0600`, `0644`) e injeção do `dconf`.
  - **`salvar-extensoes`:** Comando utilitário em `~/.local/bin/salvar-extensoes` para exportar rapidamente as preferências do GNOME para `~/du/conf/`.
- **Aliases de Produtividade & IA:**
  - Atalhos de terminal (`ls="eza"`, `ts="tspin"`, `jc="journalctl | tspin"`, etc.).
  - **TensorFlow com Docker (`tensor`):** Sobe um servidor Jupyter com TensorFlow oficial mapeando `~/du/dev/tensor` na porta 8888 em primeiro plano (`-it --rm`) sem sujar o Python do host.
  - **PlantUML com Docker (`plantuml`):** Sobe o servidor oficial Jetty do PlantUML na porta 8080 em primeiro plano (`-it --rm`), pronto para renderizar diagramas e destruindo o contêiner ao encerrar.
    > [!TIP]
    > **Aceleração por Hardware (GPU) no Docker:**
    > O alias padrão executa em **CPU**. Caso queira rodar em uma máquina com GPU dedicada (ex: PC de trabalho), os requisitos para cada fabricante são:
    > - **NVIDIA (CUDA):** Driver NVIDIA instalado + **NVIDIA Container Toolkit** (`nvidia-container-toolkit` configurado no Docker). Imagem: `tensorflow/tensorflow:latest-gpu-jupyter`. Parâmetro: `--gpus all`.
    > - **AMD Radeon (ROCm):** Driver `amdgpu` e ROCm no host (usuário nos grupos `video,render`). Imagem: `rocm/tensorflow:latest`. Parâmetros: `--device=/dev/kfd --device=/dev/dri --group-add video`.
    > - **Intel Arc / Xe:** Drivers de computação OpenCL/Level Zero (`intel-opencl-icd`, `intel-level-zero-gpu`). Imagem: `intel/intel-extension-for-tensorflow:latest`. Parâmetro: `--device=/dev/dri`.
- **Limpeza Automática:** Agendamento no `cron` para mover arquivos com mais de 30 dias em `~/Downloads` para a lixeira (`gio trash`).
- **Touch Input:** Suporte a toque contínuo no LibreWolf (`MOZ_USE_XINPUT2=1` via PAM).

### 4. Runtimes: ASDF (`03-asdf.yaml` & `04-asdf-shims.yaml`)
- **ASDF v0.20.0+:** Binário Go moderno e de alta velocidade instalado em `~/.local/bin/asdf`.
- **Erlang & Elixir:**
  - Compilação do Erlang/OTP 29 (`29.0.6`) com dependências completas (OpenSSL, wxWidgets, Ncurses).
  - Elixir pré-compilado (`1.20.4-otp-29`) integrado via shims e `.tool-versions` global.

### 5. Runtimes: SDKMAN! (`05-sdkman.yaml`)
- Instalação e gestão isolada para o ecossistema JVM:
  - **Java:** Eclipse Temurin OpenJDK 26 (`26-tem`).
  - **Maven:** Apache Maven (`3.9.16`).
  - Configurados automaticamente como versões padrão do sistema.

### 6. Virtualização & Containers (`06-virtualizacao-containers.yaml`)
- **Docker CE:** Motor Docker upstream completo com `docker-compose-plugin` e `docker-buildx-plugin`.
- **KVM/QEMU & Libvirt:** Virtualização nativa de alto desempenho via kernel Linux com GUI `virt-manager`.
- **Vagrant Upstream:** Vagrant 2.4.9 com plugins gerenciados nativamente:
  - `vagrant-libvirt` (provider KVM/QEMU)
  - `vagrant-cachier` (cache inteligente de pacotes entre VMs)
  - `vagrant-hostmanager` (resolução dinâmica de `/etc/hosts` para máquinas virtuais)
- **Permissões:** Usuário integrado aos grupos `docker`, `libvirt`, `kvm` e `libvirt-qemu`.

### 7. Google Antigravity (`07-antigravity.yaml`)
- Instalação modular do **Antigravity Standalone** e **Antigravity IDE**:
  - Extração inteligente de pacotes colocados em `~/Downloads/`.
  - Links simbólicos no `~/.local/bin/` (`antigravity` e `antigravity-ide`).
  - Atalhos `.desktop` com ícones oficiais e integração ao menu de aplicativos do GNOME.
  - Remoção automática dos tarballs pós-instalação para manter o estado limpo e idempotente.

### 8. pCloud Drive (`08-pcloud.yaml`)
- **Instalação AppImage Idempotente:**
  - Baixa ou importa o cliente oficial pCloud Electron 64-bit para `~/.local/share/pcloud/pcloud.AppImage`.
  - Só efetua o download se o binário não estiver presente, respeitando as auto-atualizações posteriores do próprio pCloud.
  - Link simbólico em `~/.local/bin/pcloud` e atalho `.desktop` com extração do ícone oficial para o menu de aplicativos.

### 9. Tailscale VPN (`09-tailscale.yaml`)
- **Rede Mesh & VPN Segura:**
  - Repositório habilitado via `extrepo`.
  - Instalação do pacote `tailscale` e ativação imediata do daemon `tailscaled.service`.
  - Integração com o cliente gráfico **Trayscale** via Flathub (`apps_flatpak`).

### 10. Vivaldi Browser (`10-vivaldi.yaml`)
- **Navegador Secundário Completo:**
  - Configuração da chave GPG oficial em `/etc/apt/keyrings/vivaldi-browser.asc`.
  - Repositório deb822 moderno em `/etc/apt/sources.list.d/vivaldi.sources`.
  - Instalação e atualização automatizada do pacote `vivaldi-stable`.

### 11. Chromium Browser (`11-chromium.yaml`)
- **Configuração Global do Chromium:**
  - Configuração do armazenamento de senhas básico (`--password-store=basic`) em `/etc/chromium.d/password-store`.
  - Evita bloqueios por chaveiro GNOME Keyring em sessões com autologin ativado.

### 12. DNS Seguro: NextDNS DoT & systemd-resolved (`12-dns.yaml`)
- **Resolução Central com Criptografia (DNS-over-TLS):**
  - Instalação e habilitação do `systemd-resolved` como resolvedor local stub listener (`127.0.0.53`).
  - Drop-in declarativo `/etc/systemd/resolved.conf.d/nextdns.conf` configurando upstream NextDNS via DoT (`DNSOverTLS=yes`), rota global padrão (`Domains=~.`), cache local (`Cache=yes`) e retenção de registros expirados (`StaleRetentionSec=1800`), preservando `/etc/systemd/resolved.conf` limpo com os padrões de distribuição e utilizando servidores IPv4 e IPv6 com SNI do perfil (`IP#id.dns.nextdns.io`).
  - Variável `nextdns_id` em `sistema/defaults/main.yaml` facilitando a troca rápida de perfil ou conta.
  - Enforçamento do link simbólico `/etc/resolv.conf -> /run/systemd/resolve/stub-resolv.conf`.
  - Delegação transparente do NetworkManager (`/etc/NetworkManager/conf.d/dns.conf` com `dns=systemd-resolved`).
  - Drop-in global de perfil no NetworkManager (`/etc/NetworkManager/conf.d/99-ignore-dhcp-dns.conf`) com `ipv4.ignore-auto-dns=yes`, `ipv6.ignore-auto-dns=yes` e `dns-priority=100`, impedindo que qualquer interface de rede reivindique `Default Route: yes` ou injete servidores DNS recebidos via DHCP.
  - Integração com o Tailscale MagicDNS (`tailscale up --accept-dns=true`), garantindo resolução privada de nós da rede mesh (`~ts.net`) sem sobrescrever a rota padrão DoT.

### 13. Customização GNOME & Backup/Restore (`99-gnome-extensions.yaml`)
- **Instalação Silenciosa (`gext`):** Utiliza `gnome-extensions-cli` via backend `--filesystem`, dispensando prompts interativos na tela.
- **12 Extensões GNOME 48:**
  - *Dash to Panel* (barra inferior unificada), *AppIndicator*, *Blur my Shell*, *Burn My Windows*, *Caffeine*, *Custom Hot Corners Extended*, *Clipboard Indicator*, *No Overview*, *Tiling Shell*, *Wallpaper Switcher*, *Window Is Ready Remover*, *Fly-Pie*.
- **Transições e Janelas:** Perfil customizado do Burn My Windows (`transicoes.conf`).
- **Restauração Atômica (`dconf`):** Template Jinja2 que sincroniza instantaneamente atalhos de teclado (`Alt+Tab`, `Super+Up`, `Alt+'`), botões de janela (`minimize,maximize,close`) e configurações das extensões.
- **Papel de Parede Bliss:** Papel de parede clássico do Windows XP (alta definição 600 DPI) aplicado automaticamente aos modos claro e escuro.

---

## 💻 Como Usar

### 📋 Passo a Passo no Notebook Físico (Recém-Formatado)

Após realizar a instalação limpa do Debian 13 e o primeiro login:

```bash
# 1. Instalar o Git e clonar o repositório
sudo apt update && sudo apt install -y git
mkdir -p ~/du/dev/github
cd ~/du/dev/github
git clone https://github.com/vndmtrx/ansible-debian-desktop.git
cd ansible-debian-desktop

# 2. Executar as otimizações de baixo nível de Day-0 / Day-1 (LUKS, ZRAM, boot e partição)
# O script realiza a calibração de chaves, expande a partição raiz para 100% e reinicia
sudo ./setup-day0.sh

# 3. Após o reboot, copiar os instaladores do Antigravity para ~/Downloads (se aplicável)
# Coloque 'Antigravity.tar.gz' e 'Antigravity IDE.tar.gz' na pasta ~/Downloads/

# 4. (Opcional) Restaurar chaves SSH, GPG e dotfiles do backup anterior
./restore.sh

# 5. Executar o provisionamento completo do sistema
./bootstrap.sh

# 6. Reiniciar para carregar todos os runtimes e sessão gráfica
sudo reboot
```

---

### ⚙️ Execução Padrão e Bootstrap Local

Para executar o bootstrap em uma máquina que já possui o repositório:

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

O script irá:
1. Configurar o `$PATH` para `~/.local/bin`.
2. Instalar `pipx` e `ansible` de forma isolada.
3. Exibir o **Relatório do Sistema** com o status do Antigravity e verificação de versões upstream (Java, Maven, Erlang, Elixir).
4. Executar o playbook solicitando a senha de `sudo` apenas uma vez.

### 3. Execução Seletiva via Tags

Você pode repassar argumentos e tags diretamente pelo `./bootstrap.sh` (ou via `ansible-playbook`):

```bash
# Executar apenas as customizações do GNOME (extensões, dconf, wallpaper)
./bootstrap.sh --tags gnome

# Executar apenas os runtimes de desenvolvimento (ASDF, SDKMAN, Java, Maven, Erlang, Elixir)
./bootstrap.sh --tags runtimes

# Executar apenas a stack de virtualização e containers (Docker, KVM, Vagrant)
./bootstrap.sh --tags virt

# Executar apenas a instalação do pCloud AppImage
./bootstrap.sh --tags pcloud

# Executar apenas o Tailscale VPN
./bootstrap.sh --tags tailscale

# Executar apenas a instalação do Vivaldi
./bootstrap.sh --tags vivaldi

# Executar apenas a configuração do Chromium
./bootstrap.sh --tags chromium

# Executar tudo, exceto virtualização
./bootstrap.sh --skip-tags virt
```

---

## 🧪 Testbed Automatizado em VM KVM / Libvirt (`testbed/` & `test-e2e-vm.sh`)

Ambiente de teste 100% isolado e repetível para simular a instalação limpa do Debian 13 em uma máquina virtual KVM com aceleração por hardware, validação de baixo nível (Day-0/Day-1) e provisionamento completo com Ansible (Day-2).

### 📋 Passo a Passo do Testbed

```
┌─────────────────────────────────────────┐
│ 1. [HOST] Preparar arquivos em testbed/ │
└────────────────────┬────────────────────┘
                     ▼
┌─────────────────────────────────────────┐
│ 2. [HOST] Executar setup-testbed-vm.sh  │
└────────────────────┬────────────────────┘
                     ▼
┌─────────────────────────────────────────┐
│ 3. [VM]   Instalar Debian 13 (Calamares)│
└────────────────────┬────────────────────┘
                     ▼
┌─────────────────────────────────────────┐
│ 4. [VM]   Subir OpenSSH Server & Chaves │
└────────────────────┬────────────────────┘
                     ▼
┌─────────────────────────────────────────┐
│ 5. [HOST] Executar test-e2e-vm.sh       │
│    (Snapshot, Day-0/1, Reboot, Ansible) │
└─────────────────────────────────────────┘
```

#### Passo 1: Preparar arquivos no Host (Opcional)
Você pode colocar os instaladores do Antigravity e a ISO do Debian na pasta `testbed/` (ignorada no git):
```bash
# Estrutura esperada em testbed/
testbed/
├── debian-live.iso            # ISO do Debian 13 Live GNOME (opcional, baixada automaticamente se ausente)
├── Antigravity.tar.gz         # Instalador do Antigravity Standalone (opcional)
└── Antigravity IDE.tar.gz     # Instalador do Antigravity IDE (opcional)
```

#### Passo 2: Criar e Inicializar a VM no Host
Execute o script de criação da máquina virtual:
```bash
./setup-testbed-vm.sh
```
* Cria a VM `debian-testbed` com 100GB de disco (`qcow2`), 8GB de RAM, 2 vCPUs e UEFI.
* Abre automaticamente o instalador gráfico da ISO.

#### Passo 3: Instalar o Debian na VM
No console gráfico da VM (`virt-manager` ou `virt-viewer`):
1. Abra o instalador **Calamares**.
2. Na tela de particionamento, selecione **"Apagar disco"** (criptografia LUKS opcional).
3. Defina seu nome de usuário e senha.
4. Conclua a instalação e reinicie a VM, fazendo o primeiro login na interface gráfica.

#### Passo 4: Subir o SSH Server na VM
No terminal da VM recém-instalada, execute o comando de inicialização do SSH:
```bash
sudo apt update && sudo apt install -y openssh-server && sudo ssh-keygen -A && sudo systemctl enable --now ssh
```

#### Passo 5: Executar a Automação End-to-End no Host
No terminal do seu Host, execute o orquestrador:
```bash
./test-e2e-vm.sh
```

O script realizará de forma 100% autônoma:
1. **Snapshot `base-clean`:** Cria o snapshot do estado limpo inicial (ou reverte para ele caso já exista, permitindo repetir o teste instantaneamente sem reinstalar).
2. **Conexão Segura:** Injeta sua chave SSH no usuário da VM via `sshpass` e sincroniza o relógio com o host.
3. **Calibrações de Baixo Nível (Day-0/Day-1):** Detecta disco/LUKS dinamicamente, calibra o Slot 0 em 500ms, configura `zram-tools`, expande a partição raiz a quente e ajusta GRUB/initramfs.
4. **Reboot:** Reinicia a VM para inicializar o kernel e initramfs otimizados.
5. **Espelhamento:** Transfere o repositório atual e os compactados do Antigravity para a VM.
6. **Provisionamento Ansible (Day-2):** Executa o `./bootstrap.sh` completo na VM.

---

## 🚀 Day-0 / Day-1: Otimizações de Baixo Nível (`setup-day0.sh`)

Após realizar a instalação limpa do Debian 13 e antes de rodar o Ansible, execute o script de calibração pós-instalação [`setup-day0.sh`](setup-day0.sh):

```bash
cd ~/du/dev/github/ansible-debian-desktop
sudo ./setup-day0.sh
```

O script automatiza com segurança:
1. **Detecção Dinâmica:** Identifica a topologia de armazenamento (LUKS com mapper, partição direta e sistema de arquivos).
2. **Desativação de Swap em Disco:** Configura `RESUME=none`, desativa containers de swap e limpa `/etc/fstab` e `/etc/crypttab`.
3. **Calibração LUKS (PBKDF2 500ms):** Recalibra o Keyslot 0 com iter-time de 500ms e injeta flags de alto desempenho (`discard,no-read-workqueue,no-write-workqueue`) no `/etc/crypttab`.
4. **Swap em RAM (zram):** Instala e ativa o `zram-tools` (`/dev/zram0`).
5. **Expansão Online da Partição Raiz:** Remove a partição legada de swap e expande a partição raiz para 100% do disco a quente.
6. **Ajuste de GRUB e Initramfs:** Remove `splash` e `resume=`, reduz o timeout do GRUB para 1s, mascara `plymouth-quit-wait.service` e executa `update-initramfs -u -k all`.

### 🖥️ Fluxo de Instalação e Primeiro Boot

1. **Instalação Gráfica padrão:** Execute o Calamares normalmente na mídia de instalação (pendrive/Live). Na tela de partição, marque **"Apagar disco"** e **"Criptografar sistema"**.
2. **Primeiro Boot — Otimizações e Provisionamento:** Ao reiniciar no SSD recém-instalado:

```bash
# 1. Clonar o repositório
sudo apt update && sudo apt install -y git
mkdir -p ~/du/dev/github
cd ~/du/dev/github
git clone https://github.com/vndmtrx/ansible-debian-desktop.git
cd ansible-debian-desktop

# 2. Executar as otimizações de Day-0 / Day-1 e reiniciar
sudo ./setup-day0.sh

# 3. (Opcional) Restaurar chaves SSH, GPG, chaveiro GNOME e dotfiles
./restore.sh

# 4. Disparar o provisionamento completo do ambiente (Ansible Day-2)
./bootstrap.sh
```

### 📋 Roteiro de Calibração Manual (Day-0 / Day-1)

As otimizações manuais de baixo nível eliminam gargalos históricos de particionamento, bootloader e escalonamento antes do Ansible assumir o sistema:
1. **Calibração de Boot LUKS:** Recria a chave no **Slot 0** com PBKDF2 em 500ms (`--iter-time 500`), reduzindo iterações de 6M para ~1.4M e eliminando o atraso de descriptografia no GRUB.
2. **GRUB Cryptodisk:** Habilita `GRUB_ENABLE_CRYPTODISK=y` e pré-carrega módulos `luks`, `crypto`, `gcry_rijndael`, `gcry_sha256` na imagem EFI.
3. **Boot Rápido:** Remove `splash`, ajusta `GRUB_TIMEOUT=1`.
4. **Eliminação do swap em disco:** Desativa e remove a partição de swap criptografada, limpa `/etc/fstab`, `/etc/crypttab` e o parâmetro `resume=` do GRUB.
5. **Redimensionamento da raiz a quente:** Deleta a partição de swap morta, expande a partição raiz até o limite do disco e redimensiona o container LUKS e o filesystem online.
6. **Pipeline NVMe síncrono & TRIM:** Injeta `discard,no-read-workqueue,no-write-workqueue` em `/etc/crypttab`.
7. **Initramfs Otimizado:** Define `RESUME=none`, regera imagens com `update-initramfs -u -k all` e atualiza o GRUB.
8. **Sysctl NVMe:** Configura `/etc/sysctl.d/99-nvme-performance.conf` (`vm.swappiness=100`, etc.).
9. **Scheduler NVMe:** Aplica regra udev com scheduler `none`.
10. **Otimização de Userspace:** Mascara `plymouth-quit-wait.service` (elimina até 21s de atraso no display manager) e desativa `NetworkManager-wait-online.service` (elimina 3-5s de retenção desnecessária).
11. **Swap comprimido em RAM (zram):** Instala `zram-tools` com compressão `zstd`, substituindo o swap em disco por um dispositivo de bloco comprimido na memória RAM.
12. **Bootstrap Mínimo:** Instala `pipx`, `git`, `curl` e `sudo`.

Para o passo a passo detalhado com cada comando de análise, atuação e verificação, consulte a [Colinha rápida para a próxima formatação](https://vndmtrx.github.io/posts/otimizacao-boot-luks/#colinha-rapida-para-a-proxima-formatacao).

---

## ⚙️ Personalização e Boas Práticas

Alinhado às melhores práticas do Ansible (níveis de precedência):
- **[`sistema/defaults/main.yaml`](sistema/defaults/main.yaml):** Valores padrão customizáveis (precedência nível 2). É onde ficam versões de runtimes, listas de pacotes e preferências. Pode ser sobrescrito facilmente por `host_vars`, `group_vars` ou `-e`.
- **[`sistema/vars/main.yaml`](sistema/vars/main.yaml):** Constantes internas e caminhos estruturais (precedência nível 16).

| Variável | Descrição | Padrão |
| :--- | :--- | :--- |
| `atualiza_sistema` | Executa `apt upgrade` completo do sistema | `false` |
| `nextdns_id` | Identificador exclusivo de perfil do NextDNS | `'2bf169'` |
| `versao_java` | Identificador do Java no SDKMAN! | `'26-tem'` |
| `versao_erlang` | Versão do Erlang/OTP compilada via ASDF | `'29.0.6'` |
| `versao_elixir` | Versão do Elixir instalada via ASDF | `'1.20.4-otp-29'` |
| `versao_asdf` | Versão do binário ASDF (Go) | `'v0.20.0'` |
| `extensoes_gnome` | Lista de extensões GNOME a instalar | *(12 extensões)* |

---

## 🧰 Guia de Utilitários CLI Modernos (Terminal)

O playbook instala um conjunto completo de utilitários CLI modernos escritos principalmente em **Rust** e **Go**, que substituem comandos tradicionais do Unix por versões mais rápidas, coloridas e informativas:

| Ferramenta | Comando no Debian | Substitui | Destaques / Principais Recursos |
| :--- | :--- | :--- | :--- |
| **`eza`** | `eza` | `ls` | Listagem com cores semânticas, suporte a status Git (`--git`), árvore de diretórios (`-T`) e ícones. |
| **`bat`** | `batcat` | `cat` | Visualizador com *syntax highlighting* para mais de 100 linguagens, paginação automática e integração Git. |
| **`fd-find`** | `fdfind` | `find` | Busca recursiva ultrarrápida, respeita o `.gitignore` por padrão e suporta regex e cores. |
| **`du-dust`** | `dust` | `du` | Visualização gráfica em árvore de barras horizontais do consumo de disco em pastas. |
| **`duf`** | `duf` | `df` | Painel colorido e organizado de sistemas de arquivos, partições montadas e dispositivos de bloco. |
| **`procs`** | `procs` | `ps` | Visualizador moderno de processos com identificação por cores, portas TCP/UDP abertas e visualização em árvore. |
| **`tailspin`** | `tspin` | `tail -f` / `less` | Colorizador e destacador de sintaxe inteligente para logs em tempo real (datas, IPs, URLs, UUIDs, erros). |
| **`btop`** | `btop` | `top` / `htop` | Monitor visual de recursos (CPU, memória, discos, rede e processos) com gráficos responsivos. |
| **`glances`** | `glances` | `top` | Monitor de recursos do sistema em modo terminal, cliente/servidor ou web. |
| **`gdu`** | `gdu` | `ncdu` | Analisador interativo de uso de disco de alta velocidade com navegação por teclado. |
| **`fzf`** | `fzf` | - | *Fuzzy finder* interativo de linha de comando para filtragem rápida de arquivos, comandos e pipes. |

---

## 💻 Aliases e Atalhos do Shell (`~/.bashrc`)

O provisionamento injeta atalhos no `~/.bashrc` (parametrizados em [`sistema/defaults/main.yaml`](sistema/defaults/main.yaml)) para agilidade e produtividade no terminal:

| Alias | Comando Expandido | Descrição / Finalidade |
| :--- | :--- | :--- |
| `ip` | `ip --color=auto` | Versão colorida do comando de rede |
| `ls` | `eza --color=auto` | Versão colorida e moderna do `ls` via `eza` |
| `grep` | `grep --color=auto` | Versão colorida do `grep` |
| `ll` | `ls -lah` | Listagem detalhada incluindo arquivos ocultos |
| `eza` | `eza --color=auto` | Atalho explícito para o `eza` com cores |
| `ts` | `tspin` | Visualizador de logs com highlight automático de sintaxe (`tailspin`) |
| `vg` | `vagrant` | Atalho rápido para gerenciar máquinas virtuais com o Vagrant |
| `jc` | `sudo journalctl -f \| tspin` | Acompanha logs do systemd (`journalctl -f`) colorizados em tempo real |
| `mtr` | `mtr -t` | Diagnóstico interativo de latência/perda de pacotes em modo texto |
| `rebootbios` | `sudo systemctl reboot --firmware` | Reinicia a máquina diretamente no setup da BIOS/UEFI |
| `tensor` | `docker run -it --rm -p 8888:8888 -v $HOME/du/dev/tensor:/tf/notebooks tensorflow/tensorflow:latest-jupyter` | Sobe ambiente interativo do TensorFlow/Jupyter com `--rm` na porta 8888 |
| `plantuml` | `docker run -it --rm -p 8080:8080 plantuml/plantuml-server:jetty` | Sobe servidor local Jetty do PlantUML na porta 8080 (`--rm`) |
| `salvar-extensoes` | `$HOME/.local/bin/salvar-extensoes` | Exporta as preferências ativas do dconf e extensões para `~/du/conf/` |
| `backup-seguranca` | `$HOME/.local/bin/backup-seguranca` | Gera backup comprimido e criptografado com GPG de dotfiles e chaves |
| `restore-seguranca` | `$HOME/.local/bin/restore-seguranca` | Restaura backups criptografados no `$HOME` com validação de integridade |

---

## 📄 Licença

MIT License - Copyright (c) 2025-2026 Eduardo N.S.R.