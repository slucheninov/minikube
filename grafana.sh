#!/usr/bin/env zsh
NAME=grafana
VERSION=7.0.2
NAMESPACE=monitoring
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add grafana https://grafana.github.io/helm-charts
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME grafana/grafana --version $VERSION \
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