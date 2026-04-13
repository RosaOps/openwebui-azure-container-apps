output "fqdn" {
  value = azurerm_container_app.main.ingress[0].fqdn
}

output "environment_static_ip" {
  value = azurerm_container_app_environment.main.static_ip_address
}

output "environment_verification_id" {
  value = azurerm_container_app_environment.main.custom_domain_verification_id
}
