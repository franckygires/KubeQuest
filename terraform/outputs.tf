output "master_public_ip" {
  description = "Adresse IP publique du noeud master."
  value       = azurerm_public_ip.pip["master"].ip_address
}

output "master_private_ip" {
  description = "Adresse IP privée du noeud master."
  value       = azurerm_network_interface.nic["master"].private_ip_address
}

output "worker_public_ip" {
  description = "Adresse IP publique du noeud worker."
  value       = azurerm_public_ip.pip["worker"].ip_address
}

output "ssh_command_to_master" {
  description = "Commande pour se connecter en SSH au master."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip["master"].ip_address}"
}

output "ssh_command_to_worker" {
  description = "Commande pour se connecter en SSH au worker."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip["worker"].ip_address}"
}
