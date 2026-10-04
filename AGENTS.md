# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, Gemini CLI, Cursor, etc.) when working with code in this repository.

## Overview

Local Minikube lab (single or multi-cluster): one zsh script for cluster lifecycle, helmfile for Helm services, plain manifests. No build system, no test suite, no linter config. Static checks: `zsh -n minikube.sh`, `shellcheck` for bash/sh scripts, `helmfile -l name=<release> template` for releases. Real testing means running against a Minikube cluster.

## Main entrypoint: `minikube.sh`

zsh script (`set -euo pipefail`), configured only via env vars: `CLUSTERS`, `K8S_VERSION`, `CNI`, `SERVICE_CIDR`, `METRICS_SERVER`, `METRICS_VERSION`, `REGISTRY`, `INSECURE_REGISTRIES`.

```bash
./minikube.sh start|stop|status|delete
./minikube.sh metrics install|uninstall
./minikube.sh registry install|uninstall|port
CLUSTERS="cluster-1,cluster-2" CNI=cilium METRICS_SERVER=true ./minikube.sh start
```

Key behavior:
- Every command loops over `CLUSTERS` (comma-split with zsh `${(@s:,:)CLUSTERS}`); the minikube profile name equals the cluster name.
- `cluster-1..3` get fixed service CIDRs `172.16.{1,2,3}.0/24` (`SERVICE_CIDR_MAP`) so multi-cluster setups don't overlap; `SERVICE_CIDR` overrides for all clusters.
- `build_start_args` returns minikube args as an array in `$reply` (no `eval`); `CLUSTER_LIST` is the parsed `CLUSTERS`.
- After each start, `sync_cluster_kubeconfig` writes a standalone, flattened kubeconfig to `~/.kube/clusters/<cluster>` (mode 600, atomic via temp file + `mv`). `start` therefore requires `kubectl`.
- Metrics-server is installed only on the **first** cluster in `CLUSTERS` (switches `minikube profile` first), with `--kubelet-insecure-tls`.
- `INSECURE_REGISTRIES` is baked in at node creation: changing it requires `delete` + `start`.
- Missing `minikube`/`helm` goes through `ensure_installed <tool> <docs-url>`, which calls `print_<tool>_install_hints` / `install_<tool>_auto` and offers an interactive install (`read -q`, zsh-only).
- `delete` asks for interactive confirmation.

When bumping the default Kubernetes version, change `DEFAULT_K8S_VERSION`, the header comment, and the README env var table/examples (`show_usage` interpolates the defaults).

## Repository layout

```
minikube.sh      cluster lifecycle (the only entrypoint script)
helmfile.yaml    every Helm release: repo, chart, pinned version, namespace, labels (group: platform|dns|monitoring|data|demo)
charts/<name>/   values.yaml (+ values-<variant>.yaml) for the release of the same name
manifests/       plain YAML for `kubectl apply -f` (argocd, istio, rabbitmq CRs, scale test)
docker/<name>/   local images; run.sh builds from its own dir and runs on Docker network `netlite`
scripts/         vault-init.sh (init + unseal 3-node raft Vault; keys -> gitignored .secrets/)
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

## Notes

- `README.md` is the user-facing doc (minikube.sh usage, registry workflows, services table, layout); keep it and this file in sync when changing behavior or layout.
- `tls/`, `credentials.json`, `.env`, `.secrets/` are gitignored.
