# terraform-openwebui-aca

Terraform configuration to deploy [OpenWebUI](https://openwebui.com) on Azure Container Apps.

## What this deploys

- **Resource Group** with all resources in one place
- **Storage Account** with two File Shares for persistent data (`/app/backend/data` and `/app/chat_frontend/models`)
- **Container App Environment** + **Container App** running OpenWebUI
- **User-Assigned Managed Identity** for passwordless Key Vault access
- **Key Vault** with auto-generated secret (`WEBUI_SECRET_KEY`) — no hardcoded values anywhere
- **Custom domain** with Azure-managed SSL certificate
- **CPU-based autoscaling** (min 1 / max 10 replicas, scale at 75% utilization)

## Requirements

- Terraform >= 1.5
- Azure CLI + an active Azure subscription
- A custom domain with DNS access

## Usage

```bash
git clone https://github.com/boshdevops13-source/terraform-assessment-openwebui
cd terraform-assessment-openwebui

cp terraform.tfvars.example terraform.tfvars
# fill in your values

az login
terraform init
terraform apply
```

After apply, you'll get a `container_app_fqdn` output. Add a CNAME record in your DNS pointing your domain to that value, then run apply again with `configure_custom_domain = true`.

## Notes

- `terraform.tfvars` is gitignored — use `terraform.tfvars.example` as a template
- Managed certificate provisioning requires DNS to be configured first (see above)
- `azapi` provider is used for the managed certificate — this resource isn't available in azurerm 3.x
