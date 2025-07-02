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
# Убиваем все процессы VirtualBox (жестко)
sudo pkill -9 -f "VBox" || true  # Linux/Mac
sudo pkill -9 -f "vagrant" || true
sudo systemctl stop vboxdrv vboxweb-service vboxautostart-service 2>/dev/null || true

# Принудительно удаляем ВМ через их UUID
vboxmanage list vms | grep -E "node[1-3]" | awk '{print $2}' | tr -d '{}' | while read uuid; do
    echo "Удаляем машину с UUID $uuid"
    vboxmanage controlvm "$uuid" poweroff 2>/dev/null || true
    vboxmanage unregistervm "$uuid" --delete 2>/dev/null || true
done

# Чистим файловые следы
sudo rm -rf \
    ~/"VirtualBox VMs/node"* \
    /tmp/.vbox-*-ipc \
    ~/.config/VirtualBox/* \
    ~/.vagrant.d/tmp/*


# Перезапускаем сервис VirtualBox
sudo systemctl restart vboxdrv  # Для Linux
sleep 5 

# Чистка кеша Vagrant
vagrant global-status --prune
rm -rf .vagrant/


vagrant up || fail "Vagrant up failed"

# Проверка, что все ноды запущены
for node in node1 node2 node3; do
    if ! vagrant status "$node" | grep -q "running"; then
        fail "VM $node failed to start"
    fi
done

# Настройка репозиториев с улучшенной обработкой ошибок
configure_repositories() {
    local node=$1
    echo "Configuring repositories for $node"
    
    # Копируем оригинальный sources.list для резервной копии
    vagrant ssh "$node" -c "sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak" || true
    
    # Замена зеркала с проверкой
    if ! vagrant ssh "$node" -c "sudo sed -i 's/us.archive.ubuntu.com/mirrors.kernel.org/g' /etc/apt/sources.list"; then
        echo "Warning: Failed to update sources.list on $node"
        return 1
    fi
    
    # Обновление apt с таймаутом
    if ! vagrant ssh "$node" -c "timeout 60 sudo apt-get update"; then
        echo "Warning: apt-get update failed on $node"
        return 1
    fi
    
    return 0
}

for node in node1 node2 node3; do
    configure_repositories "$node" || true
done

# Восстановление метаданных Vagrant с улучшениями
restore_vagrant_metadata() {
    local vm_name=$1
    
    echo "Restoring metadata for $vm_name"
    
    # Получаем UUID с проверкой ошибок
    uuid=$(VBoxManage list vms | grep "\"$vm_name\"" | awk '{print $2}' | tr -d '{}' 2>/dev/null)
    
    if [ -z "$uuid" ]; then
        echo "Error: Could not find UUID for $vm_name"
        return 1
    fi
    
    # Создаем структуру каталогов с проверкой прав
    if ! mkdir -p ".vagrant/machines/$vm_name/virtualbox"; then
        echo "Error: Failed to create metadata directory for $vm_name"
        return 1
    fi
    
    # Записываем UUID с проверкой
    if ! echo "$uuid" > ".vagrant/machines/$vm_name/virtualbox/id"; then
        echo "Error: Failed to write UUID for $vm_name"
        return 1
    fi
    
    # Валидация записи
    if [ "$(cat ".vagrant/machines/$vm_name/virtualbox/id" 2>/dev/null)" != "$uuid" ]; then
        echo "Error: UUID verification failed for $vm_name"
        return 1
    fi
    
    echo "Successfully restored metadata for $vm_name"
    return 0
}

# Восстанавливаем метаданные для всех нод
metadata_restored=0
for node in node1 node2 node3; do
    if restore_vagrant_metadata "$node"; then
        ((metadata_restored++))
    fi
done

# Проверка подключения с таймаутом
connection_test() {
    timeout 10 vagrant ssh node1 -- echo "Vagrant connection successful" 2>/dev/null
    return $?
}

if connection_test; then
    echo "Vagrant connection verified"
else
    echo "Warning: Vagrant SSH connection issues detected"
    
    # Дополнительная диагностика
    echo "Checking VirtualBox VM status:"
    VBoxManage list runningvms
    
    echo "Checking Vagrant status:"
    vagrant status
    
    fail "Failed to establish Vagrant SSH connection after metadata restoration"
fi


# 2. Клонируем и выполняем Ansible репозиторий
echo "=== Cloning Ansible repo ==="
cd "$WORK_DIR" || exit
git clone "$ANSIBLE_REPO" ansible || fail "Failed to clone Ansible repo"
cd ansible || exit

echo "=== Running Ansible playbook ==="
ansible-playbook -i hosts.ini playbook1.yml || fail "Ansible playbook failed"

echo "=== Deployment completed successfully ==="