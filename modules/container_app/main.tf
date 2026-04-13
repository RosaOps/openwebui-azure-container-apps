resource "azurerm_container_app_environment" "main" {
  name                = "cae-${var.project_name}-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_container_app_environment_storage" "models" {
  name                         = "models"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = var.storage_account_name
  share_name                   = var.models_share_name
  access_key                   = var.storage_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "data" {
  name                         = "data"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = var.storage_account_name
  share_name                   = var.data_share_name
  access_key                   = var.storage_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "main" {
  name                         = "ca-${var.project_name}-${var.suffix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  depends_on = [
    azurerm_container_app_environment_storage.models,
    azurerm_container_app_environment_storage.data,
  ]

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # Secret referenced from Key Vault via Managed Identity — no value stored in code
  secret {
    name                = "webui-secret-key"
    key_vault_secret_id = var.secret_versionless_id
    identity            = var.managed_identity_id
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 10

    volume {
      name         = "models-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.models.name
    }

    volume {
      name         = "data-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.data.name
    }

    container {
      name   = "openwebui"
      image  = "ghcr.io/open-webui/open-webui:main"
      cpu    = 1.0
      memory = "2Gi"

      # Secret injected as environment variable — value comes from Key Vault at runtime
      env {
        name        = "WEBUI_SECRET_KEY"
        secret_name = "webui-secret-key"
      }

      # SQLite is incompatible with Azure File Share (SMB lacks POSIX file locking).
      # DATA_DIR overrides the default data path so the database runs on local container
      # storage. Both File Shares remain mounted for persistent model and data files.
      # Production recommendation: replace SQLite with Azure Database for PostgreSQL.
      env {
        name  = "DATA_DIR"
        value = "/tmp"
      }

      volume_mounts {
        name = "models-volume"
        path = "/app/chat_frontend/models"
      }

      volume_mounts {
        name = "data-volume"
        path = "/app/backend/data"
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8080
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8080
      }
    }

    # CPU-based autoscaling at 75% utilization
    custom_scale_rule {
      name             = "cpu-scale-rule"
      custom_rule_type = "cpu"
      metadata = {
        type  = "Utilization"
        value = "75"
      }
    }
  }

  # Prevents Terraform from reverting the custom domain binding managed by azapi_update_resource
  lifecycle {
    ignore_changes = [ingress]
  }
}

# Step 1a: Wait for DNS A record to propagate before attempting hostname add and certificate creation.
# Azure validates DNS during both steps — running before propagation causes FailedARecordValidation.
# Polls every 15 seconds for up to 10 minutes.
resource "terraform_data" "wait_for_dns" {
  count = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0

  triggers_replace = [
    azurerm_container_app_environment.main.static_ip_address,
    var.custom_domain,
  ]

  provisioner "local-exec" {
    command     = <<-PS
      $ip     = "${azurerm_container_app_environment.main.static_ip_address}"
      $domain = "${var.custom_domain}"
      $attempts = 0
      Write-Host "Waiting for DNS $domain to resolve to $ip ..."
      do {
        Start-Sleep -Seconds 15
        $r = Resolve-DnsName $domain -Type A -Server 8.8.8.8 -ErrorAction SilentlyContinue
        $attempts++
        Write-Host "Attempt $attempts : $($r.IPAddress)"
      } while (($r.IPAddress -ne $ip) -and ($attempts -lt 40))
      if ($r.IPAddress -eq $ip) { Write-Host "DNS ready."; exit 0 }
      else { Write-Host "DNS timeout after $attempts attempts."; exit 1 }
    PS
    interpreter = ["PowerShell", "-Command"]
  }
}

# Step 1b: Add custom hostname to container app (required before certificate creation)
# Azure rejects certificate creation if the hostname is not already bound to a container app
resource "terraform_data" "add_hostname" {
  count = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0

  triggers_replace = [
    azurerm_container_app.main.id,
    var.custom_domain,
  ]

  provisioner "local-exec" {
    command     = "az containerapp hostname add --name ${azurerm_container_app.main.name} --resource-group ${var.resource_group_name} --hostname ${var.custom_domain}; exit 0"
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [terraform_data.wait_for_dns]
}

# Step 2: Azure-managed SSL certificate with HTTP domain validation
# azurerm 3.x does not have this resource — using azapi to call the REST API directly
resource "azapi_resource" "managed_certificate" {
  count     = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0
  type      = "Microsoft.App/managedEnvironments/managedCertificates@2023-05-01"
  name      = "cert-${var.project_name}"
  parent_id = azurerm_container_app_environment.main.id
  location  = var.location

  body = {
    properties = {
      subjectName             = var.custom_domain
      domainControlValidation = "HTTP"
    }
  }

  depends_on = [terraform_data.add_hostname]

  timeouts {
    create = "30m"
    read   = "5m"
    delete = "30m"
  }
}

# Step 3: Bind certificate to hostname (upgrades binding from Disabled to SniEnabled)
resource "azapi_update_resource" "bind_certificate" {
  count       = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0
  type        = "Microsoft.App/containerApps@2023-05-01"
  resource_id = azurerm_container_app.main.id

  body = {
    properties = {
      configuration = {
        ingress = {
          customDomains = [
            {
              name          = var.custom_domain
              bindingType   = "SniEnabled"
              certificateId = azapi_resource.managed_certificate[0].id
            }
          ]
        }
      }
    }
  }

  depends_on = [azapi_resource.managed_certificate]
}

# Cleanup: removes hostname binding before certificate deletion on destroy.
# Azure refuses to delete a certificate while it is bound to a hostname.
# This resource has no create-time action — the destroy provisioner runs first
# (before managed_certificate is deleted) because managed_certificate depends on it.
resource "terraform_data" "remove_hostname" {
  count = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0

  # Store values needed at destroy time — resource references are unavailable then
  triggers_replace = [
    azurerm_container_app.main.name,
    var.resource_group_name,
    var.custom_domain,
  ]

  provisioner "local-exec" {
    when        = destroy
    command     = "az containerapp hostname delete --name ${self.triggers_replace[0]} --resource-group ${self.triggers_replace[1]} --hostname ${self.triggers_replace[2]} --yes; exit 0"
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [
    azapi_resource.managed_certificate,
    azapi_update_resource.bind_certificate,
  ]
}
