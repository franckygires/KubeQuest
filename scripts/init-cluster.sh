#!/bin/bash
# Script pour initialiser un cluster Kubernetes avec kubeadm sur 2 VM
# Version optimisée avec méthodes alternatives pour Docker et Kubernetes

MASTER_IP=$1
WORKER_IP=$2
ADMIN_USERNAME=$3
ADMIN_PASSWORD=$4
LOG_MASTER="kube-install-master.log"
LOG_WORKER="kube-install-worker.log"

# Fonctions de journalisation
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_MASTER"; }
log_worker() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_WORKER"; }

# Vérification des arguments
if [ -z "$MASTER_IP" ] || [ -z "$WORKER_IP" ] || [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
  log "Erreur : Usage: $0 <master_ip> <worker_ip> <admin_username> <admin_password>"
  exit 1
fi

# Fonction SSH avec timeout
run_ssh() {
  local ip=$1 cmd=$2 log_file=$3
  sshpass -p "$ADMIN_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20 "$ADMIN_USERNAME@$ip" "$cmd" >> "$log_file" 2>&1 || {
    echo "ERREUR: Échec de '$cmd' sur $ip" | tee -a "$log_file"
    exit 1
  }
}

# Désactiver interactions GPG/apt
export DEBIAN_FRONTEND=noninteractive

# Installation de sshpass
if ! command -v sshpass &> /dev/null; then
  log "Installation de sshpass..."
  sudo apt-get update && sudo apt-get install -y sshpass || {
    log "Échec de l'installation de sshpass"
    exit 1
  }
fi

# Script d'installation commun
INSTALL_SCRIPT=$(cat << 'EOF'
#!/bin/bash
LOG_FILE="/tmp/kube-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "=== Début de l'installation ==="

# Vérifier connectivité
log "Vérification réseau"
ping -c 4 google.com || log "Avertissement : Ping google.com échoué"
curl -s -I https://pkgs.k8s.io || log "Avertissement : Accès pkgs.k8s.io échoué"
curl -s -I https://download.docker.com || log "Avertissement : Accès download.docker.com échoué"

# Désactivation du swap
log "Désactivation swap"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Activation bridge networking
log "Activation bridge-nf-call-iptables"
sudo modprobe br_netfilter
echo "1" | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Installer pré-requis
log "Installation dépendances"
sudo apt-get update -y && sudo apt-get install -y apt-transport-https ca-certificates curl lsb-release

# Installer Docker (méthode alternative sans GPG)
log "Installation Docker"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null || {
  log "Erreur : Échec téléchargement clé Docker"
  exit 1
}
sudo chmod a+r /etc/apt/keyrings/docker.asc

log "Ajout dépôt Docker"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || {
  log "Erreur : Échec dépôt Docker"
  exit 1
}

sudo apt-get update -y && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
  log "Erreur : Échec installation Docker"
  exit 1
}
sudo systemctl enable docker containerd
sudo systemctl start docker containerd

# Configurer containerd
log "Configuration containerd"
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# Create crictl.yaml file
log "Création du fichier crictl.yaml"
cat <<EOF2 | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF2

# Installer Kubernetes (méthode alternative sans GPG)
log "Installation Kubernetes"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo tee /etc/apt/keyrings/kubernetes.asc > /dev/null || {
  log "Erreur : Échec clé Kubernetes"
  exit 1
}
sudo chmod a+r /etc/apt/keyrings/kubernetes.asc

log "Ajout dépôt Kubernetes"
echo "deb [signed-by=/etc/apt/keyrings/kubernetes.asc] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null || {
  log "Erreur : Échec dépôt Kubernetes"
  exit 1
}

# Add --allow-change-held-packages to apt-get install for Kubernetes packages
log "Installation de Kubernetes avec autorisation de rétrogradation et changement de paquets retenus"
sudo apt-get update -y && sudo apt-get install -y --allow-downgrades --allow-change-held-packages kubelet=1.28.0-1.1 kubeadm=1.28.0-1.1 kubectl=1.28.0-1.1 || {
  log "Erreur : Échec installation Kubernetes avec autorisation de rétrogradation et changement de paquets retenus"
  exit 1
}
sudo apt-mark hold kubelet kubeadm kubectl

log "=== Installation terminée ==="
EOF
)

# Installation sur le maître
log "Installation sur le master ($MASTER_IP)"
echo "$INSTALL_SCRIPT" | run_ssh "$MASTER_IP" "bash -s" "$LOG_MASTER" || {
  log "Échec de l'installation sur le master"
  exit 1
}

# Installation sur le worker
log_worker "Installation sur le worker ($WORKER_IP)"
echo "$INSTALL_SCRIPT" | run_ssh "$WORKER_IP" "bash -s" "$LOG_WORKER" || {
  log_worker "Échec de l'installation sur le worker"
  exit 1
}

# Initialisation du cluster
log "Initialisation du cluster Kubernetes"
KUBEADM_INIT=$(cat << 'EOF'
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d /etc/kubernetes /var/lib/etcd
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --v=5
test -f /etc/kubernetes/pki/ca.crt || { echo "Erreur : Certificat CA manquant"; exit 1; }
EOF
)

echo "$KUBEADM_INIT" | run_ssh "$MASTER_IP" "bash -s" "$LOG_MASTER" || {
  log "Échec de l'initialisation du cluster"
  run_ssh "$MASTER_IP" "journalctl -u kubelet --no-pager | tail -n 100" "$LOG_MASTER"
  exit 1
}

# Configuration de kubectl
log "Configuration de kubectl sur le master"
run_ssh "$MASTER_IP" "mkdir -p \$HOME/.kube && sudo cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config" "$LOG_MASTER" || {
  log "Erreur : Échec de la configuration de kubectl"
  exit 1
}

# Vérification de la connectivité réseau
log "Vérification de la connectivité réseau au nœud maître"
run_ssh "$WORKER_IP" "nc -zv $MASTER_IP 6443" "$LOG_WORKER" || {
  log_worker "Erreur : Échec de la connectivité réseau au nœud maître"
  exit 1
}

# Installation du réseau Flannel
log "Installation de Flannel"
run_ssh "$MASTER_IP" "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml" "$LOG_MASTER" || {
  log "Erreur : Échec de l'installation de Flannel"
  exit 1
}

# Génération robuste de la commande join
log "Génération de la commande join"
MAX_RETRIES=5
RETRY_DELAY=15
JOIN_CMD=""

for i in $(seq 1 $MAX_RETRIES); do
  log "Tentative $i/$MAX_RETRIES de génération du token"
  run_ssh "$MASTER_IP" "kubectl get nodes >/dev/null 2>&1" "$LOG_MASTER" || {
    log "API server pas encore prêt, attente de $RETRY_DELAY secondes..."
    sleep $RETRY_DELAY
    continue
  }
  JOIN_CMD=$(run_ssh "$MASTER_IP" "sudo kubeadm token create --ttl 24h --print-join-command" "$LOG_MASTER")
  if [ -n "$JOIN_CMD" ] && echo "$JOIN_CMD" | grep -q "kubeadm join"; then
    log "Commande join générée avec succès"
    break
  fi
  log "Échec de la génération du token, attente $RETRY_DELAY secondes"
  sleep $RETRY_DELAY
done

if [ -z "$JOIN_CMD" ]; then
  log "Génération alternative du token..."
  run_ssh "$MASTER_IP" "test -f /etc/kubernetes/pki/ca.crt" "$LOG_MASTER" || {
    log "Erreur : Certificat CA /etc/kubernetes/pki/ca.crt manquant"
    exit 1
  }
  CERT_HASH=$(run_ssh "$MASTER_IP" "sudo openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | awk '{print \$2}'" "$LOG_MASTER")
  [ -z "$CERT_HASH" ] && { log "Erreur : Échec extraction hash CA"; exit 1; }
  TOKEN=$(run_ssh "$MASTER_IP" "sudo kubeadm token generate" "$LOG_MASTER")
  [ -z "$TOKEN" ] && { log "Erreur : Échec génération token"; exit 1; }
  JOIN_CMD="kubeadm join $MASTER_IP:6443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$CERT_HASH"
fi

log "Commande join : $JOIN_CMD"

# Ajout robuste du worker
log_worker "Ajout du worker au cluster"
MAX_JOIN_RETRIES=3
JOIN_SUCCESS=false

for i in $(seq 1 $MAX_JOIN_RETRIES); do
  log_worker "Tentative $i/$MAX_JOIN_RETRIES"
  run_ssh "$WORKER_IP" "sudo kubeadm reset -f" "$LOG_WORKER"
  sleep 5
  run_ssh "$WORKER_IP" "sudo $JOIN_CMD" "$LOG_WORKER" && {
    JOIN_SUCCESS=true
    break
  }
  log_worker "Échec de la tentative $i, attente de 30 secondes..."
  sleep 30
done

if ! $JOIN_SUCCESS; then
  log_worker "Échec critique de l'ajout du worker après $MAX_JOIN_RETRIES tentatives"
  exit 1
fi

# Vérification finale
log "Vérification de l'état du cluster..."
run_ssh "$MASTER_IP" "
for i in {1..20}; do
  if kubectl get nodes | grep -q '$WORKER_IP'; then
    echo 'Worker détecté dans le cluster'
    kubectl get nodes -o wide
    exit 0
  fi
  sleep 10
  echo 'En attente du worker... ($i/20)'
done
echo 'Timeout en attente du worker'
exit 1
" "$LOG_MASTER" || {
  log "Échec : le worker n'a pas rejoint le cluster"
  exit 1
}

# Copier kubeconfig localement
log "Copie kubeconfig"
sshpass -p "$ADMIN_PASSWORD" scp -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$MASTER_IP":~/.kube/config ~/.kube/config && kubectl get nodes >> "$LOG_MASTER" 2>&1 || log "Erreur : Échec copie kubeconfig"

log "=== Cluster Kubernetes initialisé avec succès ==="