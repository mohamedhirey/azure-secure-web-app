resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-webapp-cac-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Request traces, dependency calls (the Cosmos DB queries) and exceptions.
resource "azurerm_application_insights" "this" {
  name                = "appi-webapp-cac-001"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

# Platform logs: every HTTP request to the app, and every access to the vault.
resource "azurerm_monitor_diagnostic_setting" "web_app" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AuditEvent"
  }
}

resource "azurerm_monitor_action_group" "email" {
  name                = "ag-webapp-cac-001"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "webapp"
  tags                = var.tags

  email_receiver {
    name          = "owner"
    email_address = var.alert_email
  }
}

# Fires when the app returns more than five server errors in five minutes.
# Step 15 of GUIDE.md fires it on purpose, using the app's /fail endpoint.
resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-webapp-http5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "The web app returned more than 5 server errors in 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}
