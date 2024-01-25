#!/usr/bin/env zsh
NAME=nginx
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
       printf "please %s [init|start|stop]\n" "$0"
       ;;
esac
else
     printf "Cancel run, please %s [init|start|stop]\n" "$0"
fi

