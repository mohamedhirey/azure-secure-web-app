# One user-assigned identity for the web app. Created before the app, so every
# permission below exists by the time the app first starts.
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-webapp-cac-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

# Read secret values and their metadata, nothing else - cannot write or delete them.
resource "azurerm_role_assignment" "app_reads_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Cosmos DB has its own data-plane roles, separate from Azure RBAC.
# ...0002 is the built-in "Cosmos DB Built-in Data Contributor" (read and write
# items). Scoped to the one database, not the whole account.
resource "azurerm_cosmosdb_sql_role_assignment" "app_reads_writes_items" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.app.principal_id
  scope               = "${azurerm_cosmosdb_account.this.id}/dbs/${azurerm_cosmosdb_sql_database.this.name}"
}
