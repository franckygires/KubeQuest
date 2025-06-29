#!/bin/bash
set -e
#  Création du dossier de log
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"

#  Nom du fichier log avec horodatage
LOG_FILE="$LOG_DIR/deploy-infra-$(date +%Y%m%d_%H%M%S).log"

#  Rediriger la sortie vers le terminal + le fichier
exec > >(tee -a "$LOG_FILE") 2>&1

echo " [$(date)] Déploiement Kubernetes - START"
echo "--------------------------------------------"

echo " Déploiement Ingress NGINX Controller"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

echo " Déploiement Kubernetes Dashboard"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

#  Déploiement via kustomize
DEV_OVERLAY_PATH="../k8s-manifests/overlays/dev"
if [ -d "$DEV_OVERLAY_PATH" ]; then
  echo " Déploiement des composants internes (via kustomize)"
  kubectl apply -k "$DEV_OVERLAY_PATH"
fi

echo " Déploiement Prometheus-Grafana"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

echo " Déploiement Loki Stack"
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update
helm install loki grafana/loki-stack --namespace logging --create-namespace

echo " [$(date)] Déploiement terminé avec succès"
echo "--------------------------------------------"
