#!/usr/bin/env zsh
NAME=metrics-server
VERSION=3.11.0
NAMESPACE=kube-system
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME metrics-server/metrics-server --version $VERSION \
         --namespace $NAMESPACE --create-namespace --wait --values $NAME/helm-values.yaml
       ;;
     stop)
       helm uninstall $NAME --namespace $NAMESPACE
       ;;
     *)
       printf "please $0 [init|start|stop]\n"
       ;;
esac
else
     printf "Cancel run, please  $0 [init|start|stop]\n"
fi