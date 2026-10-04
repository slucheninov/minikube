# CoreDNS

Values for the `coredns` release in `helmfile.yaml` (chart `coredns/coredns` v1.28.2, namespace `coredns`).

## Usage

```bash
helmfile -l name=coredns apply                                   # default values.yaml
COREDNS_VALUES=values-etcd.yaml helmfile -l name=coredns apply   # etcd backend
COREDNS_VALUES=values-redis.yaml helmfile -l name=coredns apply  # Redis backend
helmfile -l name=coredns destroy

kubectl get pods,svc,cm -n coredns -l app.kubernetes.io/name=coredns
```

## Configuration

### Values Files

#### Default Configuration (`values.yaml`)

Standard CoreDNS configuration suitable for most use cases.

#### etcd Backend Configuration (`values-etcd.yaml`)

CoreDNS configured to use etcd as backend for dynamic DNS records.

Features:
- Custom CoreDNS image: `autosetup/coredns:0.0.2`
- etcd plugin enabled
- Resource limits: 100m CPU, 128Mi Memory

**Prerequisites:**
- an etcd cluster must be deployed separately (not part of this repo)
- etcd endpoint should be accessible from CoreDNS pods

#### Redis Backend Configuration (`values-redis.yaml`)

CoreDNS configured to use Redis as backend for dynamic DNS records.

Features:
- Custom CoreDNS image: `autosetup/coredns:0.0.2`
- Redis plugin enabled
- Resource limits: 100m CPU, 128Mi Memory

**Prerequisites:**
- `keydb` release deployed (`helmfile -l name=keydb apply`); see `charts/keydb/coredns-zone-fixture.json`

#### Example.com Configuration (`values-example.com.yaml`)

Domain-specific configuration for example.com.

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

## References

- [CoreDNS Official Documentation](https://coredns.io/manual/toc/)
- [CoreDNS Helm Chart](https://github.com/coredns/helm)
- [CoreDNS Plugins](https://coredns.io/plugins/)
- [etcd Plugin Documentation](https://coredns.io/plugins/etcd/)

## Support

For issues with:
- **CoreDNS chart:** Check [CoreDNS Helm Chart Issues](https://github.com/coredns/helm/issues)
- **Custom images:** Verify image availability and tags
