# **KubeQuest : Déploiement d'une Stack Applicative sur Kubernetes**

## 1\. Présentation Générale

Ce projet met en œuvre le déploiement complet d'une application web et de son écosystème sur un cluster Kubernetes. L'objectif est de migrer une application initialement conçue pour `docker-compose` vers une architecture "cloud-native", robuste et observable, le tout de manière automatisée.

L'infrastructure est provisionnée sur Microsoft Azure et le cluster est motorisé par **K3s**, une distribution Kubernetes légère et certifiée. Le déploiement inclut une stack d'observabilité complète avec Prometheus pour le monitoring et Loki pour la journalisation, un Ingress Controller NGINX pour la gestion du trafic entrant, ainsi que l'application web elle-même, packagée via un Chart Helm.

### Schéma d'Architecture Final

```
                           +-------------------------------------------------+
    Utilisateur --> Navigateur --> Internet --> |          AZURE (IP Publique du Worker)          |
                           +----------------|---------------------------------+
                                            | (Port 80/443, via NSG)
                           +----------------v---------------------------------+
    Cluster K3s            |         NGINX Ingress Controller (Pod)          |
    sur VM Worker          +----------------|---------------------------------+
                                            | (Routage basé sur webapp.kubequest.local)
                           +----------------v---------------------------------+
                           |          Service "web-app" (ClusterIP)          |
                           +----------------|---------------------------------+
                                            | (Selector: app=web-app)
           +--------------------------------v---------------------------------+
           |                    Pod "web-app" (Deployment)                     |
           | +--------------------------+ +---------------------------------+ |
           | | Init Container           | | Main Container                  | |
           | | (composer, migrate, ...) | | (NGINX + PHP-FPM)               | |
           | +--------------------------+ +---------------------------------+ |
           +--------------------------------|---------------------------------+
                                            | (Connexion via Service "web-app-mysql")
                           +----------------v---------------------------------+
                           |      Pod "web-app-mysql" (StatefulSet)          |
                           | (Géré par le Chart Helm de Bitnami)             |
                           +----------------|---------------------------------+
                                            | (Stockage sur Volume Persistant)
                           +----------------v---------------------------------+
                           |        PersistentVolumeClaim (5Go)              |
                           +-------------------------------------------------+
```

---

## 2\. Guide de Déploiement de A à Z

Ce guide permet de recréer l'intégralité de l'environnement sur un nouveau poste.

### Prérequis

Assurez-vous d'avoir les outils suivants installés sur votre machine locale :

- `git`
- `az` (Azure CLI)
- `terraform` (v1.x)
- `kubectl` (v1.28+)
- `helm` (v3.x)

### Procédure d'Installation

1.  **Configuration initiale :**

    - Clonez ce dépôt Git.
    - Connectez-vous à votre compte Azure avec `az login`.
    - Assurez-vous d'avoir une clé SSH disponible à `~/.ssh/id_rsa.pub` ou modifiez le chemin dans la commande `terraform apply`.

2.  **Lancer les scripts de déploiement dans l'ordre :**

    - **Étape A : Créer l'infrastructure sur Azure**

      - _Rôle :_ Crée les 2 VMs (master/worker), le réseau, et les règles de pare-feu.

      <!-- end list -->

      ```bash
      cd terraform
      terraform apply -var="admin_public_key_path=~/.ssh/id_rsa.pub"
      ```

    - **Étape B : Installer et configurer le cluster K3s**

      - _Rôle :_ Installe K3s sur les VMs et configure votre `kubectl` local.

      <!-- end list -->

      ```bash
      cd .. # Revenir à la racine du projet
      ./scripts/bootstrap-k3s.sh
      ```

    - **Étape C : Déployer les services d'infrastructure**

      - _Rôle :_ Déploie NGINX, Prometheus, Grafana, Loki et le Dashboard.

      <!-- end list -->

      ```bash
      ./scripts/deploy-infra.sh
      ```

    - **Étape D : Déployer l'application web**

      - _Rôle :_ Déploie le Chart Helm de l'application et sa base de données.

      <!-- end list -->

      ```bash
      ./scripts/deploy-app.sh
      ```

---

## 3\. Guide d'Utilisation

Une fois le déploiement terminé, voici comment accéder aux différents services.

### Accéder à l'Application Web

1.  **Récupérer l'adresse IP du worker :**
    ```bash
    terraform -chdir=./terraform output -raw worker_public_ip
    ```
2.  **Modifier votre fichier `hosts` local** (avec `sudo` sur Linux/macOS, ou en tant qu'administrateur sur Windows) et y ajouter la ligne :
    ```
    <IP_DU_WORKER> webapp.kubequest.local
    ```
3.  **Ouvrez votre navigateur** à l'adresse : `http://webapp.kubequest.local`

### Accéder à Grafana (Monitoring)

1.  **Récupérer le mot de passe admin :**
    ```bash
    kubectl -n monitoring get secret prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
    ```
2.  **Créer un tunnel de connexion :**
    ```bash
    kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
    ```
3.  **Ouvrez votre navigateur** à l'adresse : `http://localhost:3000` (login: `admin`, avec le mot de passe récupéré).

### Accéder au Kubernetes Dashboard

1.  **Récupérer le token de connexion :**
    ```bash
    kubectl -n kubernetes-dashboard create token admin-user
    ```
2.  **Lancer le proxy d'accès :**
    ```bash
    kubectl proxy
    ```
3.  **Ouvrez l'URL** suivante dans votre navigateur et connectez-vous avec le token : `http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/`

---

## 4\. Analyse Technique et Retour d'Expérience

Cette section détaille les décisions techniques prises et les défis surmontés au cours du projet.

### Justification des Choix Techniques

- **Pourquoi K3s plutôt qu'un Kubernetes standard ?**
  La contrainte principale du projet était l'utilisation de VMs Azure de petite taille (`Standard_B2ls_v2`). Une installation Kubernetes standard avec `kubeadm` se serait avérée trop gourmande en ressources. Le choix de **K3s**, une distribution légère et certifiée par la CNCF, a été une décision stratégique pour garantir une stabilité maximale du cluster dans cet environnement contraint, tout en conservant toutes les fonctionnalités nécessaires.

- **Pourquoi une approche "hybride" Helm / Kustomize ?**
  L'objectif initial était de tout gérer via Kustomize, y compris les charts Helm. Cependant, nous avons fait face à des **conflits de versions** et des bugs entre l'outil `kustomize`, sa bibliothèque interne utilisée par `kubectl`, et l'outil `helm`. Pour fiabiliser le déploiement, la stratégie a été d'utiliser **chaque outil pour sa force principale** :

  - **Helm** pour gérer le cycle de vie des applications complexes (Prometheus, Loki, notre application).
  - **Kustomize** pour les manifestes YAML plus simples (Dashboard, NGINX).
    Cette séparation a rendu les scripts de déploiement plus robustes et plus clairs.

### Défis Rencontrés et Solutions

Ce projet fut un parcours de débogage complet, qui a permis de surmonter les défis suivants :

- **Instabilité du Cluster :** Résolue par le passage à **K3s**.
- **Conflits de Déploiement :** Résolus par la **séparation des logiques Helm et Kustomize** et la mise en place d'un déploiement en plusieurs étapes (CRDs d'abord, puis le reste).
- **Erreurs de Connectivité (404 Not Found) :** Résolues par un débogage systématique de toute la chaîne de connexion : configuration du **fichier `hosts` local**, ajout de **règles au pare-feu Azure (NSG)**, correction de l'**`Ingress Class`**, et vérification de la liaison **Service-Endpoints-Pod**.
- **Crashs Applicatifs (`CrashLoopBackOff` / Erreur 500) :** Résolus en entrant directement dans le conteneur (`kubectl exec`) pour trouver les erreurs applicatives réelles, qui étaient dues à un **chemin d'exécutable PHP incorrect**, à des **permissions de fichiers** manquantes, et enfin à un **mot de passe de base de données** qui n'était pas correctement transmis entre les charts Helm.

### Fonctionnalités Non Implémentées et Justifications

- **Système de Sauvegarde (Velero) :** Une tentative d'installation de Velero avec un stockage interne MinIO a été effectuée. Le déploiement de MinIO a échoué en raison d'un manque de mémoire (`Insufficient memory`) sur le nœud worker. La décision a été prise de **ne pas implémenter cette fonctionnalité** afin de préserver la stabilité de l'environnement et de se concentrer sur un déploiement applicatif 100% fonctionnel.
- **Sécurité Avancée (OPA / Dex) :** De la même manière, l'ajout d'OPA Gatekeeper et de Dex, bien que pertinent, aurait ajouté une charge supplémentaire sur le CPU et la mémoire. Face aux contraintes matérielles, la priorité a été donnée à la finalisation d'un socle applicatif stable. Ces fonctionnalités de sécurité constituent une piste d'amélioration logique pour ce projet sur une infrastructure plus conséquente.
