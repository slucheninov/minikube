# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, Gemini CLI, Cursor, etc.) when working with code in this repository.

## Overview

Local Minikube lab (single or multi-cluster): one zsh script for cluster lifecycle, helmfile for Helm services, plain manifests. No build system or linter config. Offline script regression tests: `python3 -m unittest discover -s tests -v` (requires zsh, bash, jq; substitutes all cluster commands). Static checks: `zsh -n minikube.sh`, `shellcheck` for bash/sh scripts, `helmfile -l name=<release> template` for releases. Integration testing requires a Minikube cluster.

## Main entrypoint: `minikube.sh`

zsh script (`set -euo pipefail`), configured only via env vars: `CLUSTERS`, `K8S_VERSION`, `CNI`, `SERVICE_CIDR`, `METRICS_SERVER`, `METRICS_VERSION`, `REGISTRY`, `INSECURE_REGISTRIES`.

```bash
./minikube.sh start|stop|status|delete|updates
./minikube.sh metrics install|uninstall
./minikube.sh registry install|uninstall|port
CLUSTERS="cluster-1,cluster-2" CNI=cilium METRICS_SERVER=true ./minikube.sh start
```

Key behavior:
- Cluster lifecycle and registry commands loop over `CLUSTERS` (comma-split with zsh `${(@s:,:)CLUSTERS}`); the minikube profile name equals the cluster name.
- `cluster-1..3` get fixed service CIDRs `172.16.{1,2,3}.0/24` (`SERVICE_CIDR_MAP`) so multi-cluster setups don't overlap; `SERVICE_CIDR` overrides for all clusters.
- `build_start_args` returns minikube args as an array in `$reply` (no `eval`); `CLUSTER_LIST` is the parsed `CLUSTERS`.
- After each start, `sync_cluster_kubeconfig` writes a standalone, flattened kubeconfig to `~/.kube/clusters/<cluster>` (mode 600, atomic via temp file + `mv`). `start` therefore requires `kubectl`.
- Metrics-server is installed only on the **first** cluster in `CLUSTERS`, with explicit Helm `--kube-context` and `--kubelet-insecure-tls`; it does not switch the active profile/context.
- `INSECURE_REGISTRIES` is baked in at node creation: changing it requires `delete` + `start`.
- Missing `minikube`/`helm` goes through `ensure_installed <tool> <docs-url>`. Interactive Homebrew installation is offered only when a terminal and brew are available; otherwise the command fails with the documentation URL. No downloaded installer scripts are executed.
- Profile names, duplicate/empty entries, boolean flags and command arguments are validated before tool calls. Profile names cannot contain path separators. Stop/delete/status attempt every profile and return nonzero if any operation fails.
- `delete` asks for interactive confirmation.
- `updates` is an explicit read-only network check requiring curl + jq. It compares installed Minikube against GitHub stable releases and configured `K8S_VERSION` against Kubernetes stable markers (same-branch patch and latest stable). It never contacts clusters or installs tools; ordinary lifecycle commands do not trigger it. Exit 1 means an incomplete/failed check, not an available update.

When bumping the default Kubernetes version, change `DEFAULT_K8S_VERSION`, the header comment, and the README env var table/examples (`show_usage` interpolates the defaults).

## Repository layout

```
minikube.sh      cluster lifecycle (the only entrypoint script)
helmfile.yaml    every Helm release: repo, chart, pinned version, namespace, labels (group: platform|dns|monitoring|data|demo)
charts/<name>/   values.yaml (+ values-<variant>.yaml) for the release of the same name
manifests/       plain YAML for `kubectl apply -f` (argocd, istio, rabbitmq CRs, scale test)
docker/<name>/   local images; run.sh builds from its own dir and runs on Docker network `netlite`
scripts/         vault-init.sh (init|unseal 3-node raft Vault; explicit KUBE_CONTEXT; keys -> gitignored .secrets/)
tests/           offline script regression tests with fake minikube/helm/kubectl
examples/        standalone sidecar demos, each with its own COMMAND.md/README.md
```

Helm releases (needs `helmfile` + `helm-diff` plugin):

```bash
helmfile list
helmfile -l name=<release> apply | destroy   # always use a selector; bare apply installs everything
helmfile -l group=monitoring apply
helmfile -l name=<release> template          # render locally to validate (downloads charts)
COREDNS_VALUES=values-etcd.yaml helmfile -l name=coredns apply   # values variant via env var
```

- Adding a service: a `releases:` entry in `helmfile.yaml` (+ repo if new) and `charts/<name>/values.yaml`; update the README table.
- Values variants are chosen with `{{ env "X_VALUES" | default "values.yaml" }}` in the release (`COREDNS_VALUES`, `EXTERNAL_DNS_VALUES`).
- metrics-server is intentionally not in helmfile: `./minikube.sh metrics install` owns it.
- `helmDefaults` sets `wait` and `createNamespace` for all releases.
- CoreDNS `values-redis.yaml` points at the `keydb` release; etcd used by `values-etcd.yaml` (CoreDNS, external-dns) is not deployed by this repo.
- Manifests in `manifests/` depend on their releases (rabbitmq CRs need `rabbitmq-operator`, argocd service needs `argocd`).
- Fixed, basic test credentials in values/manifests are intentional for this local Minikube lab and are explicitly accepted by the user. Do not replace them with generated credentials or require manual Secret provisioning. RabbitMQ Secrets are included in `manifests/rabbitmq/users.yaml`; the exporter references the monitoring Secret to avoid password duplication.
- Grafana/Argo CD retain fixed test admin credentials. Argo CD ingress is disabled and server TLS enabled by default. Docker demo ports and Envoy's demo admin listener bind to loopback.
- Vault init refuses to overwrite any keys file and preserves partial output on failure. `unseal` reuses valid saved keys; keys travel over stdin, and the root token is never printed. `KEYS_FILE` can isolate credentials for different clusters.

## Notes

- `README.md` is the user-facing doc (minikube.sh usage, registry workflows, services table, layout); keep it and this file in sync when changing behavior or layout.
- `tls/`, `credentials.json`, `.env`, `.secrets/` are gitignored.
