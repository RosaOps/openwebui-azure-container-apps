variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "suffix" {
  description = "Random suffix for unique resource names"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
}

variable "storage_account_name" {
  description = "Storage account name for Azure File Share mounts"
  type        = string
}

variable "storage_access_key" {
  description = "Storage account access key"
  type        = string
  sensitive   = true
}

variable "models_share_name" {
  description = "File share name for AI models (/app/chat_frontend/models)"
  type        = string
}

variable "data_share_name" {
  description = "File share name for application data (/app/backend/data)"
  type        = string
}

variable "managed_identity_id" {
  description = "Resource ID of the User-Assigned Managed Identity"
  type        = string
}

variable "secret_versionless_id" {
  description = "Versionless Key Vault secret URI for WEBUI_SECRET_KEY"
  type        = string
}

variable "database_url_secret_id" {
  description = "Versionless Key Vault secret URI for DATABASE_URL"
  type        = string
}

variable "custom_domain" {
  description = "Custom domain for the Container App (e.g., myapp.xyz)"
  type        = string
  default     = ""
}

variable "configure_custom_domain" {
  description = "Set to true after DNS CNAME is configured to provision the managed SSL certificate"
  type        = bool
  default     = false
}
