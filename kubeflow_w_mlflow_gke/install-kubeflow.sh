#!/bin/bash

# Kubeflow Installation Script for GKE
# Install google auth plugin with `sudo apt-get install google-cloud-sdk-gke-gcloud-auth-plugin``

set -e

PROJECT_ID="jamesdv-mlops"
CLUSTER_NAME="kubeflow-mlops"
REGION="us-central1"

echo "Installing Kubeflow on GKE cluster: $CLUSTER_NAME"

# Get cluster credentials
echo "Getting cluster credentials..."
gcloud container clusters get-credentials $CLUSTER_NAME \
    --region $REGION \
    --project $PROJECT_ID

# Install kustomize (required for Kubeflow)
# echo "Installing kustomize..."
# curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
# sudo mv kustomize /usr/local/bin/

# Clone Kubeflow manifests
echo "Cloning Kubeflow manifests..."
if [ ! -d "../../kubeflow/manifests" ]; then
    echo "Must have kubeflow manifests directory" 
    exit
fi

cd ../../kubeflow/manifests

# Install cert-manager
echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

# Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
kubectl wait --for=condition=ready pod -l app=cainjector -n cert-manager --timeout=300s
kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=300s

# Install Istio
echo "Installing Istio..."
cd manifests
kubectl apply -k common/istio-1-17/istio-crds/base | kubectl apply -f -
kubectl apply -k common/istio-1-17/istio-namespace/base | kubectl apply -f -
kubectl apply -k common/istio-1-17/istio-install/base | kubectl apply -f -

# Wait for Istio to be ready
echo "Waiting for Istio to be ready..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s

# Install Dex
echo "Installing Dex..."
kubectl apply -k  common/dex/overlays/istio | kubectl apply -f -

# Install OIDC AuthService
echo "Installing OIDC AuthService..."
kubectl apply -k  common/oidc-authservice/base | kubectl apply -f -

# Install Knative
echo "Installing Knative..."
kubectl apply -k  common/knative/knative-serving/overlays/gateways | kubectl apply -f -
kubectl apply -k  common/istio-1-17/cluster-local-gateway/base | kubectl apply -f -

# Install Kubeflow Namespace
echo "Installing Kubeflow Namespace..."
kubectl apply -k  common/kubeflow-namespace/base | kubectl apply -f -

# Install Kubeflow Roles
echo "Installing Kubeflow Roles..."
kubectl apply -k  common/kubeflow-roles/base | kubectl apply -f -

# Install Kubeflow Istio Resources
echo "Installing Kubeflow Istio Resources..."
kubectl apply -k  common/istio-1-17/kubeflow-istio-resources/base | kubectl apply -f -

# Install Kubeflow Pipelines
echo "Installing Kubeflow Pipelines..."
kubectl apply -k  apps/pipeline/upstream/env/cert-manager/platform-agnostic-multi-user | kubectl apply -f -

# Apply custom database configuration
echo "Applying custom database configuration..."
kubectl apply -f ../kubeflow-deployment.yaml

# Install Katib
echo "Installing Katib..."
kubectl apply -k  apps/katib/upstream/installs/katib-with-kubeflow | kubectl apply -f -

# Install Central Dashboard
echo "Installing Central Dashboard..."
kubectl apply -k  apps/centraldashboard/upstream/overlays/kserve | kubectl apply -f -

# Install Admission Webhook
echo "Installing Admission Webhook..."
kubectl apply -k  apps/admission-webhook/upstream/overlays/cert-manager | kubectl apply -f -

# Install Notebook Controller
echo "Installing Notebook Controller..."
kubectl apply -k  apps/jupyter/notebook-controller/upstream/overlays/kubeflow | kubectl apply -f -

# Install Jupyter Web App
echo "Installing Jupyter Web App..."
kubectl apply -k  apps/jupyter/jupyter-web-app/upstream/overlays/istio | kubectl apply -f -

# Install Profiles + KFAM
echo "Installing Profiles + KFAM..."
kubectl apply -k  apps/profiles/upstream/overlays/kubeflow | kubectl apply -f -

# Install Volumes Web App
echo "Installing Volumes Web App..."
kubectl apply -k  apps/volumes-web-app/upstream/overlays/istio | kubectl apply -f -

# Install Tensorboards Controller
echo "Installing Tensorboards Controller..."
kubectl apply -k  apps/tensorboard/tensorboard-controller/upstream/overlays/kubeflow | kubectl apply -f -

# Install Tensorboards Web App
echo "Installing Tensorboards Web App..."
kubectl apply -k  apps/tensorboard/tensorboards-web-app/upstream/overlays/istio | kubectl apply -f -

# Install Training Operator
echo "Installing Training Operator..."
kubectl apply -k  apps/training-operator/upstream/overlays/kubeflow | kubectl apply -f -

# Install User Namespace
echo "Installing User Namespace..."
kubectl apply -k  common/user-namespace/base | kubectl apply -f -

cd ..

echo "Waiting for all deployments to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment --all -n kubeflow
kubectl wait --for=condition=available --timeout=600s deployment --all -n kubeflow-pipelines || true
kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system

echo "Kubeflow installation completed!"
echo ""
echo "To access Kubeflow UI:"
echo "1. Get the external IP:"
echo "   kubectl get svc istio-ingressgateway -n istio-system"
echo ""
echo "2. Or use port forwarding:"
echo "   kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80"
echo "   Then access: http://localhost:8080"
echo ""
echo "Default credentials:"
echo "   Email: user@example.com"
echo "   Password: 12341234"