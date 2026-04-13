data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.suffix}"
  location = var.location
  tags     = var.tags
}

module "storage" {
  source = "./modules/storage"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  project_name        = var.project_name
  suffix              = var.suffix
  tags                = var.tags
}

module "identity" {
  source = "./modules/identity"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  project_name        = var.project_name
  suffix              = var.suffix
  tags                = var.tags
}

module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  project_name                  = var.project_name
  suffix                        = var.suffix
  tags                          = var.tags
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  admin_object_id               = data.azurerm_client_config.current.object_id
  managed_identity_principal_id = module.identity.principal_id
}

# Azure DNS Zone — manages DNS records automatically so destroy+apply works without manual Namecheap updates.
# After first apply: copy the nameservers from output "dns_nameservers" into Namecheap (Custom DNS).
resource "azurerm_dns_zone" "main" {
  count               = var.custom_domain != "" ? 1 : 0
  name                = var.custom_domain
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_dns_a_record" "apex" {
  count               = var.custom_domain != "" ? 1 : 0
  name                = "@"
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [module.container_app.environment_static_ip]

}

resource "azurerm_dns_txt_record" "asuid" {
  count               = var.custom_domain != "" ? 1 : 0
  name                = "asuid"
  zone_name           = azurerm_dns_zone.main[0].name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300

  record {
    value = module.container_app.environment_verification_id
  }
}

module "container_app" {
  source = "./modules/container_app"

  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  project_name            = var.project_name
  suffix                  = var.suffix
  tags                    = var.tags
  storage_account_name    = module.storage.account_name
  storage_access_key      = module.storage.primary_access_key
  models_share_name       = module.storage.models_share_name
  data_share_name         = module.storage.data_share_name
  managed_identity_id     = module.identity.id
  secret_versionless_id   = module.keyvault.secret_versionless_id
  custom_domain           = var.custom_domain
  configure_custom_domain = var.configure_custom_domain

  # Ensure all Key Vault resources (including RBAC) are ready before container starts
  depends_on = [module.keyvault]
}
