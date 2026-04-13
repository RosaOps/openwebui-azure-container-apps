resource "random_password" "webui_secret_key" {
  length  = 32
  special = false
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_name}-${var.suffix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = var.tags
}

# Current user — needs Key Vault Administrator to create secrets during deployment
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.admin_object_id
}

# Managed Identity — needs Key Vault Secrets User to read secrets at runtime
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.managed_identity_principal_id
}

resource "azurerm_key_vault_secret" "webui_secret_key" {
  name         = "WEBUI-SECRET-KEY"
  value        = random_password.webui_secret_key.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_admin]
}

# Key Vault enters soft-delete for 7 days after destroy — name stays reserved globally.
# This purges it immediately so the same name can be reused on the next apply.
resource "terraform_data" "purge_key_vault" {
  triggers_replace = [azurerm_key_vault.main.name, var.location]

  provisioner "local-exec" {
    when        = destroy
    command     = "az keyvault purge --name ${self.triggers_replace[0]} --location '${self.triggers_replace[1]}'; exit 0"
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [azurerm_key_vault.main]
}
