# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.provision "shell", path: "python.sh"

  NodeCount = 3

 
  config.vm.box = "ubuntu/jammy64"
  config.vm.box_check_update = false
  config.ssh.insert_key = false

  # ArgoCD ports
  config.vm.define "node1" do |node|
    node.vm.hostname = "node1"
    node.vm.network "public_network",
      bridge: "wlp7s0",
      auto_config: true,
      use_dhcp_assigned_default_route: true
      
    node.vm.network "private_network", ip: "192.168.56.101"
    # Проброс портов для доступа к ArgoCD с хоста
    node.vm.network "forwarded_port", 
      guest: 30080,  # HTTP NodePort
      host: 30080,
      host_ip: "0.0.0.0",
      auto_correct: true,
      protocol: "tcp"
      
    node.vm.network "forwarded_port",
      guest: 30443,  # HTTPS NodePort
      host: 30443,
      host_ip: "0.0.0.0",
      auto_correct: true,
      protocol: "tcp"

    node.vm.provider "virtualbox" do |v|
      v.name = "node1"
      v.memory = 2048
      v.cpus = 2
    end
  end

  # node2 и node3
  (2..NodeCount).each do |i|
    config.vm.define "node#{i}" do |node|
      node.vm.hostname = "node#{i}"
      node.vm.network "private_network", ip: "192.168.56.10#{i}"
      
      node.vm.provider "virtualbox" do |v|
        v.name = "node#{i}"
        v.memory = 2048
        v.cpus = 2
      end
    end
  end

  # Общие provisioners для всех узлов
  config.vm.provision "file", source: "~/.ssh/vagrant_ansible_key.pub", destination: "/tmp/authorized_keys"
  
  config.vm.provision "shell", inline: <<-SHELL
    # Настройка SSH
    mkdir -p /home/vagrant/.ssh
    cat /tmp/authorized_keys >> /home/vagrant/.ssh/authorized_keys
    chown -R vagrant:vagrant /home/vagrant/.ssh
    chmod 700 /home/vagrant/.ssh
    chmod 600 /home/vagrant/.ssh/authorized_keys
    rm -f /tmp/authorized_keys
  
  SHELL
end
