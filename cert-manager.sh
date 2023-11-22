#!/usr/bin/env zsh
NAME=cert-manager
VERSION=1.13.1
NAMESPACE=kube-system
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add cert-manager https://charts.jetstack.io
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME cert-manager/cert-manager --version $VERSION \
         --namespace $NAMESPACE --create-namespace --wait --values $NAME/helm-values.yaml
       ;;
     stop)
       helm uninstall $NAME --namespace $NAMESPACE
       ;;
     *)
       printf "please %s [init|start|stop]\n" "$0"
       ;;
esac
else
     printf "Cancel run, please %s [init|start|stop]\n" "$0"
fi
