data "azurerm_client_config" "current" {}

# ---------------------------------------------------------- Cosmos DB --------

resource "azurerm_cosmosdb_account" "this" {
  name                = "cosmos-webapp-${random_string.suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = var.tags

  # Serverless: billed per request, nothing while idle.
  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.this.location
    failover_priority = 0
  }

  # No internet path, and account keys are refused. The only way to the data is the
  # private endpoint plus an Entra ID identity holding a data-plane role.
  public_network_access_enabled = false
  local_authentication_enabled  = false
}

resource "azurerm_cosmosdb_sql_database" "this" {
  name                = "appdb"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
}

resource "azurerm_cosmosdb_sql_container" "this" {
  name                = "visits"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  database_name       = azurerm_cosmosdb_sql_database.this.name
  partition_key_paths = ["/id"]
}

# ---------------------------------------------------------- Key Vault --------

resource "azurerm_key_vault" "this" {
  name                = "kv-webapp-${random_string.suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  soft_delete_retention_days    = 7
}

resource "random_password" "demo_api_key" {
  length  = 32
  special = false
}

# Written through Azure Resource Manager (control plane), not the vault's own
# endpoint (data plane). That is why this works from your laptop even though
# the vault has no public network access: Terraform never connects to the vault.
# Reading the value back still needs the data plane, which is private.
resource "azapi_resource" "demo_api_key" {
  type      = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  name      = "demo-api-key"
  parent_id = azurerm_key_vault.this.id

  body = {
    properties = {
      value = random_password.demo_api_key.result
    }
  }
}
