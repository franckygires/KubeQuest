#!/bin/bash
set -e
# On se place à la racine du projet
cd "$(dirname "$0")/.."

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-app-$(date +'%Y-%m-%d_%H-%M-%S').log"
exec > >(tee -i "${LOG_FILE}") 2>&1

echo "--- Déploiement de l'application Web (Journalisation activée) ---"
echo "Fichier de log : ${LOG_FILE}"

if ! command -v kubectl &> /dev/null || ! command -v helm &> /dev/null; then
    echo "Erreur: 'kubectl' et 'helm' doivent être installés."
    exit 1
fi

echo -e "\n>>> Vérification de la connexion au cluster..."
kubectl cluster-info

# --- Étape 1: Mise à jour des dépendances Helm ---
echo -e "\n>>> Étape 1: Mise à jour des dépendances du chart (MySQL)..."
# Cette commande télécharge le chart MySQL dans le dossier 'charts' de notre web-app
helm dependency update ./application/web-app/
echo "Dépendances mises à jour."

# --- Étape 2: Déploiement de l'application avec Helm ---
echo -e "\n>>> Étape 2: Déploiement/Mise à jour de la release 'web-app'..."
# La commande 'helm upgrade --install' installe le chart s'il n'existe pas,
# ou le met à jour s'il existe déjà. C'est la commande standard.
helm upgrade --install web-app ./application/web-app/ \
  --namespace default

echo -e "\n>>> Déploiement initié."
echo "La création des pods peut prendre quelques minutes."
echo "Pour suivre : kubectl get pods --watch"
echo "Pour accéder à l'application, n'oubliez pas de modifier votre fichier /etc/hosts pour faire pointer webapp.kubequest.local vers l'IP de votre worker."
echo -e "\n--- Fin du script de déploiement ---"