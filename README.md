# 🔧 Ansible Debian Desktop

Ansible playbook para automatizar a configuração de uma instalação desktop de Debian

Este projeto nasceu da minha necessidade pessoal de manter meus computadores sempre atualizados e padronizados. Como costumo formatar meus computadores com frequência, seja para testar novas configurações ou manter o sistema limpo, precisava de uma forma automatizada e confiável de recriar meu ambiente de trabalho exatamente como gosto.

O playbook reflete minhas escolhas pessoais de software e configurações para um desktop de uso geral. É um projeto que evolui constantemente conforme mudo minhas preferências - é essencialmente um espelho do que uso no dia a dia.

## Funcionalidades

O playbook está organizado em módulos que tratam de diferentes aspectos do sistema:

### Base do Sistema
- Timezone configurado para Brasil (America/Sao_Paulo)
- Sistema totalmente atualizado com últimas correções
- UFW (Uncomplicated Firewall) habilitado e configurado
- Ferramentas essenciais de terminal como exa (ls moderno), btop (monitor de sistema), fzf (fuzzy finder)
- Suporte a Flatpak com Flathub configurado para aplicações isoladas

### Repositórios Extras
- Extrepo configurado com suporte a repositórios non-free
- LibreWolf como navegador principal focado em privacidade
- VSCodium para desenvolvimento
- VirtualBox para virtualização
- Waydroid para suporte a aplicativos Android

### Configurações de Usuário
- Tilix como emulador de terminal principal
- Aliases úteis pré-configurados no bash
- Limpeza automática de arquivos antigos em Downloads (mais de 30 dias)
- Ajustes de usabilidade no LibreWolf

### Desenvolvimento
- SDKMAN! para gerenciamento de SDKs
- Java 23 em duas distribuições (Oracle e OpenJDK)
- Todas as configurações necessárias no ambiente

### Virtualização e Containers
- VirtualBox e KVM/QEMU para virtualização
- Vagrant com plugins essenciais (cachier, hostmanager, libvirt)
- Configuração automática de grupos e permissões
- Integração com libvirt para melhor desempenho
- Interface gráfica virt-manager para gerenciamento de VMs

### GNOME
- Extensões selecionadas do GNOME Shell
- Blur my Shell para efeitos visuais modernos
- Dash to Dock para um dock personalizável
- Outras extensões para produtividade

## Uso

1. Clone o repositório:
```bash
git clone https://github.com/vndmtrx/ansible-debian-desktop.git
cd ansible-debian-desktop
```

2. Execute o script de bootstrap:
```bash
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

## Licença

Este projeto está licenciado sob a MIT License

Escolhi esta licença porque, embora este seja meu ambiente pessoal, acredito que outros podem se beneficiar dele, seja usando-o como está, adaptando-o às suas necessidades ou apenas aprendendo com as soluções implementadas.

## Contribuindo

Como este playbook reflete meu ambiente pessoal de trabalho, contribuições precisam vir acompanhadas de uma explicação clara sobre como a mudança proposta pode melhorar minha experiência de uso do desktop. Embora sugestões sejam sempre bem-vindas, pull requests devem incluir:

1. Descrição detalhada do benefício da mudança
2. Por que você considera que essa alteração seria útil para o meu workflow
3. Se adicionar novo software, explicar por que ele seria melhor que o atual

O objetivo é manter o playbook focado e eficiente, refletindo um ambiente de trabalho real e em uso.