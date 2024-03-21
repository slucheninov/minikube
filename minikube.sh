#!/usr/bin/env zsh
# link https://kubernetes.io/releases/
VERSION=1.26.14
#VERSION=v1.28.5

if [[ -n $1 ]]; then
case $1 in
     start)
       minikube start --kubernetes-version=$VERSION -p cluster-1
       ;;
     stop)
       minikube stop -p cluster-1
       ;;
     delete)
       minikube delete -p cluster-1
       ;;
     *)
       printf "please %s [start|stop]\n" "$0"
       ;;
esac
else
     printf "Cancel run, please %s [start|stop]\n" "$0"
fi
