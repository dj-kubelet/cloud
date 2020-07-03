#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

apt-get install -y \
    unzip \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    gnupg2 \
    certbot \
    curl \
    git \
    golang-cfssl \
    jq \
    socat

main() {
    disable_swap
    setup_sysctl
    install_docker
    install_kind "0.8.1"
    install_k8s kubectl
    clone_dj_kubelet_repos
}

disable_swap() {
    systemctl mask dev-sda2.swap
    swapoff -a
    sed -i '/swap/d' /etc/fstab
}

setup_sysctl() {
    cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
    sysctl --system
}

install_docker() {
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-cache policy docker-ce
    apt-get install -y docker-ce
    systemctl status docker
    #usermod -aG docker "$USER"
}

install_kind() {
    local version="$1"
    curl -sLo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v${version}/kind-$(uname)-amd64"
    chmod +x /usr/local/bin/kind
    kind completion bash >/etc/bash_completion.d/kind
}

install_k8s() {
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
    apt-get update -y
    apt-get install -y "$@"
    apt-mark hold "$@"
    if [[ "$*" =~ "kubectl" ]]; then
        kubectl completion bash >/etc/bash_completion.d/kubectl
    fi
    if [[ "$*" =~ "kubeadm" ]]; then
        kubeadm completion bash >/etc/bash_completion.d/kubeadm
    fi
}

clone_dj_kubelet_repos() {
    mkdir -p /var/lib/dj-kubelet
    cd /var/lib/dj-kubelet
    curl -s https://api.github.com/orgs/dj-kubelet/repos |
        jq -r '.[].clone_url' |
        xargs -n1 git clone --recursive
}

main "$@"
