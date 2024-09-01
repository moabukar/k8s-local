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

