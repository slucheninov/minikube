# Minikube Cluster Management

Local Kubernetes lab on Minikube: a single script for single and multi-cluster setups, plus declarative Helm releases (helmfile) and manifests for common services.

## Features

- **Universal cluster management** - Single script for managing one or multiple clusters
- **Flexible configuration** - Environment-based configuration
- **CNI support** - Support for Cilium, Calico, and default CNI plugins
- **Metrics Server integration** - Optional automatic installation of metrics-server
- **Image registry** - Optional in-cluster registry addon and support for trusting external insecure registries
- **Helm services** - Declarative releases in `helmfile.yaml` with values in `charts/`

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed (local version: 1.39.0)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [Helm](https://helm.sh/docs/intro/install/) installed (for metrics-server and other services)
- [helmfile](https://helmfile.readthedocs.io/) + [helm-diff](https://github.com/databus23/helm-diff) (for services in `helmfile.yaml`)
- zsh (`minikube.sh` is a zsh script)
- bash and jq (for `scripts/vault-init.sh` and offline tests)
- [Docker](https://docs.docker.com/get-docker/) (only for local images in `docker/`)

Missing Minikube/Helm tools can be installed interactively through Homebrew.
On other setups, the script prints the official installation guide and exits; it
does not download and execute installer scripts.

## Repository Layout

```
minikube.sh      Cluster lifecycle (start/stop/delete, metrics-server, registry addon)
helmfile.yaml    All Helm releases (repos, chart versions, namespaces, labels)
charts/<name>/   Values files for each release (variants: values-<variant>.yaml)
manifests/       Plain Kubernetes manifests for `kubectl apply -f`
docker/<name>/   Local Docker images (envoy, nginx) with run.sh
scripts/         Helper scripts (vault-init.sh, etcd-rehearsal/)
tests/           Offline regression tests for scripts
.secrets/        Generated secrets, gitignored (Vault keys, etcd rehearsal CA)
examples/        Standalone sidecar pattern demos
```

## Quick Start

### Start a Single Cluster

```bash
./minikube.sh start
```

After each successful cluster start, the script also refreshes
`~/.kube/clusters/<cluster-name>` (for example, `~/.kube/clusters/cluster-1`)
from the kubeconfig updated by Minikube. Each file contains only that cluster's
context and embedded credentials, with permissions set to `600`. The existing
file is preserved if the export fails.

### Start Multiple Clusters

```bash
CLUSTERS="cluster-1,cluster-2" CNI=cilium ./minikube.sh start
```

### Start Cluster with Metrics Server

```bash
METRICS_SERVER=true ./minikube.sh start
```

## Usage

### Basic Commands

```bash
# Start cluster(s)
./minikube.sh start

# Stop cluster(s)
./minikube.sh stop

# Show cluster status
./minikube.sh status

# Delete cluster(s) - requires confirmation
./minikube.sh delete
```

### Check for Updates

```bash
./minikube.sh updates
K8S_VERSION=1.35.9 ./minikube.sh updates
```

The check highlights `UPDATE` when a newer stable version exists:

- Minikube: installed CLI version versus the latest stable GitHub release.
- Kubernetes patch: configured `K8S_VERSION` versus the latest patch in that minor branch.
- Kubernetes latest stable: configured version versus the newest stable release across branches.

The repository default is also printed. Kubernetes comparisons use the configured
version for `start`, not the version of an existing cluster. A new upstream release
may require a newer Minikube; the check does not certify compatibility or upgrade
anything. It works without a running cluster and requires `curl` and `jq`.

Sources: [Minikube releases](https://github.com/kubernetes/minikube/releases),
[Kubernetes stable](https://dl.k8s.io/release/stable.txt) and the matching
`stable-<major>.<minor>.txt` marker. Each request has a 5-second connection timeout
and 15-second total timeout. Unavailable checks are reported explicitly and return
exit code 1; successful checks return 0 even when updates are available. Missing
Minikube or non-stable version strings are reported as incomplete checks.

Run this command when reviewing updates. Regular lifecycle commands do not add
network checks. After reviewing release notes, update Minikube with your package
manager and change the Kubernetes pin deliberately; changing `K8S_VERSION` alone
does not describe or migrate an existing cluster.

### Metrics Server Management

```bash
# Install metrics-server
./minikube.sh metrics install

# Uninstall metrics-server
./minikube.sh metrics uninstall
```

Metrics commands target the first profile in `CLUSTERS` through an explicit Helm
`--kube-context`; they do not change the active context. Stop/delete/status return
a nonzero exit code on partial failure after attempting every requested profile.
Invalid arguments, duplicate/empty profile names and boolean typos are rejected
before cluster operations.

### Registry Management

```bash
# Enable the built-in minikube registry addon on the cluster(s) in $CLUSTERS
./minikube.sh registry install

# Disable it
./minikube.sh registry uninstall

# Print host:port of the in-cluster registry (node IP + 5000)
./minikube.sh registry port
```

## Configuration

The script uses environment variables for configuration. All variables are optional and have sensible defaults.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTERS` | `cluster-1` | Comma-separated list of cluster names |
| `K8S_VERSION` | `1.35.9` | Kubernetes version to use |
| `CNI` | (empty) | CNI plugin: `cilium`, `calico`, or empty for default |
| `SERVICE_CIDR` | (auto) | Service cluster IP range (auto-assigned for known clusters) |
| `METRICS_SERVER` | `false` | Install metrics-server on start: `true` or `false` |
| `METRICS_VERSION` | `3.11.0` | Metrics-server Helm chart version |
| `REGISTRY` | `false` | Enable in-cluster `registry` addon on start: `true` or `false` |
| `INSECURE_REGISTRIES` | (empty) | Comma-separated list of registries the node should trust over plain HTTP (passed to `minikube start --insecure-registry`) |

### Service CIDR Mapping

For multi-cluster setups, the script automatically assigns service CIDR ranges:

- `cluster-1`: `172.16.1.0/24`
- `cluster-2`: `172.16.2.0/24`
- `cluster-3`: `172.16.3.0/24`

You can override this by setting `SERVICE_CIDR` environment variable.

## Examples

### Example 1: Single Cluster with Default Settings

```bash
./minikube.sh start
```

### Example 2: Two Clusters with Cilium CNI

```bash
CLUSTERS="cluster-1,cluster-2" CNI=cilium ./minikube.sh start
```

### Example 3: Single Cluster with Metrics Server

```bash
METRICS_SERVER=true ./minikube.sh start
```

### Example 4: Custom Kubernetes Version

```bash
K8S_VERSION=1.34.12 ./minikube.sh start
```

### Example 5: Multi-Cluster with Custom Configuration

```bash
CLUSTERS="cluster-1,cluster-2,cluster-3" \
CNI=cilium \
K8S_VERSION=1.35.9 \
METRICS_SERVER=true \
./minikube.sh start
```

### Example 6: Cluster with In-Cluster Registry

```bash
REGISTRY=true ./minikube.sh start
./minikube.sh registry port
```

### Example 7: Cluster Trusting an External Insecure Registry

```bash
INSECURE_REGISTRIES="my-registry.lan:5000" ./minikube.sh start
```

## Switching Between Clusters

To switch between clusters, use the `minikube profile` command:

```bash
# Switch to cluster-1
minikube profile cluster-1

# Switch to cluster-2
minikube profile cluster-2

# List all profiles
minikube profile list
```

## Additional Services

Helm releases are managed with [helmfile](https://helmfile.readthedocs.io/) (requires `helmfile` and the `helm-diff` plugin: `helm plugin install https://github.com/databus23/helm-diff`).

```bash
helmfile list                          # all releases with labels
helmfile -l name=vault apply           # install / upgrade one release
helmfile -l group=monitoring apply     # prometheus, grafana, kube-state-metrics
helmfile -l name=vault destroy         # uninstall
```

Always pass a selector: a bare `helmfile apply` installs every release.

| Release | Group | Notes |
|---------|-------|-------|
| cert-manager, argocd, vault, rabbitmq-operator | `platform` | After Vault install run `KUBE_CONTEXT=cluster-1 scripts/vault-init.sh` (see credential setup below) |
| coredns, external-dns | `dns` | Values variant via `COREDNS_VALUES` / `EXTERNAL_DNS_VALUES`, e.g. `COREDNS_VALUES=values-etcd.yaml` |
| prometheus, grafana, kube-state-metrics | `monitoring` | |
| keydb, opensearch | `data` | |
| nginx, nginx2 | `demo` | Two nginx instances with different CoreDNS agent labels |

metrics-server is installed via `./minikube.sh metrics install`, not helmfile.

`COREDNS_VALUES=values-redis.yaml` uses the `keydb` release as backend (zone fixture: `charts/keydb/coredns-zone-fixture.json`). The etcd variants of CoreDNS and external-dns expect an existing etcd in namespace `etcd`; it is not deployed by this repo.

## Local Service Credentials

Fixed test credentials are intentional for this local Minikube lab. They can
remain in values and manifests; no password generation or manual Secret setup is
required. Grafana uses `admin` / `admin`; KeyDB and the CoreDNS Redis variant share
the same test password. Argo CD retains its configured test admin password hash.

RabbitMQ user Secrets are included in `manifests/rabbitmq/users.yaml`. After
installing `rabbitmq-operator`, apply the directory as usual:

```bash
kubectl --context=cluster-1 apply -f manifests/rabbitmq/
```

The exporter reads the monitoring password from the included Secret so it does
not need a duplicate password in the cluster manifest. The `guest` user remains
a lab administrator; the monitoring user has management monitoring access with
AMQP configure/write/read permissions removed. RabbitMQ uses cluster-provided DNS.

Argo CD serves HTTPS with its generated certificate; ingress is disabled. Access
it locally with:

```bash
kubectl --context=cluster-1 -n argocd port-forward svc/argocd-server 8443:443
```

Open `https://localhost:8443` and use the existing test admin credentials.

### Vault

```bash
KUBE_CONTEXT=cluster-1 scripts/vault-init.sh         # initialize once, then unseal
KUBE_CONTEXT=cluster-1 scripts/vault-init.sh unseal  # retry join/unseal with saved keys
```

`KUBE_CONTEXT` is mandatory. `NAMESPACE` defaults to `vault`; `KEYS_FILE` defaults
to `.secrets/vault-cluster-keys.json`. For multiple clusters, set distinct
`KEYS_FILE` paths and use the same path when unsealing that cluster. Back up this
file securely: the lab uses a single unseal share and stores the root token there.
The script creates the file with mode `600`, refuses to overwrite it, and retains
partial output if initialization fails. Inspect that file and the server state
before recovery; do not delete it merely to retry initialization. The unseal key
is sent as JSON on stdin through [`vault write`](https://developer.hashicorp.com/vault/docs/commands/write),
without appearing in process arguments. The root token is not printed.

## Security Review and Follow-up

Fixed test passwords are an accepted local-lab default, not a finding requiring
rotation or Git history cleanup. The items below concern reliability, host
isolation, or optional hardening if the lab is later shared or exposed. No image
CVE scan or live-cluster audit is implied.

| Priority | Remaining issue | Suggested next step |
|----------|-----------------|---------------------|
| High | Vault listener disables TLS and uses one unseal share; root token and share are stored together | Configure trusted TLS, separate custody/backups, and use auto-unseal or a multi-share policy for a shared environment |
| High | OpenSearch has an explicitly privileged sysctl init container | Set required sysctls on lab nodes, then remove the privileged container and verify startup |
| Medium | CoreDNS Redis variant allows unrestricted AXFR/IXFR and `transfer to *` | Restrict transfers to known secondaries or disable them if unused |
| Medium | etcd variants use HTTP; external-dns's HTTP endpoint is paired with enabled TLS settings | Choose one matching endpoint/TLS configuration and deploy authenticated etcd separately |
| Medium | Istio explicitly disables automatic mTLS | Enable and test mesh mTLS before relying on workload isolation |
| Medium | metrics-server skips kubelet certificate verification; registry addon is HTTP | Keep these lab-only; configure trusted certificates/TLS where applicable |
| Medium | Old pinned charts/images, floating image tags, custom CoreDNS build without provenance in this repo | Scan actual image digests with Trivy/Grype, review upgrades, pin digests, document the custom image source |
| Medium | Demo workloads lack consistent resource limits, restricted security contexts and network policies | Add controls per workload and test DNS, monitoring and sidecar behavior with a policy-enforcing CNI |

Local Docker demo ports bind to `127.0.0.1`. Envoy's demo admin listener also binds
to loopback. Its GCS upstream now checks the certificate chain and DNS name using
the container CA bundle, following the [Envoy TLS guidance](https://www.envoyproxy.io/docs/envoy/latest/start/quick-start/securing).
Validate the configuration against the actual Envoy image before rollout.

## Validation

```bash
zsh -n minikube.sh
bash -n scripts/vault-init.sh
sh -n docker/envoy/run.sh
sh -n docker/nginx/run.sh
python3 -m unittest discover -s tests -v
helmfile -l name=keydb template
COREDNS_VALUES=values-redis.yaml helmfile -l name=coredns template
helmfile -l name=grafana template
helmfile -l name=argocd template
```

Offline tests use fake `minikube`, `kubectl`, and `helm` commands and an isolated
home directory; they do not contact clusters. Chart rendering validates templates,
not application startup. Next, run single/multi-cluster smoke tests in a disposable
lab, including Vault recovery, RabbitMQ metrics, Redis-backed DNS and HTTPS access.
Add these offline checks and a secret scanner to CI; keep chart/image upgrades in
separate changes with integration checks.

## Manifests

```bash
kubectl apply -f manifests/argocd/headless-service.yaml   # after argocd
kubectl apply -f manifests/rabbitmq/                       # after rabbitmq-operator
kubectl apply -f manifests/istio/envoy-filter-coredns.yaml # needs Istio
kubectl apply -f manifests/test/scale-nodes-nginx.yaml     # node scaling test
```

`manifests/istio/istio-operator.yaml` is an `IstioOperator` spec for `istioctl install -f`.

### Local Docker images

```bash
docker/envoy/run.sh   # builds envoy:v1, runs on :8080
docker/nginx/run.sh   # builds nginx:v1, runs on :81
```

Both create the shared Docker network `netlite` if it is missing.

## etcd Upgrade Rehearsal

`scripts/etcd-rehearsal/` reproduces the coredns etcd migration from the Bitnami chart 9.8.1 to the own
`charts-common/etcd` chart and the upgrade 3.5.11 → 3.5.34 → 3.6.15 → 3.7.2 under a load generator that mimics
corenet, lock and short-lease clients. It is not part of helmfile: the Bitnami and own charts are swapped on the
same release `etcd` with plain `helm`. Setup, the step helper `rehearsal.sh` (`gate`, `roll`, `stats`) and cleanup:
[scripts/etcd-rehearsal/README.md](scripts/etcd-rehearsal/README.md).

## Troubleshooting

### Cluster Won't Start

1. Check Minikube status:
   ```bash
   minikube status
   ```

2. Check system requirements:
   ```bash
   minikube start --dry-run
   ```

3. View Minikube logs:
   ```bash
   minikube logs
   ```

### Metrics Server Issues

1. Check if metrics-server is installed:
   ```bash
   kubectl get deployment metrics-server -n kube-system
   ```

2. Check metrics-server logs:
   ```bash
   kubectl logs -n kube-system deployment/metrics-server
   ```

3. Reinstall metrics-server:
   ```bash
   ./minikube.sh metrics uninstall
   ./minikube.sh metrics install
   ```

### Network Issues

If you're running multiple clusters, ensure they have different service CIDR ranges to avoid conflicts.

## Testing DNS and Network Tools

To test DNS resolution and network connectivity in your cluster:

```bash
# Run DNS utils pod
kubectl run -it --rm --restart=Never busybox \
  --image=autosetup/dnsutils:0.0.4 bash

# Or use Alpine
kubectl run -it --rm --restart=Never busybox \
  --image=alpine:3.18 sh
```

## Image Registry

Minikube ships a built-in registry addon that runs an in-cluster Docker registry on port `5000`. This script exposes it via the `REGISTRY` env var and the `registry` subcommand. You can also use `INSECURE_REGISTRIES` to tell the node's container runtime to trust external plain-HTTP registries.

### Option 1: In-cluster registry addon

Run a registry inside the cluster and push images to it.

```bash
# Start the cluster with the registry addon enabled
REGISTRY=true ./minikube.sh start

# Or enable it later on an already running cluster
./minikube.sh registry install

# Find out the host:port to push to (node IP + 5000)
./minikube.sh registry port
# -> cluster-1: 192.168.49.2:5000
```

#### Pushing an image to the in-cluster registry

There are three common ways to get an image into the registry. Pick the one that matches your driver/OS.

##### Way A — `minikube image load` (simplest, any OS/driver)

Loads an image straight from your host's Docker into the cluster's container runtime. The registry addon isn't strictly required for this, but the image becomes immediately pullable by Pods on that node.

```bash
# Build locally
docker build -t my-app:dev .

# Push the image into the node
minikube image load my-app:dev -p cluster-1

# Verify it's on the node
minikube image ls -p cluster-1 | grep my-app

# Reference it in a Pod with imagePullPolicy: IfNotPresent
kubectl run my-app --image=my-app:dev --image-pull-policy=IfNotPresent
```

##### Way B — build directly inside minikube's Docker daemon

`docker build` runs against the node's daemon, so the image lands there without a push. Handy on macOS/Windows where the node IP is not routable from the host.

```bash
# Point your local docker CLI at minikube's daemon for this shell
eval $(minikube -p cluster-1 docker-env)

# Build — image is stored directly on the node
docker build -t my-app:dev .

# Use in a Pod
kubectl run my-app --image=my-app:dev --image-pull-policy=IfNotPresent

# Reset when done
eval $(minikube -p cluster-1 docker-env -u)
```

##### Way C — `docker push` to the registry addon

Use this when you want a real push flow (CI, Skaffold, Tilt, etc.) against `host:5000`.

**Linux (the node IP is routable from the host):**

```bash
# 1. Get the host:port
REG_HOST="$(minikube ip -p cluster-1):5000"

# 2. Tell your local Docker to treat it as insecure (HTTP).
#    Edit /etc/docker/daemon.json once:
#    { "insecure-registries": ["192.168.49.2:5000"] }
#    then: sudo systemctl restart docker

# 3. Tag and push
docker tag my-app:dev "${REG_HOST}/my-app:dev"
docker push "${REG_HOST}/my-app:dev"

# 4. Reference in a Pod using the same host:port
kubectl run my-app --image="${REG_HOST}/my-app:dev"
```

**macOS / Windows (Docker driver, node IP not routable):** port-forward the registry Service to `localhost:5000` and push there.

```bash
# 1. Expose the in-cluster registry on localhost:5000
kubectl -n kube-system port-forward svc/registry 5000:80 &

# 2. On Docker Desktop add "localhost:5000" to
#    Settings -> Docker Engine -> insecure-registries, then Apply & Restart.

# 3. Push
docker tag my-app:dev localhost:5000/my-app:dev
docker push localhost:5000/my-app:dev

# 4. The node itself reaches the registry via its ClusterIP Service,
#    so reference the image from a Pod as <node-ip>:5000/...
REG_HOST="$(minikube ip -p cluster-1):5000"
kubectl run my-app --image="${REG_HOST}/my-app:dev"
```

> The in-cluster registry speaks plain HTTP. The node's container runtime already trusts it (the addon wires that up), but your **host** Docker does not — that's why Way C needs an `insecure-registries` entry on the host. Ways A and B avoid that step entirely.

#### Quick smoke test

```bash
# End-to-end: build -> load -> run
docker build -t hello:dev -<<'DOCKER'
FROM nginx:alpine
RUN echo "hello from minikube registry" > /usr/share/nginx/html/index.html
DOCKER

minikube image load hello:dev -p cluster-1
kubectl run hello --image=hello:dev --image-pull-policy=IfNotPresent --port=80
kubectl wait --for=condition=Ready pod/hello --timeout=60s
kubectl port-forward pod/hello 8080:80 &
curl -s http://localhost:8080
```

### Option 2: Trust an external insecure registry

If you run a registry outside the cluster over plain HTTP (e.g. a lab registry on your LAN), pass it via `INSECURE_REGISTRIES` so the node's container runtime doesn't reject it.

```bash
# Single registry
INSECURE_REGISTRIES="my-registry.lan:5000" ./minikube.sh start

# Multiple (comma-separated)
INSECURE_REGISTRIES="my-registry.lan:5000,10.0.0.5:5000" ./minikube.sh start
```

This maps to `minikube start --insecure-registry=...`. Note that insecure-registry settings are baked into the node at creation time: changing `INSECURE_REGISTRIES` requires `delete` + `start` for that cluster, a simple `stop`/`start` is not enough.

### Combining both

```bash
REGISTRY=true \
INSECURE_REGISTRIES="192.168.49.2:5000" \
CLUSTERS="cluster-1,cluster-2" \
./minikube.sh start
```

## GCP Authentication (Optional)

If you need to pull images from Google Container Registry or Artifact Registry:

### Using registry-creds addon

```bash
minikube addons configure registry-creds -p cluster-1
minikube addons enable registry-creds -p cluster-1
```

### Using gcp-auth addon

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
minikube addons enable gcp-auth -p cluster-1
```

For more information, see the [Minikube GCP Auth documentation](https://minikube.sigs.k8s.io/docs/handbook/addons/gcp-auth/).

## Contributing

- New Helm service: add a release to `helmfile.yaml` (and its repo if new), put values in `charts/<name>/values.yaml`, add it to the table above.
- Plain YAML goes to `manifests/<area>/`, local images to `docker/<name>/`, helper scripts to `scripts/`.
- Changes to `minikube.sh`: test with both single and multi-cluster setups and update this README.

## License

This project is for experimental and development purposes.
