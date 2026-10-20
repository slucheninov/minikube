#!/usr/bin/env bash
# Test CA + etcd server/client certificate for the coredns etcd rehearsal.
# SANs mirror the prod Secret etcd-main-tls (one cert with serverAuth + clientAuth, no IP SANs).
# Creates Secret etcd-main-tls in $NAMESPACE and Secret etcd-client-tls in each of $CLIENT_NAMESPACES.
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:?Set KUBE_CONTEXT to the intended lab cluster}"
NAMESPACE="${NAMESPACE:-coredns}"
CLIENT_NAMESPACES="${CLIENT_NAMESPACES-etcd-load corenet}"
TLS_DIR="${TLS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/.secrets/etcd-rehearsal}"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
for tool in kubectl openssl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
k() { kubectl --context="$KUBE_CONTEXT" "$@"; }

mkdir -p "$TLS_DIR"
chmod 700 "$TLS_DIR"
cd "$TLS_DIR"
umask 077

if [[ ! -f ca.crt ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=Etcd CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign,digitalSignature" \
    -keyout ca.key -out ca.crt 2>/dev/null
fi

if [[ ! -f tls.crt ]]; then
  sans="DNS:*.etcd-headless.${NAMESPACE}.svc.cluster.local,DNS:etcd.${NAMESPACE}.svc.cluster.local"
  sans+=",DNS:*.etcd.${NAMESPACE}.svc.cluster.local,DNS:localhost"
  openssl req -newkey rsa:2048 -nodes -subj "/CN=etcd-cluster" -keyout tls.key -out tls.csr 2>/dev/null
  openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out tls.crt \
    -extfile <(printf 'basicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=%s\n' "$sans") 2>/dev/null
  rm -f tls.csr
fi

for ns in "$NAMESPACE" $CLIENT_NAMESPACES; do
  k create namespace "$ns" --dry-run=client -o yaml | k apply -f - >/dev/null
done
# Server secret (same keys as prod: tls.crt, tls.key, ca.crt).
k -n "$NAMESPACE" create secret generic etcd-main-tls --type=kubernetes.io/tls \
  --from-file=tls.crt --from-file=tls.key --from-file=ca.crt --dry-run=client -o yaml | k apply -f -
# Client secret for the load generator and corenet (the prod cert is also a client cert).
for ns in $CLIENT_NAMESPACES; do
  k -n "$ns" create secret generic etcd-client-tls \
    --from-file=tls.crt --from-file=tls.key --from-file=ca.crt --dry-run=client -o yaml | k apply -f -
done
printf 'Certificates in %s\n' "$TLS_DIR"
