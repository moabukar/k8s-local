#!/bin/bash

echo -e "\n[BOOTSTRAPPING CLUSTER]\n"

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

# Core repos
add_helm_repo jetstack https://charts.jetstack.io
add_helm_repo traefik https://traefik.github.io/charts
add_helm_repo prometheus-community https://prometheus-community.github.io/helm-charts
add_helm_repo grafana https://grafana.github.io/helm-charts
add_helm_repo argo https://argoproj.github.io/argo-helm

# Additional repos
add_helm_repo minio https://charts.min.io/
add_helm_repo gitlab https://charts.gitlab.io/

helm repo update

##############################################
# Install core helm charts
##############################################

echo -e "\n[·] Installing core helm charts..."

# Function to check if a helm release exists
function helm_release_exists() {
    local release=$1
    local namespace=${2:-default}
    helm status $release -n $namespace >/dev/null 2>&1
    return $?
}

# Install cert-manager if not exists
if ! helm_release_exists cert-manager cert-manager; then
    echo "Installing cert-manager..."
    helm upgrade --install \
        cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --values ./kubernetes/controllers/cert-manager/values.yaml \
        --wait
else
    echo "cert-manager already installed, skipping..."
fi

# Install Traefik if not exists
if ! helm_release_exists traefik default; then
    echo "Installing Traefik..."
    helm upgrade --install \
        traefik traefik/traefik \
        --values ./kubernetes/controllers/traefik/values.yaml \
        --wait
else
    echo "traefik already installed, skipping..."
fi

# Install Prometheus if not exists
if ! helm_release_exists prometheus monitoring; then
    echo "Installing Prometheus..."
    helm upgrade --install \
        prometheus prometheus-community/prometheus \
        --namespace monitoring \
        --create-namespace \
        --wait
else
    echo "prometheus already installed, skipping..."
fi

# Install Grafana if not exists
if ! helm_release_exists grafana monitoring; then
    echo "Installing Grafana..."
    helm upgrade --install \
        grafana grafana/grafana \
        --namespace monitoring \
        --create-namespace \
        --wait
else
    echo "grafana already installed, skipping..."
fi

# Install ArgoCD if not exists
if ! helm_release_exists argocd argocd; then
    echo "Installing ArgoCD..."
    helm upgrade --install \
        argocd argo/argo-cd \
        --namespace argocd \
        --create-namespace \
        --wait
else
    echo "argocd already installed, skipping..."
fi

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
# Install custom configuration and apps
##############################################
echo -e "\n[·] Installing custom configs and apps..."
kubectl create ns gitlab
kubectl create ns kubernetes-dashboard
kubectl apply -k ./kubernetes/configs
kubectl apply -k ./kubernetes/apps

##############################################
# Extract Certificates and Trust in Keychain (macOS)
##############################################
echo -e "\n[·] Extracting and trusting certificates..."

if kubectl get secret cert-whoami &> /dev/null; then
  kubectl get secret cert-whoami -o jsonpath='{.data.tls\.crt}' | base64 --decode > whoami.crt
else
  echo "Error: secret 'cert-whoami' not found"
  exit 1
fi

echo -e "\n[·] Adding certificates to Keychain Access..."
sudo security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db whoami.crt

##############################################
# Display core access details
##############################################
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
ARGOCD_PASSWORD=$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)

echo -e "\n› Core components setup done!"
echo -e "\n[💻] WhoAmI application running on: https://whoami.127.0.0.1.nip.io"
echo -e "[💻] Traefik dashboard accessible at: https://traefik.127.0.0.1.nip.io/dashboard/"
echo -e "[💻] Prometheus dashboard accessible at: https://prometheus.127.0.0.1.nip.io/"
echo -e "[💻] Grafana dashboard accessible at: https://grafana.127.0.0.1.nip.io/"
echo -e "[💻] Grafana username: admin"
echo -e "[💻] Grafana password: $GRAFANA_PASSWORD"
echo -e "[💻] ArgoCD dashboard accessible at: https://argocd.127.0.0.1.nip.io/"
echo -e "[💻] ArgoCD password: $ARGOCD_PASSWORD"

##############################################
# Install Additional Components
##############################################
echo -e "\n[·] Installing Additional Components..."

## 1. Kubernetes Dashboard
echo -e "\n[·] Installing Kubernetes Dashboard..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

echo "Creating dashboard admin ServiceAccount and ClusterRoleBinding..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dashboard-admin
  namespace: kubernetes-dashboard
EOF

echo "Creating IngressRoute for Kubernetes Dashboard..."
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`dashboard.127.0.0.1.nip.io\`)
      kind: Rule
      services:
        - name: kubernetes-dashboard
          port: 8443
  tls:
    certResolver: default
EOF

# ## 2. MinIO
# echo -e "\n[·] Installing MinIO..."
# helm upgrade --install minio minio/minio --namespace minio --create-namespace \
#   --set accessKey=minio,secretKey=minio123 --wait

# echo "Creating IngressRoute for MinIO..."
# cat <<EOF | kubectl apply -f -
# apiVersion: traefik.io/v1alpha1
# kind: IngressRoute
# metadata:
#   name: minio
#   namespace: minio
# spec:
#   entryPoints:
#     - web
#   routes:
#     - match: Host(\`minio.127.0.0.1.nip.io\`)
#       kind: Rule
#       services:
#         - name: minio
#           port: 9000
# EOF

## 3. Istio
echo -e "\n[·] Installing Istio..."
# Make sure istioctl is installed and available in your PATH
istioctl install --set profile=demo -y
echo "Labeling default namespace for Istio sidecar injection..."
kubectl label namespace default istio-injection=enabled --overwrite

## 4. GitLab
echo -e "\n[·] Installing GitLab..."
helm upgrade --install gitlab gitlab/gitlab \
    --namespace gitlab \
    --create-namespace \
    --set global.hosts.domain=127.0.0.1.nip.io \
    --set global.ingress.configureCertmanager=false \
    --set global.ingress.tls.enabled=false \
    --set global.certmanager.install=false \
    --set certmanager.install=false \
    --set global.edition=ce \
    --set gitlab.webservice.minReplicas=1 \
    --set gitlab.webservice.maxReplicas=1 \
    --set gitlab.sidekiq.minReplicas=1 \
    --set gitlab.sidekiq.maxReplicas=1 \
    --set gitlab.gitlab-shell.minReplicas=1 \
    --set gitlab.gitlab-shell.maxReplicas=1 \
    --set postgresql.resources.requests.cpu=200m \
    --set postgresql.resources.requests.memory=256Mi \
    --set redis.resources.requests.cpu=100m \
    --set redis.resources.requests.memory=128Mi \
    --set gitlab.webservice.resources.requests.cpu=200m \
    --set gitlab.webservice.resources.requests.memory=512Mi \
    --set gitlab.sidekiq.resources.requests.cpu=100m \
    --set gitlab.sidekiq.resources.requests.memory=400Mi \
    --set gitlab.gitlab-shell.resources.requests.cpu=100m \
    --set gitlab.gitlab-shell.resources.requests.memory=128Mi \
    --set registry.enabled=false \
    --set prometheus.install=false \
    --set gitlab-runner.install=false \
    --timeout 10m \
    --wait

echo -e "\n[·] Additional components installation complete!"
echo -e "\n[💻] Kubernetes Dashboard: https://dashboard.127.0.0.1.nip.io (use token from 'kubectl -n kubernetes-dashboard create token dashboard-admin')"
echo -e "[💻] MinIO: http://minio.127.0.0.1.nip.io/"
echo -e "[💻] Istio installed (check pods in istio-system namespace)"
echo -e "[💻] GitLab: Access via Ingress (e.g. http://gitlab.127.0.0.1.nip.io/) - configuration may vary"

# K8s dashboard
echo -e "\n[💻] K8s dashboard accessible at: https://dashboard.127.0.0.1.nip.io:8443/"

# GitLab root pass
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 --decode)

echo -e "\n[💻] GitLab accessible at: https://gitlab.127.0.0.1.nip.io:8443/"
echo -e "user: root"
echo -e "password: $GITLAB_PASSWORD"

echo -e "\n› All components have been deployed successfully!"
