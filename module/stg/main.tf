data "azurerm_resource_group" "storacc" {
  name = var.resource_group_name
}

resource "random_string" "storacc" {
  length  = 4
  special = false
  number  = false
}

resource "azurerm_storage_account" "storacc" {
  name                     = lower(join("", [var.storage_account_name, random_string.storacc.result]))
  resource_group_name      = data.azurerm_resource_group.storacc.name
  location                 = var.location == null ? data.azurerm_resource_group.storacc.location : var.location
  account_tier             = var.tier
  account_kind             = var.kind
  account_replication_type = var.replication
  tags                     = var.tags

  dynamic "static_website" {
    for_each = var.static_website_enabled ? [var.static_website] : []
    content {
      index_document     = static_website.value["index_document"]
      error_404_document = static_website.value["error_404_document"]
    }
  }

}

resource "azurerm_storage_container" "container" {
  for_each              = var.storacc_containers
  name                  = each.value.name
  storage_account_name  = azurerm_storage_account.storacc.name
  container_access_type = each.value.container_access_type
}

resource "azurerm_storage_share" "FSShare" {
  count   = var.enable_file_share == true ? 1 : 0
  name                 = "share-raiz"
  storage_account_name = azurerm_storage_account.storage.name
  depends_on           = [azurerm_storage_account.storage]
}

## Azure built-in roles
## https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
data "azurerm_role_definition" "storage_role" {
  name = "Storage File Data SMB Share Contributor"
}

resource "azurerm_role_assignment" "af_role" {
  count   = var.enable_file_share == true ? 1 : 0
  scope              = azurerm_storage_account.storage.id
  role_definition_id = data.azurerm_role_definition.storage_role.id
  principal_id       = azuread_group.aad_group.id
}