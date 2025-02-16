#!/usr/bin/env bash
#
# Script de bootstrap para Ansible no Debian
# Instala Ansible do repositório oficial e executa o playbook

set -eu

sudo apt-get update
sudo apt-get install -y ansible ansible-lint

ansible-lint

ansible-playbook playbook.yaml