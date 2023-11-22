#!/usr/bin/env zsh
NAME=nginx2
VERSION=15.3.4
NAMESPACE=$NAME
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add bitnami https://charts.bitnami.com/bitnami
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME bitnami/nginx --version $VERSION \
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

