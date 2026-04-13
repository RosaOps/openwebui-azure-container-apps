output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "secret_versionless_id" {
  value = azurerm_key_vault_secret.webui_secret_key.versionless_id
}
