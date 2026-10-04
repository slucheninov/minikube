# external-dns

Values for the `external-dns` release in `helmfile.yaml` (namespace `etcd`).

- `values.yaml`: CoreDNS provider, etcd over TLS (secret `etcd-client-tls`), default
- `values-etcd.yaml`: CoreDNS provider, etcd with auto-generated TLS
- `values-clouddns.yaml`: Google Cloud DNS

```bash
EXTERNAL_DNS_VALUES=values-clouddns.yaml helmfile -l name=external-dns apply
```

Cloud DNS needs a static-credentials secret in the release namespace first
([docs](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/gke.md#static-credentials)):

```bash
kubectl create namespace etcd
kubectl create secret generic external-dns --namespace etcd \
  --from-file charts/external-dns/credentials.json   # gitignored
```
