#!/bin/bash

# Параметры (передаются при запуске)
VAGRANT_REPO=$1
ANSIBLE_REPO=$2

# Проверка входных данных
if [ -z "$VAGRANT_REPO" ] || [ -z "$ANSIBLE_REPO" ]; then
  echo "Usage: $0 <vagrant_repo_url> <ansible_repo_url>"
  exit 1
fi

# Временная директория
WORK_DIR="/tmp/infra_deploy_$(date +%s)"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit

# Функция для обработки ошибок
fail() {
  echo "Error: $1" >&2
  exit 1
}

# 1. Клонируем и выполняем Vagrant репозиторий
echo "=== Cloning Vagrant repo ==="
git clone "$VAGRANT_REPO" vagrant || fail "Failed to clone Vagrant repo"
cd vagrant || exit

echo "=== Starting Vagrant VMs ==="
vboxmanage list vms | grep -E "node[1-3]" | awk '{print $1}' | xargs -I {} vboxmanage unregister
vm {} --delete 2>/dev/null || true
vagrant destroy -f || echo "No existing VMs to destroy"
vagrant up || fail "Vagrant up failed"

# 2. Клонируем и выполняем Ansible репозиторий
echo "=== Cloning Ansible repo ==="
cd "$WORK_DIR" || exit
git clone "$ANSIBLE_REPO" ansible || fail "Failed to clone Ansible repo"
cd ansible || exit

echo "=== Running Ansible playbook ==="
ansible-playbook -i inventory.ini site.yml || fail "Ansible playbook failed"

echo "=== Deployment completed successfully ==="