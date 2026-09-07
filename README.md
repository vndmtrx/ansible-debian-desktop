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
- **Fuso Horário & NTP:** `America/Sao_Paulo` com sincronização automática via `systemd-timesyncd`.
- **Firewall & SSH:** Firewall UFW ativo com regras para OpenSSH e interface gráfica (`gufw`).
- **Terminal & CLI Moderna:**
  - `eza` (substituto moderno do `ls` com suporte a git e ícones)
  - `btop` e `glances` (monitores avançados de hardware e processos)
  - `fzf` (fuzzy finder interativo de terminal)
  - `tailspin` (`tspin` nativo do Debian para colorização inteligente de logs)
  - `gdu` (analisador de uso de disco)
  - `mtr-tiny` (diagnóstico de rotas e rede em tempo real)
  - `neowofetch` (sumário visual do sistema)
- **Flatpak & Flathub:** Suporte nativo ao Flathub integrado ao GNOME Software (`gnome-software-plugin-flatpak`, `xdg-desktop-portal-gnome`), suporte a FUSE (`libfuse2t64`), temas Adwaita/Adw-gtk3, cliente VPN **Trayscale** (`dev.deedles.Trayscale`) e utilitários (`Flatseal`, `Warehouse`, `Extension Manager`).

### 2. Repositórios Upstream Oficiais (`01-extrepo.yaml`)
- Configuração do `extrepo` para Debian Trixie habilitando os repositórios oficiais:
  - **LibreWolf:** Navegador principal focado em privacidade.
  - **VSCodium:** Editor de código com telemetria desativada.
  - **Docker CE & HashiCorp:** Repositórios oficiais utilizados na stack de virtualização.

### 3. Ambiente do Usuário & Shell (`02-usuario.yaml`)
- **Padrão XDG & Estrutura de Trabalho:**
  - Binários locais consolidados em `~/.local/bin` (integrado ao `$PATH`).
  - Criação automática dos diretórios de trabalho: `~/du/dev`, `~/du/conf`, `~/du/dev/tensor`, `~/du/dev/github` e `~/du/dev/docker-stacks`.
- **Tilix:** Terminal em ladrilhos com suporte a integração VTE (`/etc/profile.d/vte.sh`).
- **Backup de Extensões & GNOME (`salvar-extensoes`):** Comando utilitário que exporta as configurações ativas do GNOME e de todas as extensões para `~/du/conf/extensoes_YYYYMMDDHHMMSS.dconf`.
- **Aliases de Produtividade & IA:**
  - Atalhos de terminal (`ls="eza"`, `ts="tspin"`, `jc="journalctl | tspin"`, etc.).
  - **TensorFlow com Docker (`tensor`):** Sobe um servidor Jupyter com TensorFlow oficial mapeando `~/du/dev/tensor` diretamente na porta 8888 sem sujar o Python do host.
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

## ⚙️ Personalização e Boas Práticas

Alinhado às melhores práticas do Ansible (níveis de precedência):
- **[`sistema/defaults/main.yaml`](file:///c:/Users/Pichau/Documentos/dev/ansible-debian-desktop/sistema/defaults/main.yaml):** Valores padrão customizáveis (precedência nível 2). É onde ficam versões de runtimes, listas de pacotes e preferências. Pode ser sobrescrito facilmente por `host_vars`, `group_vars` ou `-e`.
- **[`sistema/vars/main.yaml`](file:///c:/Users/Pichau/Documentos/dev/ansible-debian-desktop/sistema/vars/main.yaml):** Constantes internas e caminhos estruturais (precedência nível 16).

| Variável | Descrição | Padrão |
| :--- | :--- | :--- |
| `atualiza_sistema` | Executa `apt upgrade` completo do sistema | `false` |
| `versao_java` | Identificador do Java no SDKMAN! | `'26-tem'` |
| `versao_maven` | Versão do Apache Maven no SDKMAN! | `'3.9.16'` |
| `versao_erlang` | Versão do Erlang/OTP compilada via ASDF | `'29.0.6'` |
| `versao_elixir` | Versão do Elixir instalada via ASDF | `'1.20.4-otp-29'` |
| `versao_asdf` | Versão do binário ASDF (Go) | `'v0.20.0'` |
| `extensoes_gnome` | Lista de extensões GNOME a instalar | *(12 extensões)* |

---

## 📄 Licença

MIT License - Copyright (c) 2025-2026 Eduardo N.S.R.