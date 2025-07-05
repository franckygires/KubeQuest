terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Indique à Terraform de LIRE les informations d'un groupe de ressources EXISTANT
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# Crée un réseau virtuel (VNet) pour nos VMs
# Notez que .location et .name pointent maintenant vers "data.azurerm_resource_group.rg"
resource "azurerm_virtual_network" "vnet" {
  name                = "kubequest-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Crée un sous-réseau à l'intérieur du VNet
resource "azurerm_subnet" "subnet" {
  name                 = "kubequest-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Crée un groupe de sécurité réseau (pare-feu)
resource "azurerm_network_security_group" "nsg" {
  name                = "kubequest-nsg"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" # Pour le projet. En production, limitez à votre IP.
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowK3sApi"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "*" # Pour le projet. En production, limitez à votre IP.
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*" # Pour le projet. En production, limitez à votre IP.
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*" # Pour le projet. En production, limitez à votre IP.
    destination_address_prefix = "*"
  }
}

# Boucle pour créer les IPs, les cartes réseau et les VMs
locals {
  nodes = {
    "master" = {}
    "worker" = {}
  }
}

resource "azurerm_public_ip" "pip" {
  for_each            = local.nodes
  name                = "kubequest-${each.key}-pip"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static" # IP Statique
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  for_each            = local.nodes
  name                = "kubequest-${each.key}-nic"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[each.key].id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  for_each                  = local.nodes
  network_interface_id      = azurerm_network_interface.nic[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each              = local.nodes
  name                  = "kubequest-${each.key}"
  resource_group_name   = data.azurerm_resource_group.rg.name
  location              = data.azurerm_resource_group.rg.location
  size                  = "Standard_B2ls_v2"
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]

  # Configuration de l'authentification par clé SSH
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.admin_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Image Ubuntu Server 22.04 LTS, légère et supportée
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
