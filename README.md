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

```bash
$ minikube addons configure registry-creds -p cluster-1   

Do you want to enable AWS Elastic Container Registry? [y/n]: n

Do you want to enable Google Container Registry? [y/n]: y
-- Enter path to credentials (e.g. /home/user/.config/gcloud/application_default_credentials.json):/Users/lucheninov/terraform-admin.json
-- Do you want to change the GCR URL (Default https://gcr.io)? [y/n]: n

Do you want to enable Docker Registry? [y/n]: n

Do you want to enable Azure Container Registry? [y/n]: n
✅  registry-creds was successfully configured
$
$ minikube addons enable registry-creds -p cluster-1
```
