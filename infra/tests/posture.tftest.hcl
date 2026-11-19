# command = plan, so nothing is created in Azure. These assert against the plan.
# An `az login` session is still needed, because the provider signs in to plan.

variables {
  alert_email = "nobody@example.com"
}

run "data_tier_has_no_public_network_path" {
  command = plan

  assert {
    condition     = azurerm_cosmosdb_account.this.public_network_access_enabled == false
    error_message = "Cosmos DB must not be reachable from the internet."
  }

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "Key Vault must not be reachable from the internet."
  }
}

run "no_keys_or_passwords_anywhere" {
  command = plan

  assert {
    condition     = azurerm_cosmosdb_account.this.local_authentication_enabled == false
    error_message = "Cosmos DB account keys must be disabled. Access is by Entra ID identity only."
  }

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled == true
    error_message = "Key Vault must use Azure RBAC, not legacy access policies."
  }

  assert {
    condition = (
      azurerm_linux_web_app.this.ftp_publish_basic_authentication_enabled == false &&
      azurerm_linux_web_app.this.webdeploy_publish_basic_authentication_enabled == false
    )
    error_message = "The web app must not accept publishing passwords."
  }
}

run "web_app_is_https_only" {
  command = plan

  assert {
    condition     = azurerm_linux_web_app.this.https_only == true
    error_message = "The web app must redirect plain HTTP to HTTPS."
  }
}

run "private_endpoint_subnet_denies_by_default" {
  command = plan

  assert {
    condition = (
      azurerm_network_security_rule.deny_all_inbound.priority == 4096 &&
      azurerm_network_security_rule.deny_all_inbound.access == "Deny"
    )
    error_message = "The catch-all deny must sit at 4096, the highest priority number Azure accepts, so it is evaluated last."
  }

  assert {
    condition = (
      azurerm_network_security_rule.allow_https_from_app.priority <
      azurerm_network_security_rule.deny_all_inbound.priority
    )
    error_message = "The allow must have a LOWER priority number than the deny, or Azure never evaluates it."
  }
}
