#!/usr/bin/env bash
#

kubectl create secret generic etcd-ca --from-file=tls/tls.crt --from-file=tls/tls.key --from-file=tls/ca.crt -n monitoring
