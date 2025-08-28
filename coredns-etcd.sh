#!/usr/bin/env zsh
NAME=etcd
VERSION=11.1.3
NAMESPACE=coredns
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add bitnami https://charts.bitnami.com/bitnami
       helm repo update
       ;;
     start)
       kubectl create namespace $NAMESPACE
       kubectl apply -f coredns-etcd/secrets.yaml -n $NAMESPACE
       sleep 5
       helm upgrade --install $NAME bitnami/etcd --version $VERSION \
         --namespace $NAMESPACE --create-namespace --wait --values coredns-etcd/helm-values.yaml
       ;;
     stop)
       helm uninstall $NAME --namespace $NAMESPACE
       kubectl delete -f coredns-etcd/secrets.yaml -n $NAMESPACE
       kubectl delete namespace $NAMESPACE
       ;;
     *)
       printf "please %s [init|start|stop]\n" "$0"
       ;;
esac
else
     printf "Cancel run, please %s [init|start|stop]\n" "$0"
fi
