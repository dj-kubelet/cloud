#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
snap install go --classic

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    gnupg2 \
    golang-cfssl \
    certbot \
    curl \
    git \
    jq

install_docker() {
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable" >/etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-cache policy docker-ce
    apt-get install -y docker-ce
    systemctl status docker
    #usermod -aG docker "$USER"
}
install_docker

install_k8s() {
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list
    apt-get update -y
    apt-get install -y kubectl
    apt-mark hold kubectl
    kubectl completion bash >/etc/bash_completion.d/kubectl
}
install_k8s

install_kind() {
    local version="$1"
    curl -sLo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v${version}/kind-$(uname)-amd64"
    chmod +x /usr/local/bin/kind
    kind completion bash >/etc/bash_completion.d/kind
}
install_kind "0.8.1"

clone_dj_kubelet_repos() {
    mkdir -p /var/lib/dj-kubelet
    cd /var/lib/dj-kubelet
    curl -s https://api.github.com/orgs/dj-kubelet/repos |
        jq -r '.[].clone_url' |
        xargs -n1 git clone --recursive
}
clone_dj_kubelet_repos
