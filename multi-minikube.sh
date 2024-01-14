#!/usr/bin/env zsh
# for calico
VERSION=v1.26.11

if [[ -n $1 ]]; then
case $1 in
     start)

       minikube start --kubernetes-version=$VERSION -p cluster-1 --cni=cilium --service-cluster-ip-range=172.16.1.0/24
       minikube start --kubernetes-version=$VERSION -p cluster-2 --cni=cilium --service-cluster-ip-range=172.16.2.0/24
       ;;
     stop)
       minikube stop -p cluster-1
       minikube stop -p cluster-2
       ;;
    delete)
        minikube delete -p cluster-1
        minikube delete -p cluster-2
      ;;
     *)
       printf "please %s [start|stop]\n" "$0"
       ;
esac
else
     printf "Cancel run, please  %s [start|stop]\n" "$0"
fi
# minikube addons configure registry-creds
#
## switch to cluster-1
#minikube profile cluster-1
# switch to cluster-2
#minikube profile cluster-2