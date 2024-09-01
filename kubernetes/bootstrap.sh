#!/bin/bash

echo -e '\n[BOOSTRAPING CLUSTER]\n'
kind create cluster --wait 5m --config=./kubernetes/kind.yaml

# Fails on errors
set -o errexit

##############################################
# Download helm repositories
##############################################
echo -e "\n[·] Downloading helm repositories..."

## uncomment out below if both already pulled for you (otherwise leave it)

# helm repo add jetstack https://charts.jetstack.io
# helm repo add traefik https://traefik.github.io/charts
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm repo add grafana https://grafana.github.io/helm-charts
# helm repo update

##############################################
# Install helm charts
##############################################

echo -e "\n[·] Installing helm charts..."

echo "Installing cert-manager..."
helm upgrade --install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --values ./kubernetes/controllers/cert-manager/values.yaml \
  --wait

echo "Installing Traefik..."
helm upgrade --install \
  traefik traefik/traefik \
  --values ./kubernetes/controllers/traefik/values.yaml \
  --wait

echo "Installing Prometheus..."
helm install prometheus prometheus-community/prometheus --namespace monitoring --create-namespace


echo "Installing Grafana..."
helm install grafana grafana/grafana --namespace monitoring --create-namespace

##############################################
# Install custom configuration
##############################################
echo -e "\n[·] Installing custom configs..."
kubectl apply -k ./kubernetes/configs

echo -e "\n[·] Installing apps..."
kubectl apply -k ./kubernetes/apps

##############################################
echo -e "\n› Done!"
echo -e "\n[💻] WhoAmI application running on: https://whoami.127.0.0.1.nip.io"
echo -e "[💻] Traefik dashboard accessible at http://traefik.127.0.0.1.nip.io/dashboard/ \n"

echo -e "[💻] Prometheus dashboard accessible at http://prometheus.127.0.0.1.nip.io/ \n"

GRAFANA_PASSWORD=$(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo -e "[💻] Grafana dashboard accessible at http://grafana.127.0.0.1.nip.io/ \n"

echo -e "[💻] Grafana username is: admin"
echo -e "[💻] Grafana password is: $GRAFANA_PASSWORD"
