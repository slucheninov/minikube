#!/usr/bin/env zsh
NAME=argocd
VERSION=5.45.1
NAMESPACE=$NAME
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add argo https://argoproj.github.io/argo-helm
       helm repo update
       ;;
     start)
       helm upgrade --install $NAME argo/argo-cd --version $VERSION \
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

# run access to argocd
# minikube service argocd-server -n argocd --url
