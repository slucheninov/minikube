# CoreDNS Helm Deployment

This directory contains configuration and deployment script for running CoreDNS in Kubernetes using Helm.

## Structure

```
coredns/
├── README.md                           # This file
└── values/                             # Helm values files
    ├── helm-values.yaml                # Default configuration
    ├── helm-values-etcd.yaml           # Configuration with etcd backend
    ├── helm-values-redis.yaml          # Configuration with Redis backend
    └── helm-values-example.com.yaml    # Example.com specific configuration
```

## Quick Start

### 1. Initialize Helm Repository

```bash
cd helm
./coredns.sh init
```

### 2. Deploy CoreDNS

**Default configuration:**
```bash
./coredns.sh start
```

**With etcd backend:**
```bash
./coredns.sh start --values coredns/values/helm-values-etcd.yaml
```

**With Redis backend:**
```bash
./coredns.sh start --values coredns/values/helm-values-redis.yaml
```

**With custom configuration:**
```bash
./coredns.sh start --values coredns/values/helm-values-example.com.yaml
```

### 3. Check Status

```bash
./coredns.sh status
```

### 4. Stop and Remove

```bash
./coredns.sh stop
```

## Configuration

### Helm Chart Version

Current configuration uses:
- **Chart:** coredns/coredns v1.28.2
- **Repository:** https://coredns.github.io/helm

### Values Files

#### Default Configuration (`values/helm-values.yaml`)

Standard CoreDNS configuration suitable for most use cases.

#### etcd Backend Configuration (`values/helm-values-etcd.yaml`)

CoreDNS configured to use etcd as backend for dynamic DNS records.

Features:
- Custom CoreDNS image: `autosetup/coredns:0.0.2`
- etcd plugin enabled
- Resource limits: 100m CPU, 128Mi Memory

**Prerequisites:**
- etcd cluster must be deployed first (see `../../coredns-etcd/`)
- etcd endpoint should be accessible from CoreDNS pods

#### Redis Backend Configuration (`values/helm-values-redis.yaml`)

CoreDNS configured to use Redis as backend for dynamic DNS records.

Features:
- Custom CoreDNS image: `autosetup/coredns:0.0.2`
- Redis plugin enabled
- Resource limits: 100m CPU, 128Mi Memory

**Prerequisites:**
- Redis instance must be deployed and accessible

#### Example.com Configuration (`values/helm-values-example.com.yaml`)

Domain-specific configuration for example.com.

## Commands

### Available Commands

```bash
./coredns.sh init       # Initialize Helm repository
./coredns.sh start      # Deploy CoreDNS
./coredns.sh stop       # Remove CoreDNS
./coredns.sh status     # Check CoreDNS status
./coredns.sh help       # Show help message
```

### Script Features

- ✅ bash-based (better compatibility)
- ✅ Strict error handling (`set -euo pipefail`)
- ✅ Color-coded logging (INFO/WARN/ERROR)
- ✅ Status command for health checks
- ✅ Help command with examples
- ✅ Custom values file support via `--values`
- ✅ 10-minute timeout for deployments
- ✅ File validation
- ✅ Interactive namespace deletion prompt

## Troubleshooting

### CoreDNS Not Starting

**Check pod status:**
```bash
kubectl get pods -n coredns -l app.kubernetes.io/name=coredns
kubectl describe pods -n coredns -l app.kubernetes.io/name=coredns
```

**Check logs:**
```bash
kubectl logs -n coredns -l app.kubernetes.io/name=coredns
```

### Connection to Backend Failed

**For etcd backend:**
```bash
# Check etcd is running
kubectl get pods -n coredns -l app.kubernetes.io/name=etcd

# Test etcd connectivity from CoreDNS pod
kubectl exec -it -n coredns <coredns-pod> -- nslookup etcd.coredns.svc.cluster.local
```

**For Redis backend:**
```bash
# Check Redis is running
kubectl get pods -n <redis-namespace> -l app=redis

# Test Redis connectivity
kubectl exec -it -n coredns <coredns-pod> -- nc -zv redis.namespace.svc.cluster.local 6379
```

### DNS Resolution Issues

**Test DNS from a pod:**
```bash
# Create test pod
kubectl run -it --rm test-dns --image=busybox --restart=Never -- nslookup kubernetes.default

# Test specific domain
kubectl run -it --rm test-dns --image=busybox --restart=Never -- nslookup example.com <coredns-service-ip>
```

**Check CoreDNS configuration:**
```bash
kubectl get configmap -n coredns coredns -o yaml
```

## Advanced Usage

### Custom Corefile Configuration

To customize the Corefile, modify the `servers` section in your values file:

```yaml
servers:
  - zones:
      - zone: .
    port: 53
    plugins:
      - name: errors
      - name: health
        configBlock: |-
          lameduck 5s
      - name: ready
      - name: kubernetes
        parameters: cluster.local in-addr.arpa ip6.arpa
        configBlock: |-
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
      - name: forward
        parameters: . /etc/resolv.conf
      - name: cache
        parameters: 30
      - name: loop
      - name: reload
      - name: loadbalance
```

### Multiple CoreDNS Instances

To run multiple CoreDNS instances for different purposes:

1. Create separate values files with different configurations
2. Deploy with different release names and namespaces
3. Use different service types or ports

### Monitoring and Metrics

Enable Prometheus metrics in your values file:

```yaml
prometheus:
  service:
    enabled: true
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "9153"
  monitor:
    enabled: true
```

## Integration with etcd

To use CoreDNS with etcd backend:

1. **Deploy etcd cluster first:**
   ```bash
   cd ../..
   ./coredns-etcd.sh init
   ./coredns-etcd.sh start
   ```

2. **Deploy CoreDNS with etcd configuration:**
   ```bash
   cd helm
   ./coredns.sh start --values coredns/values/helm-values-etcd.yaml
   ```

3. **Verify connection:**
   ```bash
   ./coredns.sh status
   kubectl logs -n coredns -l app.kubernetes.io/name=coredns | grep etcd
   ```

## References

- [CoreDNS Official Documentation](https://coredns.io/manual/toc/)
- [CoreDNS Helm Chart](https://github.com/coredns/helm)
- [CoreDNS Plugins](https://coredns.io/plugins/)
- [etcd Plugin Documentation](https://coredns.io/plugins/etcd/)

## Support

For issues with:
- **CoreDNS chart:** Check [CoreDNS Helm Chart Issues](https://github.com/coredns/helm/issues)
- **etcd integration:** See `../../coredns-etcd/README.md`
- **Custom images:** Verify image availability and tags
