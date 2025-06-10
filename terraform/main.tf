terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Référencer le groupe de ressources existant
data "azurerm_resource_group" "rg" {
  name     = "rg-group-03"
}

# Créer un réseau virtuel
resource "azurerm_virtual_network" "vnet" {
  name                = "kubequest-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Créer un sous-réseau
resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Créer une interface réseau pour le maître
resource "azurerm_network_interface" "master_nic" {
  name                = "k8s-master-nic"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.master_ip.id
  }
}

# Créer une IP publique pour le maître
resource "azurerm_public_ip" "master_ip" {
  name                = "k8s-master-ip"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Créer une interface réseau pour le worker
resource "azurerm_network_interface" "worker_nic" {
  name                = "k8s-worker-nic-1"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.worker_ip.id
  }
}

# Créer une IP publique pour le worker
resource "azurerm_public_ip" "worker_ip" {
  name                = "k8s-worker-ip-1"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# Créer la VM maître
resource "azurerm_virtual_machine" "master" {
  name                  = "k8s-master"
  location              = data.azurerm_resource_group.rg.location
  resource_group_name   = data.azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.master_nic.id]
  vm_size               = var.vm_size

  storage_os_disk {
    name              = "k8s-master-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
  publisher = "Canonical"
  offer     = "ubuntu-24_04-lts"
  sku       = "server"
  version   = "latest"
}


  os_profile {
    computer_name  = "k8s-master"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

# Créer la VM worker
resource "azurerm_virtual_machine" "worker" {
  name                  = "k8s-worker-1"
  location              = data.azurerm_resource_group.rg.location
  resource_group_name   = data.azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.worker_nic.id]
  vm_size               = var.vm_size

  storage_os_disk {
    name              = "k8s-worker-1-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_image_reference {
  publisher = "Canonical"
  offer     = "ubuntu-24_04-lts"
  sku       = "server"
  version   = "latest"
}


  os_profile {
    computer_name  = "k8s-worker-1"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}
