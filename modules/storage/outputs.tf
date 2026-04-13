output "account_name" {
  value = azurerm_storage_account.main.name
}

output "primary_access_key" {
  value     = azurerm_storage_account.main.primary_access_key
  sensitive = true
}

output "models_share_name" {
  value = azurerm_storage_share.models.name
}

output "data_share_name" {
  value = azurerm_storage_share.data.name
}
