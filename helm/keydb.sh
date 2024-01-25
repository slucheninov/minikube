#!/usr/bin/env zsh
NAME=keydb
VERSION=0.48.0
NAMESPACE=keydb
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add enapter https://enapter.github.io/charts/
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME enapter/keydb --version $VERSION \
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
