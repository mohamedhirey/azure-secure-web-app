resource "azurerm_service_plan" "this" {
  name                = "asp-webapp-cac-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  os_type             = "Linux"
  sku_name            = "B1" # the cheapest tier that supports VNet integration
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                = "app-webapp-${random_string.suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id
  tags                = var.tags

  https_only                = true
  virtual_network_subnet_id = azurerm_subnet.app.id

  # No publishing passwords. Deployments authenticate with Entra ID.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  # Which identity the platform uses to resolve Key Vault references below.
  key_vault_reference_identity_id = azurerm_user_assigned_identity.app.id

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    minimum_tls_version               = "1.2"
    health_check_path                 = "/health"
    health_check_eviction_time_in_min = 5

    application_stack {
      python_version = "3.12"
    }
  }

  app_settings = {
    AZURE_CLIENT_ID  = azurerm_user_assigned_identity.app.client_id
    COSMOS_ENDPOINT  = azurerm_cosmosdb_account.this.endpoint
    COSMOS_DATABASE  = azurerm_cosmosdb_sql_database.this.name
    COSMOS_CONTAINER = azurerm_cosmosdb_sql_container.this.name

    # A Key Vault reference: the platform fetches the secret with the app's
    # identity and hands the app the value. The secret itself is never stored
    # in the app's configuration, in this repo, or in a pipeline.
    DEMO_API_KEY = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.this.vault_uri}secrets/${local.demo_secret_name})"

    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true" # install requirements.txt on deploy
  }

  # The app must not start until it can actually reach and read its dependencies.
  depends_on = [
    azapi_resource_action.demo_api_key,
    azurerm_private_endpoint.this,
    azurerm_role_assignment.app_reads_secrets,
    azurerm_cosmosdb_sql_role_assignment.app_reads_writes_items,
  ]
}
