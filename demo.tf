provider "azurerm" {
  features = {}
}

# Variables
variable "app_name" {
  description = "Name of the App Service"
  default     = "my-app-service"
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  default     = "my-resource-group"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = "East US"
}

# Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "mystorageaccount"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# App Service Plan
resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "app-service-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku {
    tier = "Standard"
    size = "S1"
  }
}

# App Service
resource "azurerm_app_service" "app_service" {
  name                = var.app_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.app_service_plan.id

  site_config {
    always_on = true
    dotnet_framework_version = "v4.0"
  }

  app_settings = {
    "WEBSITE_NODE_DEFAULT_VERSION" = "12.18.3"
  }

  connection_string {
    name  = "StorageAccountConnectionString"
    type  = "Custom"
    value = azurerm_storage_account.storage.primary_connection_string
  }
}

output "app_service_url" {
  value = azurerm_app_service.app_service.default_site_hostname
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}
