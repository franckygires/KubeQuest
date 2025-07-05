#!/bin/bash

# Arrête le script immédiatement si une commande échoue.
set -e

# --- Configuration du Logging ---
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bootstrap-$(date +'%Y-%m-%d_%H-%M-%S').log"
exec > >(tee -i "${LOG_FILE}") 2>&1
# -----------------------------------------------------------------------------

echo "--- Démarrage du Bootstrap K3s (Journalisation activée) ---"
echo "Fichier de log : ${LOG_FILE}"

# --- Configuration ---
cd "$(dirname "$0")"
ADMIN_USER="azureuser"
TERRAFORM_DIR="../terraform"

# --- Étape 0: Lire les outputs de Terraform ---
echo -e "\n>>> Lecture des informations depuis Terraform..."
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "Erreur: Le répertoire terraform '$TERRAFORM_DIR' n'a pas été trouvé."
    exit 1
fi
MASTER_IP=$(terraform -chdir=$TERRAFORM_DIR output -raw master_public_ip)
WORKER_IP=$(terraform -chdir=$TERRAFORM_DIR output -raw worker_public_ip)
MASTER_PRIVATE_IP=$(terraform -chdir=$TERRAFORM_DIR output -raw master_private_ip)
if [ -z "$MASTER_IP" ] || [ -z "$WORKER_IP" ] || [ -z "$MASTER_PRIVATE_IP" ]; then
    echo "Erreur: Impossible de récupérer les adresses IP depuis Terraform."
    exit 1
fi
echo "Master IP (Public): $MASTER_IP"
echo "Master IP (Private): $MASTER_PRIVATE_IP"
echo "Worker IP (Public): $WORKER_IP"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# --- Étape 1: Installation sur le Master ---
echo -e "\n>>> Installation de K3s sur le master ($MASTER_IP)..."
# LA LIGNE IMPORTANTE A ÉTÉ MODIFIÉE CI-DESSOUS
ssh $SSH_OPTS ${ADMIN_USER}@${MASTER_IP} <<EOF
set -e
echo "Installation des dépendances..."
sudo apt-get update && sudo apt-get install -y curl
echo "Lancement du script d'installation K3s..."
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --node-ip ${MASTER_PRIVATE_IP} \
  --write-kubeconfig-mode 644 \
  --tls-san ${MASTER_IP}
EOF
echo ">>> Master installé."

# --- Étape 2: Récupération du Token ---
echo -e "\n>>> Récupération du token depuis le master..."
K3S_TOKEN=$(ssh $SSH_OPTS ${ADMIN_USER}@${MASTER_IP} 'sudo cat /var/lib/rancher/k3s/server/node-token')
if [ -z "$K3S_TOKEN" ]; then
    echo "Erreur: Le token K3s est vide."
    exit 1
fi
echo "Token récupéré avec succès."

# --- Étape 3: Installation sur le Worker ---
echo -e "\n>>> Installation de K3s sur le worker ($WORKER_IP)..."
ssh $SSH_OPTS ${ADMIN_USER}@${WORKER_IP} <<EOF
set -e
echo "Installation des dépendances..."
sudo apt-get update && sudo apt-get install -y curl
echo "Lancement du script d'installation K3s agent..."
curl -sfL https://get.k3s.io | K3S_URL=https://$(echo $MASTER_PRIVATE_IP):6443 K3S_TOKEN='$(echo $K3S_TOKEN)' sh -
EOF
echo ">>> Worker installé et en cours de connexion."

# --- Étape 4: Récupération du Kubeconfig ---
echo -e "\n>>> Récupération et configuration du fichier kubeconfig..."
KUBECONFIG_PATH="${HOME}/.kube/config"
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
ssh $SSH_OPTS ${ADMIN_USER}@${MASTER_IP} "sudo cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/${MASTER_IP}/" > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"
echo "Kubeconfig a été installé dans $KUBECONFIG_PATH"

# --- Étape 5: Vérification finale ---
echo -e "\n>>> Vérification du statut des noeuds (attente de 20 secondes)..."
sleep 20
kubectl get nodes -o wide

echo -e "\n--- Bootstrap Terminé avec Succès ---"