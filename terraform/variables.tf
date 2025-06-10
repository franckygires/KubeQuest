variable "location" {
  description = "Région Azure pour les ressources"
  type        = string
  default     = "spaincentral"
}

variable "vm_size" {
  description = "Taille des machines virtuelles"
  type        = string
  default     = "standard_b2ls_v2"
}

variable "admin_username" {
  description = "Nom d’utilisateur admin pour les VM"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "Mot de passe admin pour les VM"
  type        = string
  sensitive   = true
}

variable "subscription_id" {
  description = "ID de la souscription Azure"
  type        = string
  default     = "6b9318b1-2215-418a-b0fd-ba0832e9b333"
}