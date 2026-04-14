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
  description = "Short alphanumeric suffix for unique resource names"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
}
