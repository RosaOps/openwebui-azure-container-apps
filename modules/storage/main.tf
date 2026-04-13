resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${var.suffix}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_storage_share" "models" {
  name                 = "models"
  storage_account_name = azurerm_storage_account.main.name
  quota                = 50
}

resource "azurerm_storage_share" "data" {
  name                 = "data"
  storage_account_name = azurerm_storage_account.main.name
  quota                = 50
}
