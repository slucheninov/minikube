#!/usr/bin/env zsh
NAME=external-dns
VERSION=6.26.5
NAMESPACE=etcd
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add bitnami https://charts.bitnami.com/bitnami
       helm repo update
       ;;
     start)
       kubectl create namespace $NAME
       kubectl create secret generic "$NAME" --namespace $NAME --from-file $NAME/credentials.json
       helm upgrade --install $NAME bitnami/external-dns --version $VERSION \
         --namespace $NAMESPACE --create-namespace --wait --values $NAME/helm-values.yaml
       ;;
     stop)
       helm uninstall $NAME --namespace $NAMESPACE
       kubectl delete secret $NAME --namespace $NAMESPACE
       ;;
     *)
       printf "please %s [init|start|stop]\n" "$0"
       ;;
esac
else
     printf "Cancel run, please %s [init|start|stop]\n" "$0"
fi

