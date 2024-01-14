#!/usr/bin/env zsh
cluster=$(kubectl config view -o jsonpath='{.clusters[].name}')
echo "Current cluster is $cluster"
if [ $cluster = "cluster-1" ]; then
kubectl apply -f apps/*.yaml
else
echo "Please switch to cluster-1"
fi