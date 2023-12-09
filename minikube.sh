#!/usr/bin/env zsh
# link https://kubernetes.io/releases/
VERSION=v1.26.11

if [[ -n $1 ]]; then
case $1 in
     start)
       minikube start --kubernetes-version=$VERSION -p cluster-1 --image-repository=gcr.io
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
