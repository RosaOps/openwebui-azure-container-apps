# Fișierele Terraform — ce face fiecare și de ce

---

## Structura completă

```
Bosh/
├── providers.tf               ← providerii și configurația Terraform
├── variables.tf               ← variabilele root
├── main.tf                    ← Resource Group + apelează modulele
├── outputs.tf                 ← ce afișează după apply
├── terraform.tfvars           ← valorile tale (gitignored)
├── terraform.tfvars.example   ← template pentru alții
├── .gitignore
├── README.md
└── modules/
    ├── storage/
    │   ├── main.tf            ← Storage Account + File Shares
    │   ├── variables.tf       ← ce primește modulul
    │   └── outputs.tf         ← ce returnează modulul
    ├── identity/
    │   ├── main.tf            ← Managed Identity
    │   ├── variables.tf
    │   └── outputs.tf
    ├── keyvault/
    │   ├── main.tf            ← Key Vault + RBAC + Secret
    │   ├── variables.tf
    │   └── outputs.tf
    └── container_app/
        ├── main.tf            ← CAE + Container App
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf        ← declară azapi pentru modul
```

---

## providers.tf — "Cu ce lucrăm"

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 3.45.0, < 4.0.0" }
    random  = { source = "hashicorp/random",  version = ">= 3.0" }
    azapi   = { source = "azure/azapi",        version = ">= 2.0.0" }
  }
}
```

**Cei 3 provideri:**
- **azurerm** — provider-ul principal Azure. Creează toate resursele standard
- **random** — generează valori aleatorii (sufixul din numele resurselor și parola din Key Vault)
- **azapi** — provider alternativ Azure pentru resurse care nu există încă în azurerm 3.x (managed certificate)

**De ce `< 4.0.0` la azurerm?**
Versiunea 4.x are breaking changes — unele resurse s-au schimbat incompatibil. Fără această limită, `terraform init` ar putea descărca 4.x și codul ar da erori.

**De ce `>= 2.0.0` la azapi?**
azapi 2.0 a schimbat sintaxa blocului `body`: în versiunea 1.x se folosea `body = jsonencode({...})`, iar în 2.x se folosește direct un obiect HCL `body = {...}`. Versiunea noastră de cod folosește sintaxa 2.x, deci limita minimă trebuie să fie 2.0.0.

**`prevent_deletion_if_contains_resources = false`**
Permite ștergerea Resource Group-ului chiar dacă mai conține resurse. Necesar pentru `terraform destroy` — fără asta, dacă un deployment a eșuat parțial și a lăsat resurse în urmă, Terraform refuza să șteargă Resource Group-ul.

---

## variables.tf — "Ce poate fi configurat"

```hcl
variable "subscription_id" { type = string }
variable "location"         { type = string, default = "West Europe" }
variable "project_name"     { type = string, default = "openwebui" }
variable "suffix"           { type = string }
variable "custom_domain"    { type = string, default = "" }
variable "configure_custom_domain" { type = bool, default = false }
variable "tags"             { type = map(string), default = {...} }
```

**De ce `suffix` e o variabilă explicită (nu `random_string`)?**
Inițial sufixul era generat aleatoriu cu `random_string`. Problema: la fiecare `destroy` + `apply` se genera un sufix nou → FQDN nou → IP nou → DNS trebuia actualizat manual în Namecheap. Cu un sufix fix în `terraform.tfvars` (`suffix = "boshaiops23"`), resursele au mereu același nume, iar DNS-ul rămâne valid.

**De ce `custom_domain` are `default = ""`?**
Dacă evaluatorul nu are un domeniu propriu, poate lăsa variabila goală. Codul verifică `var.custom_domain != ""` înainte să creeze certificatul sau să configureze custom domain binding. Fără default, Terraform ar cere obligatoriu o valoare.

**De ce nu punem valorile direct în variables.tf?**
`variables.tf` declară CE există și tipul. `terraform.tfvars` pune valorile concrete. Separarea permite oricui să cloneze repo-ul și să pună propriile valori fără să modifice codul.

---

## main.tf — "Dirijorul orchestrei"

```hcl
data "azurerm_client_config" "current" {}   # citește contul Azure logat

resource "azurerm_resource_group" "main" {
  name = "rg-${var.project_name}-${var.suffix}"
  ...
}

# Azure DNS Zone — gestionează automat A record și TXT record pentru domeniu
resource "azurerm_dns_zone" "main" {
  count = var.custom_domain != "" ? 1 : 0
  name  = var.custom_domain
}

resource "azurerm_dns_a_record" "apex" {
  count   = var.custom_domain != "" ? 1 : 0
  name    = "@"
  records = [module.container_app.environment_static_ip]
}

resource "azurerm_dns_txt_record" "asuid" {
  count = var.custom_domain != "" ? 1 : 0
  name  = "asuid"
  record { value = module.container_app.environment_verification_id }
}

module "storage" { source = "./modules/storage", ... }
module "identity" { source = "./modules/identity", ... }
module "keyvault" { source = "./modules/keyvault", ... }
module "container_app" {
  source     = "./modules/container_app"
  depends_on = [module.keyvault]
  ...
}
```

**Cum funcționează modulele?**
Un modul e ca o funcție: îi dai niște parametri (inputs), el creează resurse și îți returnează niște valori (outputs).

Exemplu:
```
module "storage" primește: resource_group_name, location, project_name, suffix, tags
module "storage" returnează: account_name, primary_access_key, models_share_name, data_share_name
```

Aceste outputuri sunt pasate ca inputs la `module.container_app`.

**`depends_on = [module.keyvault]`**
Forțează Terraform să creeze tot din modulul keyvault (inclusiv RBAC) înainte să creeze Container App-ul. Fără asta, containerul ar putea porni înainte ca permisiunile Key Vault să fie propagate.

---

## modules/storage/

**main.tf:**
```hcl
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(var.project_name, "-", "")}${var.suffix}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
resource "azurerm_storage_share" "models" { name = "models", quota = 50 }
resource "azurerm_storage_share" "data"   { name = "data",   quota = 50 }
```

`replace(var.project_name, "-", "")` — Storage Account nu acceptă cratime în nume, deci le eliminăm.
`LRS` = Locally Redundant Storage — 3 copii în același datacenter, cel mai ieftin tier.
`quota = 50` = limita de 50GB per file share.

**outputs.tf** returnează:
- `account_name` — folosit la montarea storage în Container App Environment
- `primary_access_key` — cheia de acces (sensitive = true, nu apare în logs)
- `models_share_name`, `data_share_name` — numele share-urilor

---

## modules/identity/

**main.tf:**
```hcl
resource "azurerm_user_assigned_identity" "main" {
  name = "id-${var.project_name}-${var.suffix}"
}
```

Simplu — creează identitatea. Toată complexitatea (permisiunile) e în modulul keyvault.

**outputs.tf** returnează:
- `id` — ID-ul complet, folosit la atribuirea identității containerului
- `principal_id` — folosit pentru RBAC în Key Vault
- `client_id` — afișat în outputs pentru informare

---

## modules/keyvault/

Cel mai complex modul — 4 responsabilități:

**1. Generează secretul aleatoriu**
```hcl
resource "random_password" "webui_secret_key" {
  length  = 32
  special = false
}
```
Terraform generează automat o parolă sigură. Nu o scriem noi.

**2. Creează Key Vault**
```hcl
resource "azurerm_key_vault" "main" {
  enable_rbac_authorization  = true   # RBAC în loc de access policies (metoda modernă)
  purge_protection_enabled   = false  # permite ștergerea completă la terraform destroy
  soft_delete_retention_days = 7      # recuperare accidentală timp de 7 zile
}
```

**3. Atribuie permisiuni (RBAC)**
```hcl
# Tu poți gestiona secretele (necesar la deployment)
resource "azurerm_role_assignment" "kv_admin" {
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.admin_object_id
}

# Containerul poate citi secretele (necesar la runtime)
resource "azurerm_role_assignment" "kv_secrets_user" {
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.managed_identity_principal_id
}
```

**4. Scrie secretul**
```hcl
resource "azurerm_key_vault_secret" "webui_secret_key" {
  name       = "WEBUI-SECRET-KEY"
  value      = random_password.webui_secret_key.result
  depends_on = [azurerm_role_assignment.kv_admin]  # așteptăm permisiunea înainte să scriem
}
```

---

## modules/container_app/

**versions.tf** — de ce există?
```hcl
terraform {
  required_providers {
    azapi = { source = "azure/azapi" }
  }
}
```
Când folosești un provider într-un modul, trebuie să îl declari explicit în modul. Altfel Terraform nu știe de unde să îl ia și caută greșit `hashicorp/azapi` în loc de `azure/azapi`.

**main.tf — Container App Environment Storage**
```hcl
resource "azurerm_container_app_environment_storage" "models" {
  name        = "models"
  account_name = var.storage_account_name
  share_name  = var.models_share_name
  access_key  = var.storage_access_key
  access_mode = "ReadWrite"
}
```
"Înregistrează" File Share-ul în environment ca să poată fi montat în containere.

**main.tf — Container App (secret + DATA_DIR)**
```hcl
secret {
  name                = "webui-secret-key"
  key_vault_secret_id = var.secret_versionless_id   # URI fără versiune
  identity            = var.managed_identity_id     # folosește Managed Identity
}
```
Aceasta e conexiunea cheie securitate: secretul nu are o valoare hardcodată — are un URI spre Key Vault și o identitate cu cui să se autentifice.

```hcl
env {
  name  = "DATA_DIR"
  value = "/tmp"
}
```
SQLite nu funcționează pe Azure File Share (SMB nu suportă POSIX file locking). `DATA_DIR=/tmp` mută baza de date pe storage-ul local al containerului, unde SQLite funcționează normal. Dezavantaj: datele nu persistă după restart.

**main.tf — Procesul SSL în 3 pași**

Provizionarea SSL pentru un domeniu apex (`boschaiops.xyz`) necesită 3 pași distincți — Azure nu acceptă CNAME pe domeniu apex, deci nu putem folosi validarea CNAME.

**Pasul 1 — Adaugă hostname-ul (az CLI via local-exec)**
```hcl
resource "terraform_data" "add_hostname" {
  count = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0
  provisioner "local-exec" {
    command = "az containerapp hostname add --name ${azurerm_container_app.main.name} --resource-group ${var.resource_group_name} --hostname ${var.custom_domain}"
  }
}
```
Azure cere ca hostname-ul să fie înregistrat pe Container App **înainte** de a crea certificatul. Resursa `azurerm` nu expune această operație, deci apelăm direct Azure CLI.

**Pasul 2 — Creează certificatul gestionat (azapi, validare HTTP)**
```hcl
resource "azapi_resource" "managed_certificate" {
  count     = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0
  type      = "Microsoft.App/managedEnvironments/managedCertificates@2023-05-01"
  body = {
    properties = {
      subjectName             = var.custom_domain
      domainControlValidation = "HTTP"
    }
  }
  depends_on = [terraform_data.add_hostname]
}
```
- Folosim **azapi** pentru că `azurerm_container_app_environment_managed_certificate` nu există în azurerm 3.x
- `domainControlValidation = "HTTP"` — Azure validează domeniul printr-un fișier HTTP temporar (funcționează pe domenii apex)
- `body = {...}` (obiect HCL direct) — sintaxa azapi 2.x; în 1.x se folosea `jsonencode({...})`

**Pasul 3 — Leagă certificatul de hostname (azapi_update_resource)**
```hcl
resource "azapi_update_resource" "bind_certificate" {
  count       = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0
  type        = "Microsoft.App/containerApps@2023-05-01"
  resource_id = azurerm_container_app.main.id
  body = {
    properties = {
      configuration = {
        ingress = {
          customDomains = [{
            name          = var.custom_domain
            bindingType   = "SniEnabled"
            certificateId = azapi_resource.managed_certificate[0].id
          }]
        }
      }
    }
  }
}
```
`azapi_update_resource` face un PATCH pe resursa existentă — adaugă binding-ul SSL fără să recreeze Container App-ul.

**De ce `lifecycle { ignore_changes = [ingress] }` pe Container App?**
```hcl
lifecycle {
  ignore_changes = [ingress]
}
```
`azapi_update_resource` modifică blocul `ingress` direct în Azure (prin REST API), nu prin state-ul Terraform. La următorul `plan`, azurerm ar detecta o "diferență" și ar vrea să reverte modificarea. `ignore_changes` îi spune lui Terraform să nu mai compare blocul `ingress` cu ce e în state — azapi-ul rămâne responsabil de acea parte.

**main.tf — Managed Certificate (via azapi)**
Folosim **azapi** pentru că `azurerm_container_app_environment_managed_certificate` nu există în azurerm 3.x. azapi poate apela orice Azure REST API direct — exact aceeași resursă Azure, același rezultat. Aceasta este situația reală în lumea Azure: resurse noi nu sunt mereu în azurerm imediat; azapi este soluția oficială recomandată de Microsoft și HashiCorp.

---

## outputs.tf (root) — "Ce afișează după deploy"

```hcl
output "container_app_fqdn"  → adresa implicită Azure (folosită pentru CNAME)
output "container_app_url"   → URL-ul implicit cu https://
output "custom_domain_url"   → https://boschaiops.xyz (sau mesaj dacă nu e configurat)
output "key_vault_name"      → numele Key Vault-ului creat
output "managed_identity_client_id" → pentru referință
output "dns_instruction"     → instrucțiunea exactă de adăugat în Namecheap
```

---

## terraform.tfvars — "Valorile tale"

```hcl
subscription_id         = "ae22d726-..."
location                = "North Europe"
project_name            = "openwebui"
custom_domain           = "boschaiops.xyz"
configure_custom_domain = false   # true după configurarea DNS
```

**De ce North Europe și nu West Europe?**
La primul deployment, West Europe era la capacitate maximă pentru free tier Container Apps (`ManagedEnvironmentCapacityHeavyUsageError`). Am schimbat în North Europe (Irlanda) care era disponibil.

**`configure_custom_domain = true`**
Terraform creează infrastructura, actualizează DNS automat, așteaptă propagarea DNS și emite certificatul SSL — totul într-un singur `terraform apply`. Nu mai e nevoie să modifici Namecheap sau să rulezi două apply-uri separate.

---

## .gitignore — ce NU merge pe Git

```
terraform.tfvars     ← subscription ID-ul tău
*.tfstate            ← state file cu resurse create
.terraform/          ← providerii descărcați (mari, se regenerează)
```

Pe Git merge `terraform.tfvars.example` — template fără valori reale.
