variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "project_name" {
  type = string
}

variable "suffix" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "tenant_id" {
  type = string
}

variable "admin_object_id" {
  description = "Object ID of the user/principal running terraform apply"
  type        = string
}

variable "managed_identity_principal_id" {
  description = "Principal ID of the Container App managed identity"
  type        = string
}
