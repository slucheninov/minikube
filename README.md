# minikube.sh

[![CI](https://github.com/slucheninov/minikube/actions/workflows/ci.yml/badge.svg)](https://github.com/slucheninov/minikube/actions/workflows/ci.yml)
[![Security](https://github.com/slucheninov/minikube/actions/workflows/security.yml/badge.svg)](https://github.com/slucheninov/minikube/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/slucheninov/minikube/badge)](https://scorecard.dev/viewer/?uri=github.com/slucheninov/minikube)
[![Release](https://img.shields.io/github/v/release/slucheninov/minikube?sort=semver)](https://github.com/slucheninov/minikube/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CodeRabbit Reviews](https://img.shields.io/coderabbit/prs/github/slucheninov/minikube?utm_source=oss&utm_medium=github&utm_campaign=slucheninov%2Fminikube&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)](https://coderabbit.ai)

## About

A single-file zsh wrapper over [Minikube](https://minikube.sigs.k8s.io/) for local
Kubernetes labs. One command starts one or several clusters with metrics-server,
an image registry and non-overlapping service CIDRs, exports a standalone
kubeconfig per cluster, and highlights new Minikube, Kubernetes and
metrics-server releases. Versions are never hardcoded: they are pinned in
`~/.minikube.env` by explicit `upgrade` commands. The script installs itself to
`~/bin` and works without this repository. Helm charts, services and manifests
are installed ad hoc; the repo only keeps the cluster lifecycle.

## Install

From the latest release (checksum verified):

```bash
cd "$(mktemp -d)"
curl -fsSLO https://github.com/slucheninov/minikube/releases/latest/download/minikube.sh
curl -fsSLO https://github.com/slucheninov/minikube/releases/latest/download/minikube.sh.sha256
shasum -a 256 -c minikube.sh.sha256
zsh minikube.sh self install
```

The script is standalone (settings live in `~/.minikube.env`), so it can run
outside the repo. From a clone it installs itself the same way:

```bash
./minikube.sh self install          # copies to ~/bin/minikube.sh
./minikube.sh self install ~/.local/bin
minikube.sh version
minikube.sh self uninstall          # ~/.minikube.env is kept
```

`self install` replaces the copy atomically (mode 755, previous copy kept as
`minikube.sh.bak`), shows `old -> new` and asks in a terminal. It refuses to
overwrite a file that is not this script and does not downgrade without
confirmation. It warns if the target directory is not in `PATH`. When you run
the repo copy, `start`/`status`/`updates` highlight an outdated `~/bin` copy.

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/), [kubectl](https://kubernetes.io/docs/tasks/tools/), zsh
- [Helm](https://helm.sh/docs/intro/install/) for metrics-server
- curl + jq for `updates`/`upgrade` and the automatic release check

Missing `minikube`/`helm` can be installed interactively via Homebrew; otherwise
the script prints the installation guide and exits.

## Usage

```bash
./minikube.sh start                   # cluster-1 + metrics-server + registry
./minikube.sh stop | status
./minikube.sh delete                  # asks for confirmation
./minikube.sh updates                 # show available updates
./minikube.sh upgrade                 # plan: show version changes, write nothing
./minikube.sh upgrade k8s|metrics|all # pin newest versions in ~/.minikube.env
./minikube.sh upgrade minikube        # brew upgrade minikube
./minikube.sh metrics install|uninstall
./minikube.sh registry install|uninstall|port
./minikube.sh self install|uninstall [dir]
./minikube.sh version
```

Examples:

```bash
CLUSTERS="cluster-1,cluster-2" CNI=cilium ./minikube.sh start
METRICS_SERVER=false REGISTRY=false ./minikube.sh start   # bare cluster
K8S_VERSION=1.36.4 ./minikube.sh start                    # one-off override
./minikube.sh registry port
INSECURE_REGISTRIES="my-registry.lan:5000" ./minikube.sh start
```

### Settings

Each setting can be an env var or a `KEY=VALUE` line in `~/.minikube.env`; the
env var wins. The file is plain data (never sourced); unknown keys are ignored
with a warning, invalid values abort.

```bash
# ~/.minikube.env
K8S_VERSION=1.37.0
METRICS_VERSION=3.14.0
CNI=cilium
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTERS` | `cluster-1` | Comma-separated cluster (profile) names |
| `K8S_VERSION` | minikube's default | Kubernetes version; pinned by `upgrade` |
| `CNI` | (empty) | `cilium`, `calico`, or empty for default |
| `SERVICE_CIDR` | (auto) | Service IP range for all clusters; otherwise `cluster-1..3` get `172.16.{1,2,3}.0/24` |
| `METRICS_SERVER` | `true` | Install metrics-server on start |
| `METRICS_VERSION` | latest chart | metrics-server Helm chart version; pinned by `upgrade` |
| `REGISTRY` | `true` | Enable the `registry` addon on start |
| `INSECURE_REGISTRIES` | (empty) | Plain-HTTP registries the node trusts (`--insecure-registry`) |
| `UPDATE_CHECK` | `true` | Highlight new releases after `start`/`status` |

### Behavior

- After each start, `~/.kube/clusters/<cluster>` gets a standalone kubeconfig
  with that cluster's context and credentials (mode `600`, replaced atomically).
- metrics-server goes to the **first** cluster in `CLUSTERS` via an explicit
  Helm `--kube-context`, with `--kubelet-insecure-tls`; the active context is not changed.
- `stop`/`delete`/`status` try every profile and exit nonzero if any failed.
  Invalid names, duplicates and boolean typos are rejected before any tool call.
- `INSECURE_REGISTRIES` is applied at node creation: changing it needs `delete` + `start`.

### Versions: `updates` and `upgrade`

After `start` and `status` the script prints `[UPDATE]` lines (5 s timeout,
never fails the command; disable with `UPDATE_CHECK=false`) when:

- a newer stable Minikube is released than the installed one;
- the installed Minikube supports a newer Kubernetes than `K8S_VERSION`;
- a newer metrics-server chart is in the local Helm cache than `METRICS_VERSION`.

It also warns when versions are not pinned yet. `./minikube.sh updates` prints
the full report, including a Kubernetes release that needs a newer Minikube.
Exit 1 means the check was incomplete, not that an update is available.

Updating is split into steps; nothing is written without an explicit command:

| Command | What it does |
|---------|--------------|
| `upgrade` (or `upgrade plan`) | Shows `KEY: old -> new` for Minikube, `K8S_VERSION`, `METRICS_VERSION`. Writes nothing. |
| `upgrade k8s` | Pins `K8S_VERSION` to the newest stable Kubernetes the installed Minikube supports. |
| `upgrade metrics` | Pins `METRICS_VERSION` to the latest metrics-server chart. |
| `upgrade all` | Both of the above. |
| `upgrade minikube` | `brew upgrade minikube` (Homebrew-installed only); then run `upgrade` again. |

Writing commands show the change and ask for confirmation in a terminal, save
the previous file as `~/.minikube.env.bak`, and update only the affected keys
(other lines are kept). A pin is never lowered. Clusters are not touched: apply
with `./minikube.sh start` (Minikube upgrades an existing cluster in place) and
`./minikube.sh metrics install`.

```bash
./minikube.sh upgrade            # review
./minikube.sh upgrade k8s        # pin Kubernetes only
./minikube.sh start              # apply
```

Switch clusters with `minikube profile <name>` or
`KUBECONFIG=~/.kube/clusters/<name> kubectl ...`.

## Image registry

```bash
# Simplest: load a local image into the node
docker build -t my-app:dev .
minikube image load my-app:dev -p cluster-1
kubectl run my-app --image=my-app:dev --image-pull-policy=IfNotPresent

# Or build directly in the node's Docker daemon
eval $(minikube -p cluster-1 docker-env)
docker build -t my-app:dev .
eval $(minikube -p cluster-1 docker-env -u)

# Or push to the registry addon (macOS/Windows: via port-forward;
# add localhost:5000 to Docker's insecure-registries)
kubectl -n kube-system port-forward svc/registry 5000:80 &
docker tag my-app:dev localhost:5000/my-app:dev
docker push localhost:5000/my-app:dev
kubectl run my-app --image="$(minikube ip -p cluster-1):5000/my-app:dev"
```

On Linux the node IP is routable: push straight to `$(minikube ip -p cluster-1):5000`
after adding it to `insecure-registries` in `/etc/docker/daemon.json`.

## Troubleshooting

```bash
minikube logs -p cluster-1
kubectl -n kube-system logs deployment/metrics-server
kubectl run -it --rm --restart=Never dnsutils --image=autosetup/dnsutils:0.0.4 bash
```

Multiple clusters need distinct service CIDRs (see `SERVICE_CIDR`).

## Development and releases

- CI (`.github/workflows/ci.yml`): `zsh -n`, an offline smoke test with fake
  `minikube`/`kubectl`/`helm` (`.github/ci/smoke.zsh`), actionlint, and on PRs a
  check that `SCRIPT_VERSION` was bumped whenever `minikube.sh` changed.
- Security (`.github/workflows/security.yml`): gitleaks secret scan and OpenSSF
  Scorecard (weekly and on `main`). Actions are pinned to commit SHAs and kept
  current by Dependabot.
- Reviews: [CodeRabbit](https://coderabbit.ai) reviews every PR (`.coderabbit.yaml`).
- Releases (`.github/workflows/release.yml`): after CI passes on `main`, a new
  `SCRIPT_VERSION` in `minikube.sh` is published as release `v<version>` with
  `minikube.sh` and `minikube.sh.sha256`. To release: bump `SCRIPT_VERSION` and merge.

Run the checks locally:

```bash
zsh -n minikube.sh
zsh .github/ci/smoke.zsh
```

## License

[MIT](LICENSE). Security issues: see [SECURITY.md](SECURITY.md).
