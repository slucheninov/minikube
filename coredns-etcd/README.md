# CoreDNS etcd Cluster

This directory contains configuration and deployment scripts for running an etcd cluster to support CoreDNS.

## Structure

```
coredns-etcd/
├── README.md                      # This file
├── secrets.yaml                   # TLS certificates for etcd
├── cert-manager.yaml             # Cert-manager configuration
├── values/                       # Helm values files
│   ├── helm-values.yaml          # Production (default image)
│   ├── helm-values-no-auth.yaml  # Development (default image)
│   ├── helm-values-legacy.yaml   # Production (legacy Bitnami images)
│   └── helm-values-official.yaml # Production (official CoreOS images)
├── scripts/                      # Helper scripts
└── tls/                         # TLS certificate files
```

## Quick Start

### 1. Initialize Helm Repository

```bash
./coredns-etcd.sh init
```

### 2. Deploy etcd Cluster

**Production (with authentication):**
```bash
./coredns-etcd.sh start
```

**Development (without authentication):**
```bash
./coredns-etcd.sh start --no-auth
```

**Custom values file:**
```bash
./coredns-etcd.sh start --values /path/to/custom-values.yaml
```

**Using legacy Bitnami images:**
```bash
./coredns-etcd.sh start --values coredns-etcd/values/helm-values-legacy.yaml
```

**Using official etcd images:**
```bash
./coredns-etcd.sh start --values coredns-etcd/values/helm-values-official.yaml
```

### 3. Check Status

```bash
./coredns-etcd.sh status
```

### 4. Stop and Remove

```bash
./coredns-etcd.sh stop
```

## Configuration

### Helm Chart Version

Current configuration uses:
- **Chart:** bitnami/etcd v12.0.18
- **etcd version:** 3.6.4
- **Image:** Automatically selected by Helm chart (default from chart)

**Important Note:** Bitnami has transitioned to [Bitnami Secure Images](https://techdocs.broadcom.com/us/en/vmware-tanzu/bitnami-secure-images/bitnami-secure-images/services/bsi-app-doc/apps-containers-etcd-index.html) with a commercial subscription model. The free Debian-based images are now in the [bitnamilegacy repository](https://hub.docker.com/r/bitnamilegacy/etcd) for temporary migration purposes only.

For production use, consider:
1. **Bitnami Secure Images** (commercial) - Hardened Photon-based images with enterprise support
2. **Legacy Images** - Free but unsupported, available at `bitnamilegacy/etcd`
3. **Official etcd images** - Use `quay.io/coreos/etcd` or `gcr.io/etcd-development/etcd`

This configuration uses the default image from the Helm chart, which will automatically select an appropriate image based on your cluster's capabilities.

### Values Files

#### Production Configuration (`values/helm-values.yaml`)

Features:
- TLS authentication enabled
- 3 replicas for high availability
- Custom labels for CoreDNS integration
- Metrics disabled by default
- Uses existing TLS secret: `etcd-main-tls`
- **Uses Helm chart default image**

#### Development Configuration (`values/helm-values-no-auth.yaml`)

Features:
- Authentication disabled
- Root password: Pa55w()rd
- Simplified setup for development
- **Uses Helm chart default image**

#### Legacy Images Configuration (`values/helm-values-legacy.yaml`)

Features:
- Full production configuration
- **Uses bitnamilegacy/etcd images** (etcd 3.5.17)
- Temporary solution for migration
- No ongoing support from Bitnami
- ⚠️ Requires `global.security.allowInsecureImages: true`

#### Official etcd Images Configuration (`values/helm-values-official.yaml`)

Features:
- Full production configuration
- **Uses official CoreOS etcd images from quay.io** (etcd 3.5.16)
- Community-supported official images
- Good alternative to Bitnami images
- ⚠️ Requires `global.security.allowInsecureImages: true`
- ⚠️ May have degraded features compared to Bitnami images

### TLS Configuration

The cluster uses TLS certificates stored in `secrets.yaml`. The secret must be created before deploying etcd.

Required files in the secret:
- `ca.crt` - Certificate Authority certificate
- `tls.crt` - etcd server certificate
- `tls.key` - etcd server private key

## Troubleshooting

### Image Pull Issues

If you encounter `Back-off pulling image` errors:

**Solution 1: Use Chart Defaults (Recommended)**
The configuration now uses the Helm chart's default image settings. This should work automatically.

**Solution 2: Use Legacy Images (Temporary)**
If you need a specific version, use the legacy repository:
```yaml
global:
  security:
    allowInsecureImages: true  # Required for non-standard images

image:
  registry: docker.io
  repository: bitnamilegacy/etcd
  tag: 3.5.17-debian-12-r4
```

**Solution 3: Use Official etcd Images**
Use the official etcd images instead:
```yaml
global:
  security:
    allowInsecureImages: true  # Required for non-Bitnami images

image:
  registry: quay.io
  repository: coreos/etcd
  tag: v3.5.16
```

**Note:** Bitnami has moved to commercial [Bitnami Secure Images](https://techdocs.broadcom.com/us/en/vmware-tanzu/bitnami-secure-images/). Free Debian-based images are now in the [bitnamilegacy repository](https://hub.docker.com/r/bitnamilegacy/etcd) without ongoing support.

**Security Warning:** Using non-Bitnami images requires setting `global.security.allowInsecureImages: true`, which bypasses Bitnami's container verification. This may result in:
- Degraded security and performance
- Broken chart features
- Missing environment variables
- No CVE tracking or security updates

For more information, see [Bitnami Charts Issue #30850](https://github.com/bitnami/charts/issues/30850).

### Connection Issues

Check etcd cluster status:
```bash
kubectl get pods -n coredns -l app.kubernetes.io/name=etcd
kubectl logs -n coredns -l app.kubernetes.io/name=etcd
```

### Certificate Issues

Verify TLS secret exists:
```bash
kubectl get secret etcd-main-tls -n coredns
```

## Migration Guide

If you're upgrading from the old version:

1. **Backup current deployment:**
   ```bash
   helm get values etcd -n coredns > backup-values.yaml
   ```

2. **Stop old deployment:**
   ```bash
   ./coredns-etcd.sh stop
   ```

3. **Update repository:**
   ```bash
   ./coredns-etcd.sh init
   ```

4. **Deploy new version:**
   ```bash
   ./coredns-etcd.sh start
   ```

## Advanced Usage

### Custom Configuration

Create your own values file based on the examples in `values/` directory:

```bash
cp values/helm-values.yaml values/my-custom-values.yaml
# Edit my-custom-values.yaml
./coredns-etcd.sh start --values values/my-custom-values.yaml
```

### Pod Anti-Affinity

For production deployments, uncomment the `affinity` section in `values/helm-values.yaml` to ensure pods are distributed across different nodes.

### Metrics

Enable Prometheus metrics by setting in your values file:
```yaml
metrics:
  enabled: true
  useSeparateEndpoint: true
```

## Support

For issues and questions, refer to:
- [Bitnami etcd Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/etcd)
- [etcd Documentation](https://etcd.io/docs/)
