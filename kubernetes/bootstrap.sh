#!/bin/bash

echo -e '\n[BOOTSTRAPPING CLUSTER]\n'

# Check if the kind cluster already exists
if kind get clusters | grep -q "kind"; then
  echo "Cluster 'kind' already exists. Skipping creation..."
else
  kind create cluster --wait 5m --config=./kubernetes/kind.yaml
fi

# Fails on errors
set -o errexit

##############################################
# Download helm repositories
##############################################
echo -e "\n[·] Downloading helm repositories..."

# Check if a helm repository exists and add it if it doesn't
function add_helm_repo() {
  local repo_name=$1
  local repo_url=$2
  if helm repo list | grep -q "$repo_name"; then
    echo "$repo_name repository already exists. Skipping..."
  else
    echo "Adding $repo_name repository..."
    helm repo add $repo_name $repo_url
  fi
}

# Add repositories with error checking
add_helm_repo jetstack https://charts.jetstack.io
add_helm_repo traefik https://traefik.github.io/charts
add_helm_repo prometheus-community https://prometheus-community.github.io/helm-charts
add_helm_repo grafana https://grafana.github.io/helm-charts
add_helm_repo argo https://argoproj.github.io/argo-helm

helm repo update

##############################################
# Install helm charts
##############################################

echo -e "\n[·] Installing helm charts..."

# Helm upgrade --install ensures idempotency (no errors if already installed)

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
helm upgrade --install \
  prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --wait

echo "Installing Grafana..."
helm upgrade --install \
  grafana grafana/grafana \
  --namespace monitoring \
  --create-namespace \
  --wait

echo "Installing ArgoCD..."
helm upgrade --install \
  argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --wait
##############################################
# Apply ArgoCD patch for --insecure
##############################################
echo -e "\n[·] Patching ArgoCD for --insecure..."

kubectl patch deployment argocd-server -n argocd \
  --type='json' \
  -p='[{
        "op": "add", 
        "path": "/spec/template/spec/containers/0/args/-", 
        "value": "--insecure"
      }]'

# Restart the argocd-server deployment to apply the patch
kubectl rollout restart deployment argocd-server -n argocd

##############################################
# Install custom configuration
##############################################
echo -e "\n[·] Installing custom configs..."
kubectl apply -k ./kubernetes/configs

echo -e "\n[·] Installing apps..."
kubectl apply -k ./kubernetes/apps

##############################################
# Extract Certificates and Trust in Keychain (macOS)
##############################################

echo -e "\n[·] Extracting and trusting certificates..."

# Extract certificates for whoami and traefik (force overwrite if they exist)
# Check if secret exists before extracting the certificate
if kubectl get secret cert-whoami &> /dev/null; then
  kubectl get secret cert-whoami -o jsonpath='{.data.tls\.crt}' | base64 --decode > whoami.crt
else
  echo "Error: secret 'cert-whoami' not found"
  exit 1
fi

# Move certificates to Keychain Access
echo -e "\n[·] Adding certificates to Keychain Access..."

# Add and force trust for whoami certificate
sudo security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db whoami.crt

# Manually force trust setting

##############################################
# Display access details
##############################################
echo -e "\n› Done!"
echo -e "\n[💻] WhoAmI application running on: https://whoami.127.0.0.1.nip.io"
echo -e "[💻] Traefik dashboard accessible at https://traefik.127.0.0.1.nip.io/dashboard/ \n"

echo -e "[💻] Prometheus dashboard accessible at https://prometheus.127.0.0.1.nip.io/ \n"

GRAFANA_PASSWORD=$(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo -e "[💻] Grafana dashboard accessible at https://grafana.127.0.0.1.nip.io/ \n"

echo -e "[💻] Grafana username is: admin"
echo -e "[💻] Grafana password is: $GRAFANA_PASSWORD"

# ArgoCD access details
ARGOCD_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)
echo -e "\n[💻] ArgoCD dashboard accessible at: https://argocd.127.0.0.1.nip.io/"
echo -e "[💻] ArgoCD username is: admin"
echo -e "[💻] ArgoCD password is: $ARGOCD_PASSWORD"
