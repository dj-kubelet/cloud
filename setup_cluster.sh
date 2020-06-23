#!/bin/bash
set -euo pipefail

dj_kubelet_repo_root="/var/lib/dj-kubelet"
console_base_url_hostname="console.dj-kubelet.com"
apiserver_hostname="k8s.dj-kubelet.com"
certbot_flags="--register-unsafely-without-email"

CLIENT_ID="${CLIENT_ID:-}"
echo "CLIENT_ID: $CLIENT_ID"
if [ "$CLIENT_ID" == "" ]; then
    echo "CLIENT_ID is empty"
fi
CLIENT_SECRET="${CLIENT_SECRET:-}"
echo "CLIENT_SECRET: $CLIENT_SECRET"
if [ "$CLIENT_SECRET" == "" ]; then
    echo "CLIENT_SECRET is empty"
fi

main() {
    # Spin up Kubernetes with Kind
    kind create cluster --name dj-kubelet --config "$dj_kubelet_repo_root/cloud/kind-config.yaml" || true

    # TODO Error if DNS record is not pointing to ext ip
    #metadata_token=$(curl -X PUT \
    #    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    #    "http://169.254.169.254/latest/api/token")
    #curl -H "X-aws-ec2-metadata-token: $metadata_token" \
    #    "http://169.254.169.254/latest/meta-data/public-ipv4"
    #dig +short console.dj-kubelet.com
    #dig +short k8s.dj-kubelet.com

    # Add template dj-controller and CRDs
    kubectl create namespace dj-controller || true
    kubectl apply -k "$dj_kubelet_repo_root/dj-controller/prod"

    # Deploy dj-scheduler
    kubectl create namespace dj-scheduler || true
    kubectl apply -k "$dj_kubelet_repo_root/dj-scheduler/prod"

    # Deploy console
    create_console_prod_overlay "$dj_kubelet_repo_root/console/prod"
    kubectl create namespace console || true
    kubectl apply -k "$dj_kubelet_repo_root/console/prod"
    kubectl -n console get pods
    # Forward apiserver
    # socat TCP-LISTEN:6443,fork,bind=10.0.0.x TCP:127.0.0.1:6443 &

    # Deploy oauth-refresher
    cd "$dj_kubelet_repo_root/oauth-refresher"
    create_oauth_refresher_prod_overlay "$dj_kubelet_repo_root/oauth-refresher/prod"
    kubectl create namespace oauth-refresher || true
    kubectl apply -k "$dj_kubelet_repo_root/oauth-refresher/prod"
}

rand_32() {
    head -c100 /dev/urandom | base64 | head -c32
}

create_server_cert_letsencrypt() {
    certbot certonly --standalone --keep-until-expiring --no-eff-email --agree-tos $certbot_flags -d "$console_base_url_hostname"
    certbot certificates
    local cert_dir="/etc/letsencrypt/live/$console_base_url_hostname/"
    ls -l "$cert_dir"
    ln -sf "$cert_dir/fullchain.pem" prod/server.pem
    ln -sf "$cert_dir/privkey.pem" prod/server-key.pem

}

create_server_cert_selfsigned() {
    cfssl selfsign localhost <(cfssl print-defaults csr) | cfssljson -bare prod/server
}

create_console_prod_overlay() {
    local overlay_dir="$1"
    mkdir -p "$overlay_dir"

    create_server_cert_selfsigned
    #create_server_cert_letsencrypt

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

    if ! grep "^COOKIE_STORE_AUTH_KEY=" "$overlay_dir/envfile" >/dev/null; then
        echo "COOKIE_STORE_AUTH_KEY=$(rand_32)" >>"$overlay_dir/envfile"
    fi
    if ! grep "^COOKIE_STORE_ENCRYPTION_KEY=" "$overlay_dir/envfile" >/dev/null; then
        echo "COOKIE_STORE_ENCRYPTION_KEY=$(rand_32)" >>"$overlay_dir/envfile"
    fi
    # Create CLIENT_ID and CLIENT_SECRET in envfile before applying
    if ! grep "^CLIENT_ID=" "$overlay_dir/envfile" >/dev/null; then
        echo "CLIENT_ID missing"
        if [ "$CLIENT_ID" != "" ]; then
            echo "CLIENT_ID=$CLIENT_ID" >>"$overlay_dir/envfile"
        fi
    fi
    if ! grep "^CLIENT_SECRET=" "$overlay_dir/envfile" >/dev/null; then
        echo "CLIENT_SECRET missing"
        if [ "$CLIENT_SECRET" != "" ]; then
            echo "CLIENT_SECRET=$CLIENT_SECRET" >>"$overlay_dir/envfile"
        fi
    fi
}

create_oauth_refresher_prod_overlay() {
    local overlay_dir="$1"
    mkdir -p "$overlay_dir"
    if ! grep "^AUTH_URL=" "$overlay_dir/envfile" >/dev/null; then
        cat >>"$overlay_dir/envfile" <<EOF
AUTH_URL=https://accounts.spotify.com/authorize
EOF
    fi
    if ! grep "^TOKEN_URL=" "$overlay_dir/envfile" >/dev/null; then
        cat >>"$overlay_dir/envfile" <<EOF
TOKEN_URL=https://accounts.spotify.com/api/token
EOF
    fi
    # Create CLIENT_ID and CLIENT_SECRET in envfile before applying
    if ! grep "^CLIENT_ID=" "$overlay_dir/envfile" >/dev/null; then
        echo "CLIENT_ID missing"
        if [ "$CLIENT_ID" != "" ]; then
            echo "CLIENT_ID=$CLIENT_ID" >>"$overlay_dir/envfile"
        fi
    fi
    if ! grep "^CLIENT_SECRET=" "$overlay_dir/envfile" >/dev/null; then
        echo "CLIENT_SECRET missing"
        if [ "$CLIENT_SECRET" != "" ]; then
            echo "CLIENT_SECRET=$CLIENT_SECRET" >>"$overlay_dir/envfile"
        fi
    fi
}

main
