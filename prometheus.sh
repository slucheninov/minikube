#!/usr/bin/env zsh
NAME=prometheus
VERSION=25.4.0
NAMESPACE=monitoring
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME prometheus-community/prometheus --version $VERSION \
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