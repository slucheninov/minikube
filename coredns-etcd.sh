#!/usr/bin/env zsh
NAME=etcd
VERSION=9.5.6
NAMESPACE=coredns
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add bitnami https://charts.bitnami.com/bitnami
       helm repo update
       ;;
     start)
       kubectl create namespace $NAMESPACE
       kubectl apply -f coredns-etcd/cert-manager.yaml -n $NAMESPACE
       sleep 5
       helm upgrade --install $NAME bitnami/etcd --version $VERSION \
         --namespace $NAMESPACE --create-namespace --wait --values coredns-etcd/helm-values.yaml
       ;;
     stop)
       helm uninstall $NAME --namespace $NAMESPACE
       #kubectl delete secret etcd-client-certs --namespace $NAMESPACE
       #kubectl delete -f etcd/cert-manager.yaml
       ;;
     *)
       printf "please %s [init|start|stop]\n" "$0"
       ;;
esac
else
     printf "Cancel run, please %s [init|start|stop]\n" "$0"
fi
