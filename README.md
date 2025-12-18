# Minikube Cluster Management

This repository provides tools and scripts for managing Minikube Kubernetes clusters with support for single and multi-cluster setups.

## Features

- **Universal cluster management** - Single script for managing one or multiple clusters
- **Flexible configuration** - Environment-based configuration
- **CNI support** - Support for Cilium, Calico, and default CNI plugins
- **Metrics Server integration** - Optional automatic installation of metrics-server
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
