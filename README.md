# Setup minikube for works

## ArgoCD local port  30180
url http://127.0.0.1:30180


### Test utils dns, ping, traceroute
```bash
kubectl run -it --rm --restart=Never busybox --image=autosetup/dnsutils:0.0.4 bash
```
Original
```bash
kubectl run -it --rm --restart=Never busybox --image=alpine3.18 sh
```