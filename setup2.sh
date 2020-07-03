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
    install_runc
    install_containerd
    install_crictl
    install_k8s kubectl kubelet kubeadm
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

install_runc() {
    # https://github.com/opencontainers/runc/releases
    RUNC_VERSION="1.0.0-rc10"
    RUNC_SHA256SUM="a01afd5ff47d5a2a96bea3a871fb445b432f90c249a8a5d5239b05fe0d5bee4a"

    curl -s -L -o /usr/local/bin/runc "https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.amd64"
    echo "$RUNC_SHA256SUM /usr/local/bin/runc" | sha256sum -c
    chmod 755 /usr/local/bin/runc
}

# Containerd
install_containerd() {
    version="1.3.4"
    curl -sLo containerd.tar.gz https://github.com/containerd/containerd/releases/download/v$version/containerd-$version.linux-amd64.tar.gz
    tar -C /usr/local/ -xf containerd.tar.gz
    rm -f containerd.tar

    curl -sLo containerd.zip https://github.com/containerd/containerd/archive/v$version.zip
    unzip containerd.zip

    cp containerd-$version/containerd.service /usr/lib/systemd/system/
    rm -rf containerd*

    mkdir -p /etc/containerd/
    containerd config default >/etc/containerd/config.toml

    cat >/etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
    modprobe overlay
    modprobe br_netfilter

    systemctl daemon-reload
    systemctl enable containerd --now
}

install_crictl() {
    VERSION="v1.18.0"
    curl -sLO https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
    sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
    rm -f crictl-$VERSION-linux-amd64.tar.gz
    cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
EOF
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
