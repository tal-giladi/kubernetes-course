#!/usr/bin/env bash
# Mint a self-signed certificate for shop.localtest.me and load it into the namespace.
# Certificates are not committed - regenerate whenever you need one.
set -e
DIR="$(mktemp -d)"
# The leading "//" is a Git Bash workaround: it rewrites a lone "/CN=..." into a Windows
# path ("C:/Program Files/Git/CN=..."), and collapses "//CN=..." back to "/CN=...".
# Do NOT reach for MSYS_NO_PATHCONV=1 here - that would also stop -keyout/-out from being
# translated, and the Windows openssl cannot open /tmp/... paths.
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout "$DIR/tls.key" -out "$DIR/tls.crt" \
  -subj "//CN=shop.localtest.me" \
  -addext "subjectAltName=DNS:shop.localtest.me"

kubectl create namespace lesson-10 --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lesson-10 create secret tls shop-tls \
  --cert="$DIR/tls.crt" --key="$DIR/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

rm -rf "$DIR"
echo "secret lesson-10/shop-tls created"
