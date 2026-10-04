#!/usr/bin/env bash
# Initialize and unseal the 3-node raft Vault from `helmfile -l name=vault apply`.
# Keys are written to .secrets/vault-cluster-keys.json (gitignored).
set -euo pipefail

NAMESPACE="${NAMESPACE:-vault}"
KEYS_FILE="$(cd "$(dirname "$0")/.." && pwd)/.secrets/vault-cluster-keys.json"

mkdir -p "$(dirname "${KEYS_FILE}")"
kubectl exec vault-0 -n "${NAMESPACE}" -- \
  vault operator init -key-shares=1 -key-threshold=1 -format=json > "${KEYS_FILE}"
chmod 600 "${KEYS_FILE}"

unseal_key="$(jq -r '.unseal_keys_b64[]' "${KEYS_FILE}")"
kubectl exec vault-0 -n "${NAMESPACE}" -- vault operator unseal "${unseal_key}"
for pod in vault-1 vault-2; do
  kubectl exec -ti "${pod}" -n "${NAMESPACE}" -- vault operator raft join http://vault-0.vault-internal:8200
  kubectl exec -ti "${pod}" -n "${NAMESPACE}" -- vault operator unseal "${unseal_key}"
done

echo "Root token: $(jq -r '.root_token' "${KEYS_FILE}")"
