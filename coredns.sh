#!/usr/bin/env zsh
NAME=coredns
VERSION=1.28.2
NAMESPACE=coredns
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add coredns https://coredns.github.io/helm
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME coredns/coredns --version $VERSION \
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
