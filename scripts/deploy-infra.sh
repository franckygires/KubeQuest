#!/bin/bash
set -e
# On se place à la racine du projet
cd "$(dirname "$0")/.."

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-infra-$(date +'%Y-%m-%d_%H-%M-%S').log"
exec > >(tee -i "${LOG_FILE}") 2>&1

echo "--- Déploiement des services d'infrastructure (Journalisation activée) ---"
echo "Fichier de log : ${LOG_FILE}"

# # --- ÉTAPE 0: Nettoyage Préalable des Ressources Conflictuelles ---
# echo -e "\n--- ÉTAPE 0: Nettoyage Préalable ---"
# # L'option --ignore-not-found=true évite les erreurs si les ressources n'existent pas

# echo "Suppression des namespaces (s'ils existent)..."
# kubectl delete namespace monitoring --ignore-not-found=true
# kubectl delete namespace loki --ignore-not-found=true

# echo "Suppression des ClusterRoles et ClusterRoleBindings orphelins (s'ils existent)..."
# kubectl delete clusterrole prometheus-grafana-clusterrole --ignore-not-found=true
# kubectl delete clusterrole prometheus-kube-state-metrics --ignore-not-found=true
# kubectl delete clusterrole prometheus-kube-prometheus-operator --ignore-not-found=true
# kubectl delete clusterrole prometheus-kube-prometheus-admission --ignore-not-found=true
# kubectl delete clusterrolebinding prometheus-grafana-clusterrolebinding --ignore-not-found=true
# kubectl delete clusterrolebinding prometheus-kube-state-metrics --ignore-not-found=true
# kubectl delete clusterrolebinding prometheus-kube-prometheus-operator --ignore-not-found=true
# kubectl delete clusterrolebinding prometheus-kube-prometheus-admission --ignore-not-found=true

# echo "Nettoyage terminé."

if ! command -v kubectl &> /dev/null || ! command -v helm &> /dev/null; then
    echo "Erreur: 'kubectl' et 'helm' doivent être installés."
    exit 1
fi

echo -e "\n>>> Vérification de la connexion au cluster..."
kubectl cluster-info

# --- ÉTAPE 1: Mise à jour des dépôts Helm ---
echo -e "\n--- ÉTAPE 1: Mise à jour des dépôts Helm ---"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# --- ÉTAPE 2: Installation des CRDs de Prometheus ---
echo -e "\n--- ÉTAPE 2: Installation des CRDs de Prometheus ---"
OPERATOR_VERSION="v0.73.2"
BASE_URL="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${OPERATOR_VERSION}/example/prometheus-operator-crd"
CRDS=(
  "monitoring.coreos.com_alertmanagerconfigs.yaml"
  "monitoring.coreos.com_alertmanagers.yaml"
  "monitoring.coreos.com_podmonitors.yaml"
  "monitoring.coreos.com_probes.yaml"
  "monitoring.coreos.com_prometheuses.yaml"
  "monitoring.coreos.com_prometheusrules.yaml"
  "monitoring.coreos.com_servicemonitors.yaml"
  "monitoring.coreos.com_thanosrulers.yaml"
)

for crd in "${CRDS[@]}"; do
  echo "Application de la CRD: $crd"
  kubectl apply -f "${BASE_URL}/${crd}" --server-side
done
echo "CRDs de Prometheus installés."

echo -e "\n>>> Attente de 30 secondes pour que les CRDs soient reconnus par le cluster..."
sleep 30

# --- ÉTAPE 3: Création des Namespaces ---
echo -e "\n--- ÉTAPE 3: Création des Namespaces ---"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace loki --dry-run=client -o yaml | kubectl apply -f -
echo "Namespaces 'monitoring' et 'loki' créés ou déjà existants."

# --- ÉTAPE 4: Déploiement de NGINX & Dashboard via Kustomize ---
echo -e "\n--- ÉTAPE 4: Déploiement de NGINX & Dashboard via Kustomize ---"
kubectl apply -k ./infrastructure/overlays/production/
echo "NGINX et Dashboard déployés."

# --- ÉTAPE 5: Déploiement de Prometheus & Loki via Helm ---
echo -e "\n--- ÉTAPE 5: Déploiement de Prometheus & Loki via Helm ---"
echo "Déploiement de kube-prometheus-stack..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --version "75.6.1" \
  --namespace monitoring \
  -f ./infrastructure/overlays/production/prometheus-values.yaml

echo "Déploiement de Loki..."
helm upgrade --install loki grafana/loki \
  --version "6.6.2" \
  --namespace loki \
  -f ./infrastructure/overlays/production/loki-values.yaml

echo -e "\n>>> Déploiement terminé."
echo "La création de tous les pods peut prendre plusieurs minutes."
echo "Utilisez 'kubectl get pods -A --watch' pour suivre la progression."