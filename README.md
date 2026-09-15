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
  - Instalação de `fprintd` e `libpam-fprintd` para integração nativa com leitores biométricos compatíveis com a `libfprint`, disponibilizando o cadastro de digitais diretamente nas configurações de usuários do GNOME.
- **Flatpak & Flathub:** Suporte nativo ao Flathub integrado ao GNOME Software (`gnome-software-plugin-flatpak`, `xdg-desktop-portal-gnome`), suporte a FUSE (`libfuse2t64`), temas Adwaita/Adw-gtk3, cliente VPN **Trayscale** (`dev.deedles.Trayscale`) e utilitários (`Flatseal`, `Warehouse`, `Extension Manager`).

### 2. Repositórios Upstream Oficiais (`01-extrepo.yaml`)
- Configuração do `extrepo` para Debian Trixie habilitando os repositórios oficiais:
  - **LibreWolf:** Navegador principal focado em privacidade.
  - **VSCodium:** Editor de código com telemetria desativada.
  - **Docker CE & HashiCorp:** Repositórios oficiais utilizados na stack de virtualização.

### 3. Ambiente do Usuário & Shell (`02-usuario.yaml`)
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

### 11. Customização GNOME & Backup/Restore (`99-gnome-extensions.yaml`)
- **Instalação Silenciosa (`gext`):** Utiliza `gnome-extensions-cli` via backend `--filesystem`, dispensando prompts interativos na tela.
- **12 Extensões GNOME 48:**
  - *Dash to Panel* (barra inferior unificada), *AppIndicator*, *Blur my Shell*, *Burn My Windows*, *Caffeine*, *Custom Hot Corners Extended*, *Clipboard Indicator*, *No Overview*, *Tiling Shell*, *Wallpaper Switcher*, *Window Is Ready Remover*, *Fly-Pie*.
- **Transições e Janelas:** Perfil customizado do Burn My Windows (`transicoes.conf`).
- **Restauração Atômica (`dconf`):** Template Jinja2 que sincroniza instantaneamente atalhos de teclado (`Alt+Tab`, `Super+Up`, `Alt+'`), botões de janela (`minimize,maximize,close`) e configurações das extensões.
- **Papel de Parede Bliss:** Papel de parede clássico do Windows XP (alta definição 600 DPI) aplicado automaticamente aos modos claro e escuro.

---

## 💻 Como Usar

### 1. Clonar o repositório
```bash
git clone https://github.com/vndmtrx/ansible-debian-desktop.git
cd ansible-debian-desktop
```

### 2. Executar o bootstrap
```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

O script irá:
1. Configurar o `$PATH` para `~/.local/bin`.
2. Instalar `pipx` e `ansible` se necessário.
3. Exibir o **Relatório do Sistema** com a checagem de runtimes e status do Antigravity.
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

# Executar tudo, exceto virtualização
./bootstrap.sh --skip-tags virt
```

---

## 🚀 Day-0 / Day-1: Preparação de Mídia com Ventoy (`setup-ventoy.sh`)

Para preparar a mídia de instalação com o repositório Ansible e backups de segurança, utilize o script [`setup-ventoy.sh`](setup-ventoy.sh):

```bash
# Com o pendrive Ventoy plugado no computador:
chmod +x setup-ventoy.sh
./setup-ventoy.sh
```

O script:
1. Monta a partição de dados do Ventoy de forma idempotente.
2. Clona/atualiza o repositório Ansible para o pendrive.
3. Sincroniza backups criptografados de `~/du/backups/` para `/backup/` no pendrive.

```text
/mnt/ventoy/
├── debian-live-13.7.0-amd64-gnome.iso
├── backup/                              <-- Backups cifrados (.tar.bz2.gpg)
└── scripts/
    └── ansible-debian-desktop/          <-- Clone local do repositório
```

### 🖥️ Fluxo de Instalação

1. **Boot pelo Ventoy:** Selecione a ISO do Debian Live GNOME no menu do Ventoy.
2. **Instalação Gráfica padrão:** Execute o Calamares normalmente. Na tela de partição, marque **"Apagar disco"** e **"Criptografar sistema"**.
3. **Primeiro Boot — Otimizações de baixo nível:** Ao reiniciar no SSD recém-instalado, monte o pendrive e copie o repositório:

```bash
# 1. Copiar repositório do pendrive
mkdir -p ~/du/dev/github
cp -r /media/$USER/Ventoy/scripts/ansible-debian-desktop ~/du/dev/github/

# 2. Copiar backups (se existirem)
mkdir -p ~/du/backups
cp -p /media/$USER/Ventoy/backup/* ~/du/backups/ 2>/dev/null || true

# 3. Aplicar otimizações de NVMe, GRUB, zram e sysctl
cd ~/du/dev/github/ansible-debian-desktop
sudo ./post-install.sh

# 4. Opcional: restaurar chaves SSH, GPG, chaveiro GNOME e atalhos
./restore.sh

# 5. Disparar o provisionamento completo do ambiente
./bootstrap.sh
```

O **[`post-install.sh`](post-install.sh)** aplica de forma 100% idempotente:
1. **GRUB Cryptodisk:** Habilita `GRUB_ENABLE_CRYPTODISK=y` e pré-carrega módulos `luks`, `crypto`, `btrfs` na imagem EFI.
2. **Boot Rápido:** Remove `splash`, ajusta `GRUB_TIMEOUT=1`.
3. **Eliminação do swap em disco:** Desativa e remove a partição de swap criptografada, limpa `/etc/fstab`, `/etc/crypttab` e o parâmetro `resume=` do GRUB.
4. **Redimensionamento da raiz a quente:** Deleta a partição de swap morta, expande a partição raiz até o limite do disco e redimensiona o container LUKS e o filesystem (ext4 ou btrfs) online.
5. **Pipeline NVMe síncrono & TRIM:** Injeta `discard,no-read-workqueue,no-write-workqueue` em `/etc/crypttab`.
6. **Initramfs Otimizado:** Define `RESUME=none` e regenera a imagem.
7. **Sysctl NVMe:** Configura `/etc/sysctl.d/99-nvme-performance.conf` (`vm.swappiness=100`, etc.).
8. **Scheduler NVMe:** Aplica regra udev com scheduler `none`.
9. **Swap comprimido em RAM (zram):** Instala `zram-tools` com compressão `zstd`, substituindo o swap em disco por um dispositivo de bloco comprimido na memória RAM.
10. **Bootstrap Mínimo:** Instala `pipx`, `git`, `curl` e `sudo`.

---

## ⚙️ Personalização e Boas Práticas

Alinhado às melhores práticas do Ansible (níveis de precedência):
- **[`sistema/defaults/main.yaml`](sistema/defaults/main.yaml):** Valores padrão customizáveis (precedência nível 2). É onde ficam versões de runtimes, listas de pacotes e preferências. Pode ser sobrescrito facilmente por `host_vars`, `group_vars` ou `-e`.
- **[`sistema/vars/main.yaml`](sistema/vars/main.yaml):** Constantes internas e caminhos estruturais (precedência nível 16).

| Variável | Descrição | Padrão |
| :--- | :--- | :--- |
| `atualiza_sistema` | Executa `apt upgrade` completo do sistema | `false` |
| `atualiza_firmware` | Executa atualização de firmware via `fwupdmgr` (LVFS) | `false` |
| `versao_java` | Identificador do Java no SDKMAN! | `'26-tem'` |
| `versao_maven` | Versão do Apache Maven no SDKMAN! | `'3.9.16'` |
| `versao_erlang` | Versão do Erlang/OTP compilada via ASDF | `'29.0.6'` |
| `versao_elixir` | Versão do Elixir instalada via ASDF | `'1.20.4-otp-29'` |
| `versao_asdf` | Versão do binário ASDF (Go) | `'v0.20.0'` |
| `extensoes_gnome` | Lista de extensões GNOME a instalar | *(12 extensões)* |

---

## 📄 Licença

MIT License - Copyright (c) 2025-2026 Eduardo N.S.R.