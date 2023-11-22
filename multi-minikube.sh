#!/usr/bin/env zsh

VERSION=v1.25.12

if [[ -n $1 ]]; then
case $1 in
     start)
       minikube start --kubernetes-version=$VERSION -p cluster-1
       minikube start --kubernetes-version=$VERSION -p cluster-2
       ;;
     stop)
       minikube stop -p cluster-1
       minikube stop -p cluster-2
       ;;
     *)
       printf "please $0 [start|stop]\n"
       ;;
esac
else
     printf "Cancel run, please  $0 [start|stop]\n"
fi
#
## switch to cluster-1
#minikube profile cluster-1
# switch to cluster-2
#minikube profile cluster-2