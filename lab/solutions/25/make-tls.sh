#!/usr/bin/env bash
# TLS material for shop25.localtest.me. Certificates are never committed.
set -e
DIR="$(mktemp -d)"
# "//CN=" is the Git Bash escape - see lab/solutions/10/make-tls.sh.
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout "$DIR/tls.key" -out "$DIR/tls.crt" \
  -subj "//CN=shop25.localtest.me" \
  -addext "subjectAltName=DNS:shop25.localtest.me"

kubectl create namespace lesson-25 --dry-run=client -o yaml | kubectl apply -f -
kubectl -n lesson-25 create secret tls shop25-tls \
  --cert="$DIR/tls.crt" --key="$DIR/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

rm -rf "$DIR"
echo "secret lesson-25/shop25-tls created"
