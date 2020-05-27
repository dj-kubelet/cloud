#!/bin/bash
set -euo pipefail

dj_kubelet_repo_root="/var/lib/dj-kubelet"
console_base_url_hostname="console.dj-kubelet.com"
apiserver_hostname="k8s.dj-kubelet.com"

main() {
    # Spin up Kubernetes with Kind
    kind create cluster --name dj-kubelet --config "$dj_kubelet_repo_root/cloud/kind-config.yaml"

    # Prep dj-controller CRDs and templates
    kubectl create namespace dj-controller
    kubectl apply -n dj-controller -f "$dj_kubelet_repo_root/dj-controller/k8s/"

    cd "$dj_kubelet_repo_root/console"
    create_prod_overlay
    kubectl create namespace console
    # Create CLIENT_ID and CLIENT_SECRET in envfile before applying
    #kubectl apply -k ./prod
    #kubectl -n console get pods
}

rand_32() {
    head -c100 /dev/urandom | base64 | head -c32
}

create_prod_overlay() {
    mkdir -p ./prod

    # Create server certs
    cfssl selfsign localhost <(cfssl print-defaults csr) | cfssljson -bare prod/server

    cat >./prod/kustomization.yaml <<EOF
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

    cat >./prod/deployment-patch.yaml <<EOF
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

    cat >>./prod/envfile <<EOF
COOKIE_STORE_AUTH_KEY=$(rand_32)
COOKIE_STORE_ENCRYPTION_KEY=$(rand_32)
EOF
}

main
