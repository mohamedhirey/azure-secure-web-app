# Globally unique names (web app, Cosmos DB, Key Vault) share one random suffix.
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-webapp-cac-001"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-webapp-cac-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
  tags                = var.tags
}

# The web app does not live in this subnet. It borrows it for OUTBOUND traffic
# only (VNet integration), which is how it reaches the private endpoints.
resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.app_subnet_cidr]

  delegation {
    name = "app-service"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoint_subnet_cidr]

  # Without this, NSG rules are silently ignored for private endpoints.
  private_endpoint_network_policies = "Enabled"
}

# Same rule order as the landing zone project: allows first, catch-all deny at
# 4096 (the highest priority number Azure accepts, so evaluated last) so a
# broken allow fails closed.
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-webapp-pe-cac-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "allow_https_from_app" {
  name                        = "AllowHttpsFromAppSubnet"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.app_subnet_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# ------------------------------------------------- private endpoints --------

# A private endpoint gives a service a private IP inside the VNet. The private
# DNS zone makes the service's normal hostname resolve to that IP from inside
# the VNet, so the app needs no special connection string.
locals {
  private_endpoints = {
    cosmos = {
      resource_id = azurerm_cosmosdb_account.this.id
      subresource = "Sql"
      dns_zone    = "privatelink.documents.azure.com"
    }
    vault = {
      resource_id = azurerm_key_vault.this.id
      subresource = "vault"
      dns_zone    = "privatelink.vaultcore.azure.net"
    }
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_endpoints

  name                = each.value.dns_zone
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.private_endpoints

  name                = "link-${each.key}"
  private_dns_zone_id = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = var.tags
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  name                = "pep-webapp-${each.key}-cac-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[each.key].id]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}
