# 🔧 Ansible Debian Desktop

Ansible playbook para automatizar a configuração de uma instalação desktop de Debian

Este projeto nasceu da minha necessidade pessoal de manter meus computadores sempre atualizados e padronizados. Como costumo formatar meus computadores com frequência, seja para testar novas configurações ou manter o sistema limpo, precisava de uma forma automatizada e confiável de recriar meu ambiente de trabalho exatamente como gosto.

O playbook reflete minhas escolhas pessoais de software e configurações para um desktop de uso geral. É um projeto que evolui constantemente conforme mudo minhas preferências - é essencialmente um espelho do que uso no dia a dia.

## Funcionalidades

O playbook está organizado em módulos que tratam de diferentes aspectos do sistema:

### Base do Sistema
- Timezone configurado para Brasil (America/Sao_Paulo)
- Sistema totalmente atualizado com últimas correções (opcional via variável `atualiza_sistema`)
- UFW (Uncomplicated Firewall) habilitado e configurado (com interface gráfica GUFW)
- Ferramentas essenciais de terminal como:
  - exa (ls moderno)
  - btop (monitor de sistema)
  - fzf (fuzzy finder)
  - Tailspin (visualizador de logs colorido)
  - gdu (analisador de uso de disco)
  - glances (monitor de recursos)
  - mtr (traceroute interativo)
  - neofetch (informações do sistema)
- Suporte a Flatpak com Flathub configurado para aplicações isoladas
  - Inclui temas GTK3 para Flatpak: Adwaita e libadwaita
  - Utilitários como Flatseal e Warehouse para gerenciar aplicativos Flatpak

### Repositórios Extras
- Extrepo configurado com suporte a repositórios non-free e non-free-firmware
- LibreWolf como navegador principal focado em privacidade
- VSCodium para desenvolvimento
- VirtualBox para virtualização
- Waydroid para suporte a aplicativos Android

### Configurações de Usuário
- Tilix como emulador de terminal principal
- Aliases úteis pré-configurados no bash:
  - Melhoria para comandos comuns (ls, ip, grep com cores)
  - Atalhos para ferramentas frequentes (vagrant, tailspin, journalctl)
  - Reinicialização para BIOS/UEFI com um comando
- Limpeza automática de arquivos antigos em Downloads (mais de 30 dias)
- Ajustes de usabilidade no LibreWolf (suporte a touch input)

### Desenvolvimento
- ASDF v0.16.4 para gerenciamento de runtimes e versões
  - Java 23 em duas distribuições (Oracle e OpenJDK)
  - Maven 3.9.9
  - Ruby 3.4.2 e Rails 8.0.1
  - Erlang 27.3.2 e Elixir 1.18.3-otp-27
- Instalação completa com todas as dependências necessárias
- Configuração do PATH e todas as variáveis de ambiente

### Virtualização e Containers
- VirtualBox 7.1 e KVM/QEMU para virtualização
- Vagrant com plugins essenciais:
  - vagrant-cachier (cache de pacotes)
  - vagrant-hostmanager (gerenciamento automático de hosts)
  - vagrant-libvirt (suporte a libvirt/KVM)
- Configuração automática de grupos e permissões para libvirt e KVM
- Interface gráfica virt-manager para gerenciamento de VMs

### GNOME
- Extensões selecionadas do GNOME Shell:
  - Blur my Shell para efeitos visuais modernos
  - Burn my Windows para animações
  - Dash to Dock para um dock personalizável
  - AppIndicator e Clipboard Indicator para produtividade
  - Tiling Shell para gerenciamento de janelas
  - Caffeine para evitar que o sistema entre em suspensão
  - Custom Hot Corners Extended para ações nos cantos da tela
  - No Overview para iniciar diretamente na área de trabalho
  - Wallpaper Switcher para alternar papéis de parede
  - Window Is Ready para remover notificações de janelas

## Aplicações Incluídas

### Aplicações do Sistema
- Navegadores: LibreWolf, Chromium
- Ferramentas gráficas: GIMP, Inkscape (via Flatpak)
- Entretenimento: Stremio (via Flatpak)
- Desenvolvimento: VSCodium
- Redes: Wireshark (via Flatpak)

## Uso

1. Clone o repositório:
```bash
git clone https://github.com/vndmtrx/ansible-debian-desktop.git
cd ansible-debian-desktop
```

2. Execute o script de bootstrap:
```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

O script de bootstrap irá:
- Atualizar os repositórios do sistema
- Instalar Ansible e ansible-lint
- Executar o lint do playbook
- Executar o playbook principal

## Personalização

O playbook pode ser personalizado através das variáveis definidas em `sistema/vars/main.yaml`. Algumas variáveis importantes:

- `atualiza_sistema`: Controla se o sistema será atualizado (padrão: false)
- `pacotes_sistema`: Lista de pacotes essenciais do sistema
- `apps_terminal`: Lista de aplicações de terminal a serem instaladas
- `apps_gui`: Lista de aplicações gráficas a serem instaladas
- `apps_flatpak`: Lista de aplicações Flatpak a serem instaladas
- `repos_extrepo`: Lista de repositórios extrepo a serem habilitados
- `versoes_java_asdf`: Versões do Java a serem instaladas
- `extensoes_gnome`: Lista de extensões GNOME a serem instaladas

## Licença

Este projeto está licenciado sob a MIT License - Copyright (c) 2025 Eduardo N.S.R.

Escolhi esta licença porque, embora este seja meu ambiente pessoal, acredito que outros podem se beneficiar dele, seja usando-o como está, adaptando-o às suas necessidades ou apenas aprendendo com as soluções implementadas.

## Contribuindo

Como este playbook reflete meu ambiente pessoal de trabalho, contribuições precisam vir acompanhadas de uma explicação clara sobre como a mudança proposta pode melhorar minha experiência de uso do desktop. Embora sugestões sejam sempre bem-vindas, pull requests devem incluir:

1. Descrição detalhada do benefício da mudança
2. Por que você considera que essa alteração seria útil para o meu workflow
3. Se adicionar novo software, explicar por que ele seria melhor que o atual

O objetivo é manter o playbook focado e eficiente, refletindo um ambiente de trabalho real e em uso.