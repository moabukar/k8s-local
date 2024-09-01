# Local K8s setup using Kind

Start a local kubernetes cluster with traefik ingress and HTTPS 🚀

## Prerequisites

- [Docker](https://docs.docker.com/install/)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [Helm](https://helm.sh/docs/intro/install/)

## Getting started

```bash
# start local cluster with ingress, HTTPS and a demo app
make up

# stop
make down

make help
```

## Access

```bash

› Done!

[💻] WhoAmI application running on: https://whoami.127.0.0.1.nip.io
[💻] Traefik dashboard accessible at http://traefik.127.0.0.1.nip.io/dashboard/ 
```

## Debugging (for cert)

```bash
k get certificate -A


kubectl get secret cert-whoami -o jsonpath='{.data.tls\.crt}' | base64 --decode > whoami.crt

kubectl get secret cert-traefik -o jsonpath='{.data.tls\.crt}' | base64 --decode > traefik.crt


- Open keychain access (if using Mac)

- Drag the whoami.crt & traefik.crt to login or local items keychain

- Trust both certs

- Access whoami app on "https://whoami.127.0.0.1.nip.io" 

- Access Traefik HTTPS on "https://traefik.127.0.0.1.nip.io/dashboard/"
```

## Monitoring

```bash

## Prometheus

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm repo update

helm install prometheus prometheus-community/prometheus --namespace monitoring --create-namespace

Access prometheus on "http://prometheus.127.0.0.1.nip.io"

## Grafana

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update


helm install grafana grafana/grafana --namespace monitoring --create-namespace

### Get your 'admin' user password 
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# grafana.monitoring.svc.cluster.local

Access grafana on "http://grafana.127.0.0.1.nip.io"

user: admin
pass: from above secret
```


## Grafana data source

```bash

http://prometheus-server.monitoring.svc.cluster.local:80

```


## Improvements on tools to add:

- Alertmanager
- Loki (logging)
- K8s dashboard?
- ArgoCD
- KEDA? 
- ELK??
- Service mesh (Istio or Linkerd)
- GitLab/Jenkins?
- MinIO
- PostgreSQL/MySQL DBs
- 
