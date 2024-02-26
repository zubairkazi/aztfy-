terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.74.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "bits_testing"
    storage_account_name = "bitsstorage"
    container_name       = "terraform"
    key                  = "testenv.tfstate" 
    allow_blob_public_access = false
  }
}


provider "mssql" {
  hostname = "laborpro-sqlserver-bits.database.windows.net"
  port     = 1433

  azure_auth = {
    subscription_id = "c9cef1bb-0b0b-4529-a839-ec0e4789bf63"
    client_id       = "e10032bd-3be0-4719-8a4e-2cca3702bb23"
    client_secret   = var.client_secret
    tenant_id       = "663d0a6b-d40c-4712-8fc4-5fdf411a6a3d"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "c9cef1bb-0b0b-4529-a839-ec0e4789bf63"
  client_id       = "e10032bd-3be0-4719-8a4e-2cca3702bb23"
  client_secret   = var.client_secret
  tenant_id       = "663d0a6b-d40c-4712-8fc4-5fdf411a6a3d"
}

data "azurerm_client_config" "config" {}

data "azuread_user" "user" {
  user_principal_name = "bits@benchmarkit.solutions"
}

resource "azurerm_resource_group" "resource_group" {
  name     = "Bits_Testing"
  location = "centralindia"
}

resource "azurerm_key_vault" "key_vault" {
  name                = "laborpro-kv-bits"
  location            = azurerm_resource_group.resource_group.location
  tenant_id           = data.azurerm_client_config.config.tenant_id
  resource_group_name = azurerm_resource_group.resource_group.name

  enable_rbac_authorization       = true
  enabled_for_template_deployment = false
  enabled_for_disk_encryption     = false
  soft_delete_retention_days      = 90
  purge_protection_enabled        = false

  sku_name = "standard"
}

resource "azurerm_role_assignment" "role" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_user.user.object_id
}

resource "azurerm_key_vault_access_policy" "key_vault" {
  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = data.azurerm_client_config.config.tenant_id
  object_id    = data.azuread_user.user.object_id

  key_permissions = [
    "Get",
    "Create",
  ]

  secret_permissions = [
    "Get",
    "Set",
    "List"
  ]
}

resource "azurerm_storage_account" "function_storage_account" {
  name                     = "bitsstorage"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_servicebus_namespace" "servicebus_namespace" {
  location            = azurerm_resource_group.resource_group.location
  name                = "laborpro-servicebus-bits"
  resource_group_name = azurerm_resource_group.resource_group.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "report_queue" {
  name         = "sharedreportgeneratorqueue"
  namespace_id = azurerm_servicebus_namespace.servicebus_namespace.id
}

resource "azurerm_servicebus_queue" "sso_queue" {
  name                                 = "sso-utility"
  namespace_id                         = azurerm_servicebus_namespace.servicebus_namespace.id
  dead_lettering_on_message_expiration = true
}

# resource "azurerm_servicebus_queue" "calculation_queue" {
#   name               = "bits-labor-calculation"
#   namespace_id       = azurerm_servicebus_namespace.servicebus_namespace.id
#   requires_session   = true
#   max_delivery_count = 1
# }

resource "azurerm_mssql_server" "sql_server" {
  administrator_login = "connorssql"
  location            = azurerm_resource_group.resource_group.location
  name                = "laborpro-sqlserver-bits"
  resource_group_name = azurerm_resource_group.resource_group.name
  version             = "12.0"
  azuread_administrator {
    login_username = "LaborPro - SQL Owners"
    object_id      = "2d8b827f-e751-4cba-a647-106f45eb360b"
  }

  ### this is not a valid value -- dbpass
  administrator_login_password = "LaborPro2017!"
}

resource "azurerm_mssql_elasticpool" "sql_server_elastic_pool" {
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  name        = "laborpro-sqlserver-pool-bits"
  server_name = azurerm_mssql_server.sql_server.name
  per_database_settings {
    max_capacity = 4
    min_capacity = 0
  }
  sku {
    capacity = 4
    family   = "Gen5"
    name     = "GP_Gen5"
    tier     = "GeneralPurpose"
  }
  max_size_gb = 5
}

resource "azurerm_mssql_database" "client_database" {
  name                 = "laborpro-client-bits"
  elastic_pool_id      = azurerm_mssql_elasticpool.sql_server_elastic_pool.id
  server_id            = azurerm_mssql_server.sql_server.id
  storage_account_type = "Zone"
}

resource "azurerm_mssql_database" "background_database" {
  name                 = "laborpro-background-bits"
  elastic_pool_id      = azurerm_mssql_elasticpool.sql_server_elastic_pool.id
  server_id            = azurerm_mssql_server.sql_server.id
  storage_account_type = "Zone"
}

resource "azurerm_mssql_database" "master_database" {
  name                 = "laborpro-master-bits"
  elastic_pool_id      = azurerm_mssql_elasticpool.sql_server_elastic_pool.id
  server_id            = azurerm_mssql_server.sql_server.id
  storage_account_type = "Zone"
}

module "template_deployment" {
  source = "../modules/templates/single_region_environment"

  environment_suffix           = "bits"
  release_version              = var.release_version
  resource_group_name          = azurerm_resource_group.resource_group.name
  location                     = azurerm_resource_group.resource_group.location
  api_server_name              = "laborpro-api-net6-bits"
  keyvault_name                = azurerm_key_vault.key_vault.name
  keyvault_resource_group_name = azurerm_resource_group.resource_group.name
  client_api = {

    client_subdomains = ["development"]
  }
  background_worker = {

    dashboard_password    =  "@Microsoft.KeyVault(SecretUri=https://laborpro-kv-bits.vault.azure.net/secrets/backgroundJobsDashboardPassword)"
    dashboard_require_ssl = "false"
  }
  sso = {
    client_id     = "0oa2setxzbSWpAPs01d6"
    client_secret = "@Microsoft.KeyVault(SecretUri=https://laborpro-kv-bits.vault.azure.net/secrets/okta-client-secret)"
    domain        = "https://connorsgroup.oktapreview.com"
  }
  sso_queue = {
    service_bus_namespace   = azurerm_servicebus_namespace.servicebus_namespace.name
    sso_queue_servicebus_id = azurerm_servicebus_namespace.servicebus_namespace.id
  }

  servicebus_namespace_name = "laborpro-servicebus-bits"
  labor_calculation = {
    name                       = "laborpro-calculation-net6-bits"
    queue_endpoint             = "Endpoint"
    queue_name                 = "bits-labor-calculation-net6"
    storage_account_name       = azurerm_storage_account.function_storage_account.name
    storage_account_access_key = azurerm_storage_account.function_storage_account.primary_access_key
  }
  mass_exporter = {
    name                       = "laborpro-massexporter-net6-bits"
    queue_endpoint             = "@Microsoft.KeyVault(SecretUri=https://laborpro-kv-bits.vault.azure.net/secrets/ServiceBusEndpoint)"
    function_endpoint          = "@Microsoft.KeyVault(SecretUri=https://laborpro-kv-bits.vault.azure.net/secrets/AzureExportStandardFunctionEndpoint)"
    token                      = "@Microsoft.KeyVault(SecretUri=https://laborpro-kv-bits.vault.azure.net/secrets/AzureSecretToken)"
    blob_storage_endpoint      = "@Microsoft.KeyVault(SecretUri=https://laborpro-kv-bits.vault.azure.net/secrets/BlobStorageEndpoint)"
    storage_account_name       = azurerm_storage_account.function_storage_account.name
    queue_name                 = "sharedreportgeneratorqueue-net6"
    storage_account_access_key = azurerm_storage_account.function_storage_account.primary_access_key
  }
  smtp = {
    host     = "smtp.sendgrid.net"
    username = "apikey"
    password = "ContinuousImproveDailyPursuit"
  }

  database_connection_strings = {
    # master          = "Server=tcp:laborpro-sqlserver-bits.database.windows.net,1433;Authentication=Active Directory Default;Initial Catalog=laborpro-master-bits;MultipleActiveResultSets=True;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    master         = "Server=tcp:${azurerm_mssql_server.sql_server.name}.database.windows.net,1433;Initial Catalog=${azurerm_mssql_database.master_database.name};Persist Security Info=False;User ID=phoenix-app;Password=LaborPro2017!;MultipleActiveResultSets=True;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    background     = "Server=tcp:${azurerm_mssql_server.sql_server.name}.database.windows.net,1433;Initial Catalog=${azurerm_mssql_database.background_database.name};Persist Security Info=False;User ID=phoenix-app;Password=LaborPro2017!;MultipleActiveResultSets=True;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    NET4background = "@Microsoft.KeyVault(SecretUri=https://laborpro-kv-bits.vault.azure.net/secrets/BackgroundJobs-production)"
  }
  database_configuration = {
    sql_server_id                   = azurerm_mssql_server.sql_server.id
    elastic_pool_id                 = azurerm_mssql_elasticpool.sql_server_elastic_pool.id
    background_worker_database_name = "laborpro-background-worker-net6-bits"
  }
  depends_on       = [azurerm_key_vault.key_vault]
  sftp_server_name = "tumbleweed"
  deploy_sftp      = false
  migration_utility = {
    queue_name                 = "sharedreportgeneratorqueue-net6"
    storage_account_name       = azurerm_storage_account.function_storage_account.name
    storage_account_access_key = azurerm_storage_account.function_storage_account.primary_access_key
  }
  database_names              = ["laborpro-master-bits", "laborpro-client-bits"]
  include_prototype_resources = true

  api_data_container = {
    storage_account_name = azurerm_storage_account.function_storage_account.name
  }
}
