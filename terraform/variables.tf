variable "resource_group_name" {
  description = "Le nom du groupe de ressources pour le projet KubeQuest."
  type        = string
  default     = "rg-group-03"
}

variable "location" {
  description = "La région Azure où déployer les ressources."
  type        = string
  default     = "spaincentral"
}

variable "admin_username" {
  description = "Le nom d'utilisateur pour l'accès SSH aux VMs."
  type        = string
  default     = "azureuser"
}

variable "admin_public_key_path" {
  description = "Le chemin vers votre clé publique SSH (ex: ~/.ssh/id_rsa.pub)."
  type        = string
  #   default     = "~/.ssh/id_ed25519.pub "
}
