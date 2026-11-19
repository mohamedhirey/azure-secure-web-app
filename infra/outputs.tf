output "resource_group_name" {
  description = "Resource group holding everything."
  value       = azurerm_resource_group.this.name
}

output "web_app_name" {
  description = "Web app name, needed to deploy the code."
  value       = azurerm_linux_web_app.this.name
}

output "web_app_url" {
  description = "Public HTTPS address of the web app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "cosmos_account_name" {
  description = "Cosmos DB account name."
  value       = azurerm_cosmosdb_account.this.name
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "log_analytics_workspace_guid" {
  description = "Workspace ID used by `az monitor log-analytics query`."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}
