#!/usr/bin/env zsh
NAME=etcd
VERSION=9.5.6
NAMESPACE=etcd
if [[ -n $1 ]]; then
case $1 in
     init)
       helm repo add bitnami https://charts.bitnami.com/bitnami
       helm repo update
       ;;
     start)
       kubectl create namespace $NAME
       #kubectl create secret generic etcd-client-certs --namespace etcd --from-file $NAME/tls/client.pem --from-file $NAME/tls/client-key.pem --from-file $NAME/tls/ca.pem
       #kubectl create secret generic etcd-client-certs --namespace etcd --from-file $NAME/tls/server.pem --from-file $NAME/tls/server-key.pem --from-file $NAME/tls/ca.pem
       kubectl apply -f etcd/cert-manager.yaml
       sleep 5
       helm upgrade --install $NAME bitnami/etcd --version $VERSION \
         --namespace $NAMESPACE --create-namespace --wait --values etcd/helm-values.yaml
       ;;
     stop)
       helm uninstall $NAME --namespace $NAMESPACE
       #kubectl delete secret etcd-client-certs --namespace $NAMESPACE
       #kubectl delete -f etcd/cert-manager.yaml
       ;;
     *)
       printf "please $0 [init|start|stop]\n"
       ;;
esac
else
     printf "Cancel run, please  $0 [init|start|stop]\n"
fi
