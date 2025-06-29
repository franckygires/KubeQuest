#!/bin/bash
# Script pour nettoyer les VM Kubernetes (k8s-master, k8s-worker-1) dans rg-group-03
# Usage: ./cleanup-vms.sh <master_ip> <worker_ip> <admin_username> <admin_password>
# Exemple: ./cleanup-vms.sh 20.71.123.45 68.221.132.245 azureadmin P@ssw0rd1234!
# Logs: ./cleanup-master.log, ./cleanup-worker.log

MASTER_IP=$1
WORKER_IP=$2
ADMIN_USERNAME=$3
ADMIN_PASSWORD=$4
LOG_MASTER="./logs/cleanup-master.log"
LOG_WORKER="./logs/cleanup-worker.log"

# Fonctions de journalisation
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_MASTER"; }
log_worker() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_WORKER"; }

# Vérification des arguments
if [ -z "$MASTER_IP" ] || [ -z "$WORKER_IP" ] || [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
  log "Erreur : Usage: $0 <master_ip> <worker_ip> <admin_username> <admin_password>"
  exit 1
fi

# Fonction SSH
run_ssh() {
  local ip=$1 cmd=$2 log_file=$3
  sshpass -p "$ADMIN_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$ADMIN_USERNAME@$ip" "$cmd" >> "$log_file" 2>&1 || {
    echo "Erreur : Échec de '$cmd' sur $ip" | tee -a "$log_file"
    exit 1
  }
}

# Installer sshpass localement
if ! command -v sshpass &> /dev/null; then
  log "Installation de sshpass..."
  sudo apt-get update && sudo apt-get install -y sshpass || { log "Échec installation sshpass"; exit 1; }
fi

# Script de nettoyage commun
CLEANUP_SCRIPT=$(cat << 'EOF'
#!/bin/bash
LOG_FILE="/tmp/cleanup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
 
log "Démarrage nettoyage"

# Réinitialiser Kubernetes
log "Réinitialisation Kubernetes"
sudo kubeadm reset -f || log "Avertissement : kubeadm reset échoué"
sudo rm -rf /etc/kubernetes /var/lib/etcd /etc/cni/net.d /var/lib/kubelet ~/.kube

# Désinstaller Kubernetes
log "Désinstallation Kubernetes"
sudo apt-get purge -y kubelet kubeadm kubectl || log "Avertissement : Désinstallation Kubernetes échoué"
sudo rm -f /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes.gpg

# Désinstaller Docker
log "Désinstallation Docker"
sudo systemctl stop docker containerd || true
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || log "Avertissement : Désinstallation Docker échoué"
sudo rm -rf /var/lib/docker /etc/docker /etc/containerd /etc/apt/keyrings/docker.gpg /etc/apt/sources.list.d/docker.list

# Desinstaller flannel
log "Désinstallation Flannel"
sudo rm -rf /etc/cni/net.d/10-flannel.conflist /opt/cni/bin/flannel || log "Avertissement : Désinstallation Flannel échoué"
# Désinstaller kube-proxy
log "Désinstallation kube-proxy"
sudo rm -rf /var/lib/kube-proxy || log "Avertissement : Désinstallation kube-proxy échoué"
# Désinstaller cri-dockerd
log "Désinstallation cri-dockerd"
sudo apt-get purge -y cri-dockerd || log "Avertissement : Désinstallation cri-dockerd échoué"

# Nettoyer paquets résiduels
log "Nettoyage paquets"
sudo apt-get autoremove -y && sudo apt-get autoclean -y

# Réactiver swap (si nécessaire)
log "Réactivation swap"
sudo sed -i '/ swap / s/^#\(.*\)$/\1/' /etc/fstab || true
sudo swapon -a || true

# Redémarrer services
log "Redémarrage services"
sudo systemctl daemon-reload
sudo systemctl restart networking || true

log "Nettoyage terminé"
EOF
)

# Nettoyage maître
log "Nettoyage maître ($MASTER_IP)"
echo "$CLEANUP_SCRIPT" | run_ssh "$MASTER_IP" "bash -s" "$LOG_MASTER"

# Nettoyage worker
log_worker "Nettoyage worker ($WORKER_IP)"
echo "$CLEANUP_SCRIPT" | run_ssh "$WORKER_IP" "bash -s" "$LOG_WORKER"

log "Nettoyage des VM terminé"