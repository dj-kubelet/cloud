#!/bin/bash
set -euo pipefail

dj_kubelet_repo_root="/var/lib/dj-kubelet"
console_base_url_hostname="console.dj-kubelet.com"
apiserver_hostname="k8s.dj-kubelet.com"
certbot_flags="--register-unsafely-without-email --no-eff-email"

main() {
    # Spin up Kubernetes with Kind
    kind create cluster --name dj-kubelet --config "$dj_kubelet_repo_root/cloud/kind-config.yaml" || true

    # Prep dj-controller CRDs and templates
    kubectl create namespace dj-controller || true
    kubectl apply -n dj-controller -f "$dj_kubelet_repo_root/dj-controller/k8s/"

    cd "$dj_kubelet_repo_root/console"
    create_prod_overlay
    create_server_cert_selfsigned
    #create_server_cert_letsencrypt

    kubectl create namespace console
    # TODO check for client id and secret here
    # Create CLIENT_ID and CLIENT_SECRET in envfile before applying
    #kubectl apply -k ./prod
    #kubectl -n console get pods

    # Forward apiserver
    # socat TCP-LISTEN:6443,fork,bind=10.0.0.x TCP:127.0.0.1:6443 &
}

rand_32() {
    head -c100 /dev/urandom | base64 | head -c32
}

create_server_cert_letsencrypt() {
    # TODO Error if DNS record is not pointing to ext ip
    certbot certonly --standalone $certbot_flags -d "$console_base_url_hostname"
    local cert_dir="/etc/letsencrypt/live/$console_base_url_hostname/"
    ls -l "$cert_dir"
    ln -s "$cert_dir/fullchain.pem" prod/server.pem
    ln -s "$cert_dir/privkey.pem" prod/server-key.pem

}

create_server_cert_selfsigned() {
    cfssl selfsign localhost <(cfssl print-defaults csr) | cfssljson -bare prod/server
}

create_prod_overlay() {
    local overlay_dir="$dj_kubelet_repo_root/console/prod"
    mkdir -p "$overlay_dir"

    cat >"$overlay_dir/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../base

namespace: console

secretGenerator:
- name: console
  env: envfile
  behavior: merge
  type: Opaque
- name: server-tls
  type: "kubernetes.io/tls"
  files:
    - tls.crt=server.pem
    - tls.key=server-key.pem

patchesStrategicMerge:
- deployment-patch.yaml
EOF

    cat >"$overlay_dir/deployment-patch.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: console
spec:
  template:
    spec:
      containers:
        - name: console
          args:
            - --port=:8443
            - --base-url=https://${console_base_url_hostname}:30443
            - --apiserver-endpoint=https://${apiserver_hostname}:6443
            - --cert-file=/etc/tls/tls.crt
            - --key-file=/etc/tls/tls.key
EOF

    # TODO only write these if missing
    cat >>"$overlay_dir/envfile" <<EOF
COOKIE_STORE_AUTH_KEY=$(rand_32)
COOKIE_STORE_ENCRYPTION_KEY=$(rand_32)
EOF
}

main
