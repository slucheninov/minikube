# Create a Kubernetes secret with the credentials in the same namespace of ExternalDNS.
# Link: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/gke.md#static-credentials
kubectl create secret generic "external-dns" --namespace external-dns --from-file external-dns/credentials.json
