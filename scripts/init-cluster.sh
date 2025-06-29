#!/bin/bash
# === KUBEQUEST INIT SCRIPT ===

# === Entrées ===
MASTER_IP=$1
WORKER_IP=$2
ADMIN_USERNAME=$3
ADMIN_PASSWORD=$4
LOG_MASTER="./logs/kube-install-master.log"
LOG_WORKER="./logs/kube-install-worker.log"

# === Préparation ===
mkdir -p ./logs || { echo "[FATAL] Échec création dossier ./logs"; exit 1; }

# === Journalisation ===
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_MASTER"; }
log_worker() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_WORKER"; }

# === Vérification des arguments ===
if [ -z "$MASTER_IP" ] || [ -z "$WORKER_IP" ] || [ -z "$ADMIN_USERNAME" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "Usage: $0 <master_ip> <worker_ip> <admin_username> <admin_password>"
  exit 1
fi

# === Test de connectivité SSH ===
# for ip in "$MASTER_IP" "$WORKER_IP"; do
#   echo "$ADMIN_PASSWORD ssh $ADMIN_USERNAME@$ip"
#   sshpass -p "$ADMIN_PASSWORD" ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$ip" "echo CONNECT_OK" >/dev/null 2>&1 || {
#     echo "[FATAL] SSH inaccessible sur $ip"
#     exit 1
#   }
# done

# === Fonction distante ===
run_ssh() {
  local ip=$1 cmd=$2 log_file=$3
  sshpass -p "$ADMIN_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$ADMIN_USERNAME@$ip" "$cmd" >> "$log_file" 2>&1 || {
    echo "ERREUR: $cmd sur $ip" | tee -a "$log_file"
    exit 1
  }
}

# === Installation des prérequis locaux ===
export DEBIAN_FRONTEND=noninteractive
if ! command -v sshpass &> /dev/null; then
  sudo apt-get update && sudo apt-get install -y sshpass || {
    echo "[FATAL] Échec installation sshpass"
    exit 1
  }
fi

# === Script distant commun pour master & worker ===
INSTALL_SCRIPT=$(cat << 'EOF'
#!/bin/bash
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
exec > >(tee -a /tmp/kube-install.log) 2>&1

log "=== Préparation du système ==="
sudo swapoff -a && sudo sed -i '/ swap / s/^/#/' /etc/fstab
sudo modprobe br_netfilter
sudo tee /etc/modules-load.d/k8s.conf <<< 'br_netfilter'
echo -e "net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system

log "=== Installation Docker & Containerd ==="
sudo apt-get update -y && sudo apt-get install -y apt-transport-https ca-certificates curl lsb-release gnupg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo install -m 0755 -d /etc/apt/keyrings
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker containerd
sudo systemctl start docker containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

log "=== Installation Kubernetes 1.28 ==="
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo tee /etc/apt/keyrings/kubernetes.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/kubernetes.asc
echo "deb [signed-by=/etc/apt/keyrings/kubernetes.asc] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt-get update -y && sudo apt-get install -y kubelet=1.28.0-1.1 kubeadm=1.28.0-1.1 kubectl=1.28.0-1.1
sudo apt-mark hold kubelet kubeadm kubectl

for cmd in docker containerd kubelet kubeadm kubectl; do
  command -v $cmd >/dev/null || { echo "[FATAL] $cmd introuvable"; exit 1; }
done
EOF
)

log "==> Installation sur MASTER ($MASTER_IP)"
echo "$INSTALL_SCRIPT" | run_ssh "$MASTER_IP" "bash -s" "$LOG_MASTER"
log_worker "==> Installation sur WORKER ($WORKER_IP)"
echo "$INSTALL_SCRIPT" | run_ssh "$WORKER_IP" "bash -s" "$LOG_WORKER"

# === Initialisation du master ===
KUBEADM_INIT=$(cat << 'EOF'
#!/bin/bash
sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/containerd/config.toml ~/.kube
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --v=5
mkdir -p $HOME/.kube && sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config
for i in {1..20}; do
  kubectl get nodes >/dev/null && break
  sleep 10
done
TOKEN=$(sudo kubeadm token create --ttl 24h)
CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
MASTER_PRIVATE_IP=$(hostname -I | awk '{print $1}')
cat <<EOF2 | sudo tee /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "$MASTER_PRIVATE_IP:6443"
    token: "$TOKEN"
    caCertHashes: ["sha256:$CA_HASH"]
EOF2
EOF
)

log "==> Initialisation du MASTER"
echo "$KUBEADM_INIT" | run_ssh "$MASTER_IP" "bash -s" "$LOG_MASTER"

# === Installer Flannel ===
log "==> Installation de Flannel"
run_ssh "$MASTER_IP" "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml" "$LOG_MASTER"

# === Transfert et join ===
log "==> Transfert fichier kubeadm-config.yaml"
sshpass -p "$ADMIN_PASSWORD" scp -o StrictHostKeyChecking=no "$ADMIN_USERNAME@$MASTER_IP:/tmp/kubeadm-config.yaml" /tmp/kubeadm-config.yaml
sshpass -p "$ADMIN_PASSWORD" scp -o StrictHostKeyChecking=no /tmp/kubeadm-config.yaml "$ADMIN_USERNAME@$WORKER_IP:/tmp/kubeadm-config.yaml"

log_worker "==> Join WORKER"
run_ssh "$WORKER_IP" "sudo kubeadm reset -f" "$LOG_WORKER"
run_ssh "$WORKER_IP" "sudo systemctl restart containerd" "$LOG_WORKER"
run_ssh "$WORKER_IP" "sudo kubeadm join --config /tmp/kubeadm-config.yaml" "$LOG_WORKER"

log "==> Vérification finale du cluster"
run_ssh "$MASTER_IP" "kubectl get nodes -o wide" "$LOG_MASTER"

# === Redémarrage du master ===
log "Redémarrage automatique du master pour stabiliser les services..."
run_ssh "$MASTER_IP" "sudo reboot" "$LOG_MASTER"

log "=== CLUSTER KUBERNETES INITIALISÉ AVEC SUCCÈS ==="
