terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.2"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state on purpose. This environment is created and destroyed in one
  # session from one terminal, so there is nothing to share or lock. The state
  # file holds the generated demo secret - it is gitignored, never commit it.
}

# Both providers read the subscription from ARM_SUBSCRIPTION_ID and sign in
# with your `az login` session. Nothing identifying is written in this repo.
provider "azurerm" {
  features {
    # Application Insights adds a "Smart Detection" action group to the resource
    # group on its own. Terraform does not manage it, and by default refuses to
    # delete a group containing anything it does not manage - so destroy fails.
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Deleting a workspace only soft-deletes it. It stays recoverable, logs and
    # all, for 14 days. This build claims nothing remains, so delete it for real.
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

provider "azapi" {}
