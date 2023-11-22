kubectl get secrets/etcd-client-tls -n etcd -o jsonpath='{.data.ca\.crt}' |base64 -d > tls/ca.crt
kubectl get secrets/etcd-client-tls -n etcd -o jsonpath='{.data.tls\.crt}' |base64 -d > tls/tls.crt
kubectl get secrets/etcd-client-tls -n etcd -o jsonpath='{.data.tls\.key}' |base64 -d > tls/tls.key
