variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "suffix" {
  description = "Short alphanumeric suffix for globally unique resource names (storage account, key vault). Pick once and keep stable — changing it recreates all resources."
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "West Europe"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "openwebui"
}

variable "custom_domain" {
  description = "Custom domain for the Container App (e.g., myapp.xyz). Leave empty if you don't have a domain."
  type        = string
  default     = ""
}

variable "configure_custom_domain" {
  description = "Set to true after adding the DNS CNAME record to provision the managed certificate"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    project     = "openwebui"
    environment = "assessment"
    managed_by  = "terraform"
  }
}
