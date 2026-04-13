resource "azurerm_user_assigned_identity" "main" {
  name                = "id-${var.project_name}-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
