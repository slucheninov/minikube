# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Gemini CLI, Cursor, etc.) in this repository.

## Overview

Local Minikube lab (single or multi-cluster): one zsh script for cluster lifecycle. No versions are hardcoded in the repo: they are pinned in `~/.minikube.env` by `./minikube.sh upgrade`. Helm charts, services and manifests are not kept here; install them ad hoc. MIT licensed. Checks: `zsh -n minikube.sh` and `zsh .github/ci/smoke.zsh` (offline smoke test with fake minikube/kubectl/helm; extend it when changing behavior). Integration testing requires a Minikube cluster.

## CI and releases

- `.github/workflows/ci.yml`: syntax, `SCRIPT_VERSION` format, smoke test, actionlint; on PRs fails if `minikube.sh` changed without a higher `SCRIPT_VERSION`. Also `workflow_call`ed by release.
- `.github/workflows/security.yml`: gitleaks over full history via a digest-pinned image (accepted findings in `.gitleaksignore`), OpenSSF Scorecard (SARIF to code scanning; needs a public repo).
- `.github/workflows/release.yml`: on every push to `main` (manual runs only on `main`), after CI, creates release `v<SCRIPT_VERSION>` (assets `minikube.sh`, `minikube.sh.sha256`) if it does not exist. Releasing = bumping `SCRIPT_VERSION`.
- Workflow rules: pin actions to full SHAs with a version comment, least-privilege `permissions`, `persist-credentials: false`, pass `${{ }}` via `env` (never inline in `run`). Dependabot updates the pins.
- `.coderabbit.yaml`: CodeRabbit PR reviews (ru-RU) with path instructions for `minikube.sh` and workflows.

## `minikube.sh`

zsh (`set -euo pipefail`). Settings (`CONFIG_KEYS`): `CLUSTERS`, `K8S_VERSION`, `CNI`, `SERVICE_CIDR`, `METRICS_SERVER`, `METRICS_VERSION`, `REGISTRY`, `INSECURE_REGISTRIES`, `UPDATE_CHECK`. It is the user's personal wrapper: defaults are `CLUSTERS=cluster-1`, `METRICS_SERVER=true`, `REGISTRY=true`, `UPDATE_CHECK=true`; `K8S_VERSION`/`METRICS_VERSION` empty = minikube default / latest chart.

- `load_config` parses `~/.minikube.env` as `KEY=VALUE` data (never `source`): known keys only, value charset `[A-Za-z0-9._,:/-]`, optional quotes; env vars take precedence. `write_config` updates keys atomically, preserving other lines.
- Do not add version literals to the script or docs as defaults. The only version in the script is its own `SCRIPT_VERSION` (semver): bump it on every change to `minikube.sh`.
- The script must stay standalone (no repo-relative paths): `self install [dir]` copies `SCRIPT_PATH` to `~/bin/minikube.sh` (temp + `mv`, 755, `.bak`). Copies are identified by reading the `readonly SCRIPT_VERSION=` line as text (`script_version_of`, never executed); foreign files are never overwritten/removed, downgrades need TTY confirmation. `check_installed_copy` (part of the update check) highlights an outdated `~/bin` copy.

```bash
./minikube.sh start|stop|status|delete|updates
./minikube.sh upgrade [plan|k8s|metrics|all|minikube]
./minikube.sh self install|uninstall [dir]
./minikube.sh version
./minikube.sh metrics install|uninstall
./minikube.sh registry install|uninstall|port
```

- Commands loop over `CLUSTER_LIST` (`CLUSTERS` split with `${(@s:,:)CLUSTERS}`); profile name = cluster name = kube context.
- `cluster-1..3` get fixed service CIDRs `172.16.{1,2,3}.0/24` (`SERVICE_CIDR_MAP`); `SERVICE_CIDR` overrides for all.
- `build_start_args` returns minikube args in `$reply` (no `eval`).
- After each start, `sync_cluster_kubeconfig` writes `~/.kube/clusters/<cluster>` (flattened, mode 600, temp file + `mv`); `start` requires `kubectl`.
- metrics-server is installed only on the **first** cluster, with explicit `--kube-context` and `--kubelet-insecure-tls`.
- `INSECURE_REGISTRIES` is baked in at node creation (needs `delete` + `start` to change).
- Missing `minikube`/`helm` go through `ensure_installed`: Homebrew prompt only with a TTY + brew, never downloaded installers.
- Names, duplicates, booleans and arguments are validated before tool calls; names cannot contain path separators. stop/delete/status attempt every profile and return nonzero on any failure. `delete` asks for confirmation.
- Versions (curl + jq): installed Minikube vs GitHub latest stable; `K8S_VERSION` vs newest stable from `minikube config defaults kubernetes-version -o json` (offline, what the installed Minikube supports); `METRICS_VERSION` vs `helm search repo`. `stable.txt` is only reported (needs newer Minikube).
  - `auto_check_updates` runs after `start`/`status` in quiet mode (`UPDATES_QUIET`, 3/5 s curl timeouts, Helm cache only, stderr suppressed): prints `[UPDATE]` lines and an unpinned warning, never changes the exit code; skipped without curl/jq or with `UPDATE_CHECK=false`.
  - `updates` prints the full report; exit 1 = incomplete check.
  - `upgrade`/`upgrade plan` only prints planned changes. `upgrade k8s|metrics|all` writes the selected keys (`resolve_targets` -> `print_plan` -> confirm in TTY -> `~/.minikube.env.bak` -> `write_config`). `upgrade minikube` runs `brew upgrade minikube` (TTY + brew-managed only). Never lowers a pin, never touches clusters, never writes the file implicitly.

## Notes

- `README.md` is the user-facing doc; keep it and this file in sync when changing behavior or layout.
- `tls/`, `credentials.json`, `.env`, `.secrets/`, `.remember/` are gitignored.
