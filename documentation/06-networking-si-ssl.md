# Networking, Custom Domain și SSL

---

## Cum funcționează DNS — de la domeniu la container

Când scrii `boschaiops.xyz` în browser, se întâmplă următoarele:

```
1. Browserul întreabă serverul DNS: "Care e IP-ul pentru boschaiops.xyz?"

2. Nameserverele Azure DNS răspund (ns1-01.azure-dns.com etc.):
   "boschaiops.xyz are A record → 20.105.125.169"

3. Browserul se conectează la acel IP

4. Azure Container Apps primește request-ul și îl routează la containerul OpenWebUI
```

### Azure DNS Zone — de ce am mutat DNS-ul din Namecheap

**Problema cu Namecheap:** La fiecare `destroy` + `apply`, Container App Environment primește un IP nou. Trebuia actualizat manual A record-ul în Namecheap — imposibil de automatizat.

**Soluția: Azure DNS Zone gestionat de Terraform.**

Namecheap e configurat o singură dată cu nameserverele Azure:
```
ns1-01.azure-dns.com
ns2-01.azure-dns.net
ns3-01.azure-dns.org
ns4-01.azure-dns.info
```

De acum, Terraform gestionează automat:
- **A record** `@` → IP-ul Container App Environment (se actualizează la fiecare apply)
- **TXT record** `asuid` → ID-ul de verificare al domeniului (se actualizează la fiecare apply)

### De ce A record și nu CNAME?

`boschaiops.xyz` este un **domeniu apex** (fără subdomain, fără `www`). Standardul DNS nu permite CNAME pe domenii apex. Azure Container Apps expune un IP static al environment-ului — folosim A record direct.

---

## SSL și HTTPS — de ce avem nevoie

HTTP = comunicare nesecurizată. Datele circulă în text clar — oricine "ascultă" pe rețea le poate citi.

HTTPS = HTTP + TLS (Transport Layer Security). Datele sunt criptate. Nimeni nu poate citi ce se transmite fără cheia de decriptare.

**De ce e obligatoriu HTTPS:**
- Browserele moderne marchează HTTP ca "Not Secure"
- Parolele și sesiunile utilizatorilor trebuie protejate
- Este cerință standard în 2024

### Certificatul SSL

Un certificat SSL dovedește că:
1. Serverul este cu adevărat `boschaiops.xyz` (nu un impostor)
2. Comunicarea e criptată

**Cine emite certificatele?**
Certificate Authorities (CA) — organizații de încredere care verifică că ești proprietarul domeniului și emit un certificat semnat. Browserele au o listă de CA-uri de încredere.

**Azure Managed Certificate:**
Azure Container Apps poate emite și gestiona certificatul în mod automat.
Noi nu trebuie să:
- Cumpărăm un certificat
- Îl reînnoim manual (certificatele expiră în general la 90 de zile sau 1 an)
- Îl configurăm pe server

Azure face totul automat, inclusiv reînnoirea.

---

## Cum provizionează Azure certificatul — procesul de validare

Înainte să emită un certificat pentru `boschaiops.xyz`, Azure trebuie să verifice că ești proprietarul domeniului. Altfel oricine ar putea cere un certificat pentru orice domeniu.

**Validarea prin HTTP (ce folosim noi):**

```
1. Azure generează un fișier de validare la un URL temporar pe container app
   (ex: http://boschaiops.xyz/.well-known/acme-challenge/...)

2. Azure verifică că fișierul e accesibil:
   - Accesează URL-ul
   - Dacă răspunsul e corect → validare reușită

3. Azure emite certificatul de la o CA de încredere

4. Certificatul e instalat automat pe load balancer-ul Azure

5. Orice request HTTPS la boschaiops.xyz e decriptat automat
```

**De ce folosim validare HTTP și nu CNAME sau TXT?**
- `boschaiops.xyz` este un **domeniu apex** (fără www). Standardul DNS nu permite CNAME pe domenii apex — Azure returnează eroare `InvalidValidationMethod` dacă încerci.
- TXT validation: funcționează, dar necesită propagare DNS suplimentară și am întâmpinat timeout-uri în practică (>30 minute)
- HTTP validation: Azure accesează direct containerul → rapid, funcționează pe domenii apex, nu necesită modificări DNS suplimentare față de CNAME-ul deja configurat

---

## Deploy într-un singur apply

Cu Azure DNS gestionat de Terraform, tot procesul e complet automat:

```
terraform apply
  │
  ├── Creează Container App Environment → obține IP static
  ├── Creează Azure DNS Zone
  ├── Actualizează A record @ → IP static (automat)
  ├── Actualizează TXT record asuid → verification ID (automat)
  │
  ├── wait_for_dns: polling până boschaiops.xyz rezolvă la IP-ul corect
  │   (verifică la 8.8.8.8 la fiecare 15 secunde, max 10 minute)
  │
  ├── add_hostname: az containerapp hostname add boschaiops.xyz
  ├── managed_certificate: Azure validează prin HTTP → emite certificatul
  └── bind_certificate: leagă certificatul (SniEnabled)

→ boschaiops.xyz funcționează cu HTTPS
```

**La `destroy` + `apply`** — același singur comand:
```
terraform destroy  → purge Key Vault automat, remove hostname automat
terraform apply    → recreează tot, actualizează DNS, emite cert
```
Nu se atinge Namecheap niciodată după configurarea inițială a nameserverelor.

---

## Codul pentru custom domain — cei 3 pași explicați

**Pasul 1 — Înregistrarea hostname-ului (obligatorie înainte de certificat)**
```hcl
resource "terraform_data" "add_hostname" {
  count = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0
  provisioner "local-exec" {
    command = "az containerapp hostname add --name ca-openwebui-xxx --resource-group rg-... --hostname boschaiops.xyz"
  }
}
```
Azure refuză crearea certificatului dacă hostname-ul nu e deja asociat containerului. Această resursă apelează Azure CLI local pentru a face asocierea. `terraform_data` e o resursă "goală" din Terraform care există doar pentru a rula provisioneri.

**Pasul 2 — Certificatul gestionat (via azapi, validare HTTP)**
```hcl
resource "azapi_resource" "managed_certificate" {
  count = var.configure_custom_domain && var.custom_domain != "" ? 1 : 0
  type  = "Microsoft.App/managedEnvironments/managedCertificates@2023-05-01"
  body = {
    properties = {
      subjectName             = var.custom_domain  # "boschaiops.xyz"
      domainControlValidation = "HTTP"             # validare prin HTTP (funcționează pe apex)
    }
  }
  depends_on = [terraform_data.add_hostname]
}
```
`body = {...}` este sintaxa azapi 2.x — obiect HCL direct, fără `jsonencode`.

**Pasul 3 — Legarea certificatului (PATCH pe Container App via azapi_update_resource)**
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
`azapi_update_resource` face un PATCH pe resursa existentă — modifică doar câmpurile specificate, fără să recreeze containerul.

**`certificate_binding_type = "SniEnabled"`:**
SNI = Server Name Indication. O extensie TLS care permite unui singur IP să servească certificate pentru mai multe domenii. Este standardul modern, suportat de toate browserele actuale.

**De ce `lifecycle { ignore_changes = [ingress] }` pe Container App:**
`azapi_update_resource` modifică blocul `ingress` prin REST API, în afara state-ului azurerm. La `terraform plan`, azurerm ar detecta o diferență și ar reverta binding-ul SSL. `ignore_changes = [ingress]` oprește această "luptă" — azurerm nu mai atinge blocul ingress, azapi rămâne responsabil de el.

---

## De ce am folosit azapi pentru certificat

Cerința assessment-ului: `azurerm provider version >= 3.0`

Resursa `azurerm_container_app_environment_managed_certificate` a fost adăugată în azurerm versiunea **4.x**.

Noi folosim azurerm 3.x (ultimul 3.x este 3.117.1).

**Soluția: azapi provider**
- `azapi` poate apela orice Azure REST API direct
- Exact aceeași resursă Azure, același rezultat
- Demonstrează cunoașterea ecosistemului Azure Terraform

Aceasta e o situație reală în lumea Azure: uneori resurse noi sau funcționalități noi nu sunt încă în azurerm. azapi este "soluția de bypass" oficială recomandată de Microsoft și HashiCorp.
