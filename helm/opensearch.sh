#!/usr/bin/env zsh
NAME=opensearch
VERSION=2.11.0
NAMESPACE=opensearch
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add opensearch-project-helm-charts https://opensearch-project.github.io/helm-charts
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME opensearch-project-helm-charts/opensearch --version $VERSION \
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
