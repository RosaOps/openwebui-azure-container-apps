# openwebui-azure-container-apps

Terraform configuration to deploy [OpenWebUI](https://openwebui.com) on Azure Container Apps with HTTPS, Key Vault secrets, and automatic DNS management.
Custom Domain  --> https://boschaiops.xyz/
## What this deploys

- **Resource Group** with all resources in one place
- **Storage Account** with two File Shares (`/app/backend/data` and `/app/chat_frontend/models`)
- **Container App Environment** + **Container App** running OpenWebUI
- **User-Assigned Managed Identity** for passwordless Key Vault access
- **Key Vault** with auto-generated secret (`WEBUI_SECRET_KEY`) — no hardcoded values anywhere
- **Azure DNS Zone** managing A and TXT records automatically
- **Custom domain** with Azure-managed SSL certificate (HTTP validation)
- **CPU-based autoscaling** (min 1 / max 10 replicas, scale at 75% utilization)

## Requirements

- Terraform >= 1.5
- Azure CLI + an active Azure subscription
- A custom domain (DNS will be managed automatically by Azure DNS Zone)

## Usage

```bash
git clone https://github.com/RosaOps/openwebui-azure-container-apps.git
cd openwebui-azure-container-apps

cp terraform.tfvars.example terraform.tfvars
# fill in your values

az login
terraform init
terraform apply
```

After apply, the outputs will show:
- `container_app_url` — Azure default URL (always accessible)
- `custom_domain_url` — your custom domain with HTTPS
- `dns_nameservers` — Azure DNS nameservers (see DNS setup below)

## DNS Setup (one-time)

After the first `terraform apply`, set the Azure nameservers in your domain registrar:

1. Run `terraform output dns_nameservers` to get the 4 nameservers
2. In your registrar (Namecheap, GoDaddy etc.) → set **Custom DNS** to those nameservers
3. Run `terraform apply` again — DNS propagation is handled automatically

From this point on, DNS is fully managed by Terraform. No manual DNS changes are needed on redeploy.

## Notes

- `terraform.tfvars` is gitignored — use `terraform.tfvars.example` as a template
- `suffix` must be unique (used in globally unique resource names like Key Vault and Storage Account)
- `azapi` provider is used for the managed certificate — `azurerm_container_app_environment_managed_certificate` is not available in azurerm 3.x
- SQLite runs on local container storage (`DATA_DIR=/tmp`) due to SMB locking limitations on Azure File Share — data does not persist across container restarts. For production, use Azure Database for PostgreSQL
