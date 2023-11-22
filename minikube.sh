#!/usr/bin/env zsh

VERSION=v1.26.10

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
       printf "please $0 [start|stop]\n"
       ;;
esac
else
     printf "Cancel run, please  $0 [start|stop]\n"
fi
