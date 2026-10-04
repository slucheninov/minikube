# Minikube Cluster Management

This repository provides tools and scripts for managing Minikube Kubernetes clusters with support for single and multi-cluster setups.

## Features

- **Universal cluster management** - Single script for managing one or multiple clusters
- **Flexible configuration** - Environment-based configuration
- **CNI support** - Support for Cilium, Calico, and default CNI plugins
- **Metrics Server integration** - Optional automatic installation of metrics-server
- **Image registry** - Optional in-cluster registry addon and support for trusting external insecure registries
- **Helm charts** - Pre-configured Helm charts for common services

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [Helm](https://helm.sh/docs/intro/install/) installed (for metrics-server and other services)
- zsh shell (scripts are written for zsh)

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

### Metrics Server Management

```bash
# Install metrics-server
./minikube.sh metrics install

# Uninstall metrics-server
./minikube.sh metrics uninstall
```

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
| `K8S_VERSION` | `1.33.6` | Kubernetes version to use |
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
K8S_VERSION=1.32.0 ./minikube.sh start
```

### Example 5: Multi-Cluster with Custom Configuration

```bash
CLUSTERS="cluster-1,cluster-2,cluster-3" \
CNI=cilium \
K8S_VERSION=1.33.6 \
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

This repository includes Helm charts and scripts for various services:

- **ArgoCD** - GitOps continuous delivery tool
- **Cert-Manager** - Certificate management
- **CoreDNS** - DNS server
- **External-DNS** - DNS management
- **Grafana** - Metrics visualization
- **Metrics Server** - Kubernetes metrics API
- **Prometheus** - Monitoring and alerting
- **RabbitMQ** - Message broker
- **Vault** - Secrets management

Each service has its own directory under `helm/` with configuration files and installation scripts.

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

When adding new services or features:

1. Follow the existing script structure
2. Add appropriate error handling
3. Update this README with usage examples
4. Test with both single and multi-cluster setups

## License

This project is for experimental and development purposes.
