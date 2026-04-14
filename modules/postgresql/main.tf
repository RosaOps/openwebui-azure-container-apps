resource "random_password" "pg_admin" {
  length  = 24
  special = false
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "pg-${var.project_name}-${var.suffix}"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "16"
  administrator_login    = "pgadmin"
  administrator_password = random_password.pg_admin.result
  zone                   = "1"
  tags                   = var.tags

  # Burstable B1ms — cheapest tier, sufficient for OpenWebUI
  sku_name   = "B_Standard_B1ms"
  storage_mb = 32768

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = "openwebui"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Allow all Azure services to connect (required for Container Apps)
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
