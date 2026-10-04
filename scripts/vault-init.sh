#!/usr/bin/env bash
# Initialize/unseal the lab's 3-node Raft Vault. Never run with shell tracing.
set +x
set -euo pipefail
umask 077

NAMESPACE="${NAMESPACE:-vault}"
KUBE_CONTEXT="${KUBE_CONTEXT:?Set KUBE_CONTEXT to the intended lab cluster}"
KEYS_FILE="${KEYS_FILE:-$(cd "$(dirname "$0")/.." && pwd)/.secrets/vault-cluster-keys.json}"
mode="${1:-init}"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# -le 1 && ( "$mode" == init || "$mode" == unseal ) ]] || fail "Usage: $0 [init|unseal]"
for tool in kubectl jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

vault_exec() {
  local pod="$1"
  shift
  kubectl --context="$KUBE_CONTEXT" --namespace="$NAMESPACE" exec -i "$pod" -- vault "$@"
}

if [[ "$mode" == init ]]; then
  [[ ! -e "$KEYS_FILE" && ! -L "$KEYS_FILE" ]] || fail "Keys path already exists: $KEYS_FILE. Use 'unseal' with valid saved keys."
  mkdir -p -m 700 "$(dirname "$KEYS_FILE")"
  # noclobber reserves the destination before initialization, including against
  # concurrent invocations. Existing paths (including symlinks) are rejected above.
  # Keep partial output on errors:
  # initialization may have succeeded server-side even if the connection failed.
  if ! (set -o noclobber; vault_exec vault-0 operator init \
      -key-shares=1 -key-threshold=1 -format=json > "$KEYS_FILE"); then
    fail "Initialization failed or keys file already exists: $KEYS_FILE. Preserve it; inspect Vault state before retrying. Use 'unseal' with valid saved keys."
  fi
fi

[[ -f "$KEYS_FILE" && ! -L "$KEYS_FILE" ]] || fail "Keys must be a regular, non-symlink file: $KEYS_FILE"
chmod 600 "$KEYS_FILE"
jq -e '
  (.unseal_keys_b64 | type == "array" and length == 1) and
  (.unseal_keys_b64[0] | type == "string" and length > 0) and
  (.root_token | type == "string" and length > 0)
' "$KEYS_FILE" >/dev/null || fail "Invalid lab keys file; preserve it for recovery: $KEYS_FILE"

unseal() {
  # The payload travels through stdin, never through process arguments or logs.
  jq -c '{key: .unseal_keys_b64[0]}' "$KEYS_FILE" |
    vault_exec "$1" write sys/unseal - >/dev/null
}

unseal vault-0
for pod in vault-1 vault-2; do
  vault_exec "$pod" operator raft join http://vault-0.vault-internal:8200
  unseal "$pod"
done
printf 'Vault unsealed. Keys and root token are stored in %s (mode 600).\n' "$KEYS_FILE"
