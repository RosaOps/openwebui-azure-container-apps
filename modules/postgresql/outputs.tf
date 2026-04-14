output "database_url" {
  description = "PostgreSQL connection string for OpenWebUI (DATABASE_URL)"
  value       = "postgresql://pgadmin:${random_password.pg_admin.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/openwebui"
  sensitive   = true
}
