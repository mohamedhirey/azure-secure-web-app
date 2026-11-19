variable "alert_email" {
  type        = string
  description = "Address that receives alert notifications."
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "canadacentral"
}

variable "address_space" {
  type        = string
  description = "Virtual network CIDR."
  default     = "10.60.0.0/16"
}

variable "app_subnet_cidr" {
  type        = string
  description = "Subnet the web app sends its outbound traffic through (VNet integration)."
  default     = "10.60.1.0/24"
}

variable "private_endpoint_subnet_cidr" {
  type        = string
  description = "Subnet holding the private endpoints for Cosmos DB and Key Vault."
  default     = "10.60.2.0/24"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource."
  default = {
    Project     = "azure-secure-web-app"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}
