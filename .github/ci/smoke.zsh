#!/usr/bin/env zsh
# Offline smoke test for minikube.sh: fake minikube/kubectl/helm, isolated HOME.
set -euo pipefail

repo="${0:A:h:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin" "${tmp}/home"
log="${tmp}/calls.log"

for tool in kubectl helm; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "${tool}" "${log}" > "${tmp}/bin/${tool}"
done
cat > "${tmp}/bin/minikube" <<FAKE
#!/bin/sh
echo "minikube \$*" >> "${log}"
case "\$1" in
  start) echo "kubeconfig \$KUBECONFIG" >> "${log}" ;;
  version) echo v1.0.0 ;;
  ip) echo 192.168.49.2 ;;
  config) echo '["v1.37.0","v1.36.4"]' ;;
  profile) echo '{"valid":[{"Name":"cluster-1","Config":{"KubernetesConfig":{"KubernetesVersion":"v1.35.9"}}}],"invalid":[]}' ;;
esac
exit 0
FAKE
chmod +x "${tmp}/bin/"*

run() { env -i PATH="${tmp}/bin:/usr/bin:/bin" HOME="${tmp}/home" UPDATE_CHECK=false "$@"; }
mk() { run zsh "${repo}/minikube.sh" "$@"; }
fail() { print -r -- "FAIL: $*" >&2; exit 1; }
expect_fail() { if mk "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }

mk version | grep -q '^minikube.sh [0-9]*\.[0-9]*\.[0-9]*$' || fail "version"
mk help >/dev/null || fail "help"

# start: defaults = cluster-1 + registry + metrics-server, no pinned versions.
: > "${log}"
mk start >/dev/null || fail "start"
grep -qx 'minikube start -p cluster-1 --service-cluster-ip-range=172.16.1.0/24' "${log}" || fail "start args"
grep -q '^minikube addons enable registry -p cluster-1$' "${log}" || fail "registry addon"
grep -q '^helm upgrade --install metrics-server .*--kube-context cluster-1' "${log}" || fail "metrics-server"
kc="${tmp}/home/.kube/clusters/cluster-1"
[[ "$(stat -c %a "${kc}" 2>/dev/null || stat -f %Lp "${kc}")" == 600 ]] || fail "kubeconfig mode"

# An exported KUBECONFIG must not redirect minikube away from ~/.kube/config.
: > "${log}"
run KUBECONFIG=/elsewhere/cluster-1 zsh "${repo}/minikube.sh" start >/dev/null || fail "start with KUBECONFIG"
grep -qx "kubeconfig ${tmp}/home/.kube/config" "${log}" || fail "default kubeconfig not used"

# Versions come from ~/.minikube.env; env vars override it.
printf 'K8S_VERSION=1.36.4\nMETRICS_VERSION=3.12.0\n' > "${tmp}/home/.minikube.env"
: > "${log}"
run METRICS_VERSION=3.13.0 zsh "${repo}/minikube.sh" start >/dev/null || fail "start pinned"
grep -q -- '--kubernetes-version=1.36.4' "${log}" || fail "K8S_VERSION from config"
grep -q -- '--version 3.13.0' "${log}" || fail "env overrides config"

# start raises a pin that is below the existing cluster's version (no downgrade).
if command -v jq >/dev/null 2>&1; then
  printf '# keep\nK8S_VERSION=1.35.1\n' > "${tmp}/home/.minikube.env"
  : > "${log}"
  mk start >/dev/null || fail "start with stale pin"
  grep -qx 'K8S_VERSION=1.35.9' "${tmp}/home/.minikube.env" || fail "pin not synced to cluster"
  grep -qx '# keep' "${tmp}/home/.minikube.env" || fail "config lines lost"
  grep -q -- '--kubernetes-version=1.35.9' "${log}" || fail "start uses synced pin"
  printf 'K8S_VERSION=1.35.1\n' > "${tmp}/home/.minikube.env"
  run K8S_VERSION=1.35.1 zsh "${repo}/minikube.sh" start >/dev/null 2>&1 || fail "start with env pin"
  grep -qx 'K8S_VERSION=1.35.1' "${tmp}/home/.minikube.env" || fail "env pin must not rewrite config"
fi

# Invalid input is rejected before tool calls.
expect_fail start extra
expect_fail upgrade foo
expect_fail self foo
run CLUSTERS=a,a zsh "${repo}/minikube.sh" status >/dev/null 2>&1 && fail "duplicate clusters"
run CLUSTERS=../x zsh "${repo}/minikube.sh" status >/dev/null 2>&1 && fail "path in cluster name"
printf 'K8S_VERSION=$(id)\n' > "${tmp}/home/.minikube.env"
mk status >/dev/null 2>&1 && fail "unsafe config value"
rm -f "${tmp}/home/.minikube.env"

# self install / uninstall.
mk self install >/dev/null </dev/null || fail "self install"
[[ -x "${tmp}/home/bin/minikube.sh" ]] || fail "installed copy"
cmp -s "${repo}/minikube.sh" "${tmp}/home/bin/minikube.sh" || fail "installed content"
echo 'echo foreign' > "${tmp}/home/bin/minikube.sh"
mk self install >/dev/null 2>&1 </dev/null && fail "overwrote foreign file"
grep -q foreign "${tmp}/home/bin/minikube.sh" || fail "foreign file changed"

print "smoke test passed"
