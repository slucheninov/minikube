#!/usr/bin/env zsh
NAME=vault
VERSION=0.27.0
NAMESPACE=vault
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add hashicorp https://helm.releases.hashicorp.com
       helm repo update
       ;;
     start)
       #kubectl create namespace $NAME
       helm upgrade --install $NAME hashicorp/vault --version $VERSION \
         --namespace $NAMESPACE --create-namespace --wait --values $NAME/helm-values.yaml
       ;;
     stop)
       helm uninstall $NAME --namespace $NAMESPACE
       ;;
     init-vault)
        kubectl exec vault-0 -n $NAMESPACE -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
        VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
        kubectl exec vault-0 -n $NAMESPACE -- vault operator unseal $VAULT_UNSEAL_KEY
        kubectl exec -ti vault-1 -n $NAMESPACE -- vault operator raft join http://vault-0.vault-internal:8200
        kubectl exec -ti vault-2 -n $NAMESPACE -- vault operator raft join http://vault-0.vault-internal:8200
        kubectl exec -ti vault-1 -n $NAMESPACE -- vault operator unseal $VAULT_UNSEAL_KEY
        kubectl exec -ti vault-2 -n $NAMESPACE -- vault operator unseal $VAULT_UNSEAL_KEY
        jq -r ".root_token" cluster-keys.json
       ;;
     *)
       printf "please %s [init|start|stop]\n" "$0"
       ;;
esac
else
     printf "Cancel run, please %s [init|start|stop]\n" "$0"
fi

