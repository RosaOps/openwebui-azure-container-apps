terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.45.0, < 4.0.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0.0"
    }
  }
}
