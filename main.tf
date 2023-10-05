
resource "azurerm_resource_group" "rg" {
  name     = "rg-wvm-adj"
  location = "eastus2"
}




module "storage" {
  source                = "../module/storage-account"
  resource_group_name   = azurerm_resource_group.rg.name
  storage_account_name  = "Mystorageaccrezende90"
  tier                  = "Standard"
  replication = "LRS"
  kind = "FileStorage"
  static_website_enabled = false
  
  depends_on            = [module.rg]
}