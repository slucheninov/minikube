#!/usr/bin/env zsh
NAME=rabbitmq-operator
VERSION=3.3.2
NAMESPACE=rabbitmq-operator
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add bitnami https://charts.bitnami.com/bitnami
       helm repo update
       ;;
     start)
       #kubectl create namespace $NAME
       helm upgrade --install $NAME bitnami/rabbitmq-cluster-operator --version $VERSION \
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

