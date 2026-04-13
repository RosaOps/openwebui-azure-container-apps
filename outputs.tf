output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "container_app_fqdn" {
  description = "Default FQDN — use this as the CNAME target for your custom domain"
  value       = module.container_app.fqdn
}

output "container_app_url" {
  description = "Default URL (accessible before custom domain is configured)"
  value       = "https://${module.container_app.fqdn}"
}

output "custom_domain_url" {
  description = "Custom domain URL (available after configure_custom_domain = true)"
  value       = var.custom_domain != "" ? "https://${var.custom_domain}" : "No custom domain configured"
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.keyvault.key_vault_name
}

output "managed_identity_client_id" {
  description = "Client ID of the User-Assigned Managed Identity"
  value       = module.identity.client_id
}

output "dns_nameservers" {
  description = "Set these as Custom DNS nameservers in Namecheap (one-time setup). After that, DNS is managed automatically by Terraform."
  value       = var.custom_domain != "" ? azurerm_dns_zone.main[0].name_servers : toset(["No custom domain configured"])
}
