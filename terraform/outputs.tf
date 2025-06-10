output "resource_group_name" {
  value = data.azurerm_resource_group.rg.name
}

output "master_vm_name" {
  value = azurerm_virtual_machine.master.name
}

output "worker_vm_names" {
  value = azurerm_virtual_machine.worker.name
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}