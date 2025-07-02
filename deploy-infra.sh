#!/bin/bash

# Параметры (передаются при запуске)
VAGRANT_REPO=$1
ANSIBLE_REPO=$2

# Проверка входных данных
[ -z "$VAGRANT_REPO" ] || [ -z "$ANSIBLE_REPO" ] && { echo "Usage: $0 <vagrant_repo_url> <ansible_repo_url>"; exit 1; }

# Временная директория
WORK_DIR="/tmp/infra_deploy_$(date +%s)"
mkdir -p "$WORK_DIR" && cd "$WORK_DIR" || exit 1

# Функция для обработки ошибок
fail() { echo "Error: $1" >&2; exit 1; }

# 1. Клонируем и выполняем Vagrant репозиторий
echo "=== Cloning Vagrant repo ==="
git clone "$VAGRANT_REPO" vagrant || fail "Failed to clone Vagrant repo"
cd vagrant || exit

echo "=== Starting Vagrant VMs ==="
# Очистка предыдущего состояния
cleanup_vagrant() {
    echo "Cleaning up previous Vagrant environment..."
    sudo pkill -9 -f "VBox" || true
    sudo pkill -9 -f "vagrant" || true
    sudo systemctl restart vboxdrv vboxnetadp vboxnetflt 2>/dev/null || true

    vboxmanage list vms | awk '/node[1-3]/ {gsub(/[{}]/, "", $2); system("vboxmanage controlvm "$2" poweroff 2>/dev/null || true; vboxmanage unregistervm "$2" --delete 2>/dev/null || true")}'
    
    sudo rm -rf \
        ~/"VirtualBox VMs/node"* \
        /tmp/.vbox-*-ipc \
        ~/.config/VirtualBox/* \
        ~/.vagrant.d/tmp/*
        
    vagrant global-status --prune
    rm -rf .vagrant/
    sleep 5
}
cleanup_vagrant




# Запуск ВМ
vagrant up || fail "Vagrant up failed"


# Фиксируем состояние (если нужно)
sync_vagrant_metadata


sync_vagrant_metadata() {
    echo "=== Синхронизация метаданных Vagrant ==="
    # Принудительно обновляем глобальный статус
    vagrant global-status --prune

    # Проверяем, что ВМ видны
    if ! vagrant status | grep -q "running"; then
        echo "Ошибка: ВМ не обнаружены в состоянии 'running'"
        exit 1
    fi

    # Можно также сохранить копию метаданных (на всякий случай)
    cp -r .vagrant ../vagrant_metadata_backup 2>/dev/null || true
}


echo "=== Готово! Состояние ВМ: ==="
vagrant status


# 2. Клонируем и выполняем Ansible репозиторий
echo "=== Cloning Ansible repo ==="
cd "$WORK_DIR" || exit
git clone "$ANSIBLE_REPO" ansible || fail "Failed to clone Ansible repo"
cd ansible || exit

echo "=== Running Ansible playbook ==="
ansible-playbook -i hosts.ini playbook1.yml || fail "Ansible playbook failed"

echo "=== Deployment completed successfully ==="