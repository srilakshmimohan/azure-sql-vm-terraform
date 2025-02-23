terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "demo-rg" {
  name     = "demo-resources"
  location = "UkSouth"
  tags = {
    environment = "dev"
  }

}

resource "azurerm_virtual_network" "demo-vn" {
  name                = "demo-vn"
  resource_group_name = azurerm_resource_group.demo-rg.name
  location            = azurerm_resource_group.demo-rg.location
  address_space       = ["10.123.0.0/16"]
  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "demo-subnet" {
  name                 = "demo-sub"
  resource_group_name  = azurerm_resource_group.demo-rg.name
  virtual_network_name = azurerm_virtual_network.demo-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}
resource "azurerm_network_security_group" "demo-nsg" {
  name                = "demo-nsg"
  resource_group_name = azurerm_resource_group.demo-rg.name
  location            = azurerm_resource_group.demo-rg.location
  tags = {
    environment = "dev"
  }
}
resource "azurerm_network_security_rule" "demo-nsgrule" {
  name                        = "demo-nsgrule1"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.demo-rg.name
  network_security_group_name = azurerm_network_security_group.demo-nsg.name
}
resource "azurerm_subnet_network_security_group_association" "demo-nsga" {
  subnet_id                 = azurerm_subnet.demo-subnet.id
  network_security_group_id = azurerm_network_security_group.demo-nsg.id
}


resource "azurerm_public_ip" "demp-pip1" {
  name                = "demoPublicIp1"
  resource_group_name = azurerm_resource_group.demo-rg.name
  location            = azurerm_resource_group.demo-rg.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}
resource "azurerm_network_interface" "demo-nic" {
  name                = "demo-nic"
  location            = azurerm_resource_group.demo-rg.location
  resource_group_name = azurerm_resource_group.demo-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.demo-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.demp-pip1.id
  }
}


resource "azurerm_linux_virtual_machine" "demo-vm" {
  name                = "demo-vm"
  resource_group_name = azurerm_resource_group.demo-rg.name
  location            = azurerm_resource_group.demo-rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.demo-nic.id,
  ]

  custom_data = filebase64("customer.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/demoazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

provisioner "local-exec" {
  command = templatefile("windows-ssh-script.tpl",{
    hostname = self.public_ip_address,
    user = "adminuser"
    identityfile="~/.ssh/demoazurekey"

  })
  interpreter=["powershell","-command"]
}

  tags = {
    environment = "dev"
  }
}
  data "azurerm_public_ip" "demo-ip-data"{
  name = azurerm_public_ip.demp-pip1.name
   resource_group_name = azurerm_resource_group.demo-rg.name
  }

output "public_ip_address"{
  value = "${azurerm_linux_virtual_machine.demo-vm.name}: ${data.azurerm_public_ip.demo-ip-data.ip_address}"
}

resource "azurerm_storage_account" "demo-storage" {
  name                     = "terraformdemosa18"  # Must be unique globally
  resource_group_name      = azurerm_resource_group.demo-rg.name
  location                 = azurerm_resource_group.demo-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "demo-container" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.demo-storage.name
  container_access_type = "private"
}


terraform {
  backend "azurerm" {
    resource_group_name  = "demo-resources"
    storage_account_name = "terraformdemosa18"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

