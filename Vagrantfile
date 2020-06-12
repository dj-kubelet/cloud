# -*- mode: ruby -*-
# vi: set ft=ruby :

default_box = "ubuntu/focal64"
#default_box = "generic/ubuntu2004"
default_memory = "2048"

hosts = [
  {
    "name": "node-0",
    "ip": "172.22.2.10",
  },
  {
    "name":"node-1",
    "ip": "172.22.2.11",
  },
]

Vagrant.configure("2") do |config|

hosts.each do |host|
  name = host[:name]
  config.vm.define name, primary: host.fetch(:primary, false) do |node|
    node.vm.hostname = name
    node.vm.box = host.fetch(:box, default_box)
    #node.vm.synced_folder ".", "/vagrant", disabled: true
    node.vm.network "private_network", ip: host[:ip]

    node.vm.provider "virtualbox" do |vb|
      vb.memory = host.fetch(:memory, default_memory)
      vb.cpus = 2
      vb.customize ["modifyvm", :id, "--uartmode1", "file", File::NULL]
    end

    node.vm.provision "shell", path: "setup.sh"

  end
end

end
