# Dificultăți întâmpinate, soluții și lecții învățate

---

## 1. Namespace Microsoft.App neînregistrat

**Problema:** La primul `terraform apply`, a apărut eroarea:
> `The subscription is not registered to use namespace 'Microsoft.App'`

**Cauza:** Azure necesită înregistrarea explicită a unor namespace-uri (grupuri de servicii) înainte de a putea crea resurse din ele. Container Apps face parte din `Microsoft.App`, care nu era activat pe subscripție.

**Soluția:**
```bash
az provider register --namespace Microsoft.App
```
Înregistrarea durează câteva minute. După aceea, `terraform apply` a funcționat.

**Lecție:** Când lucrezi pe o subscripție nouă sau cu servicii Azure mai noi, verifică că namespace-urile necesare sunt înregistrate. Poți vedea statusul cu `az provider show --namespace Microsoft.App`.

---

## 2. Capacitate West Europe epuizată (ManagedEnvironmentCapacityHeavyUsageError)

**Problema:** Deployment-ul a eșuat cu:
> `ManagedEnvironmentCapacityHeavyUsageError: The region West Europe is currently experiencing heavy usage`

**Cauza:** Planul de consum gratuit pentru Azure Container Apps era la capacitate maximă în West Europe.

**Soluția:** Am schimbat `location = "North Europe"` în `terraform.tfvars`. Irlanda (North Europe) era disponibil.

**Lecție:** Regiunile Azure pot fi la capacitate maximă, mai ales pe tier-ul gratuit. Dacă o regiune nu funcționează, încearcă alta apropiată.

---

## 3. Lock file hashicorp/azapi în loc de azure/azapi

**Problema:** `terraform init` descărca provider-ul greșit sau dădea erori legate de azapi.

**Cauza:** Fișierul `.terraform.lock.hcl` era generat cu sursa greșită (`hashicorp/azapi`) din cauza unei declarații lipsă în modul.

**Soluția:**
1. Șters `.terraform.lock.hcl`
2. Creat `modules/container_app/versions.tf` cu declarația explicită:
```hcl
terraform {
  required_providers {
    azapi = { source = "azure/azapi" }
  }
}
```
3. Rulat `terraform init` din nou

**Lecție:** Când folosești un provider non-HashiCorp într-un modul, trebuie declarat explicit în modulul respectiv. Altfel Terraform caută `hashicorp/<provider>` în loc de sursa corectă.

---

## 4. Sintaxa body azapi 2.x vs 1.x

**Problema:** `terraform apply` dădea eroare la blocul `azapi_resource`:
> `body must be a string`

**Cauza:** Codul folosea `body = jsonencode({...})` (sintaxa azapi 1.x), dar provider-ul instalat era azapi 2.x, care schimbase sintaxa incompatibil.

**Soluția:** Înlocuit `jsonencode({...})` cu obiect HCL direct:
```hcl
# Înainte (azapi 1.x):
body = jsonencode({
  properties = { subjectName = var.custom_domain }
})

# După (azapi 2.x):
body = {
  properties = { subjectName = var.custom_domain }
}
```
Și actualizat `version = ">= 2.0.0"` în ambele `providers.tf` și `modules/container_app/versions.tf`.

**Lecție:** Breaking changes între versiuni majore sunt frecvente. Când specifici versiuni de provideri, documentează de ce ai ales acea versiune. Versiunile `>= X.Y.Z` fără limită superioară pot "sări" la versiuni majore noi cu breaking changes.

---

## 5. Validare CNAME imposibilă pe domeniu apex

**Problema:** La crearea certificatului SSL, Azure a returnat:
> `InvalidValidationMethod: CNAME validation is not supported for apex domains`

**Cauza:** `boschaiops.xyz` este un domeniu apex (fără subdomain). Standardul DNS nu permite CNAME records pe domenii apex — este o limitare fundamentală a protocolului DNS. Azure știe asta și refuză să încerce validarea CNAME pentru apex.

**Soluția:** Schimbat `domainControlValidation = "CNAME"` în `domainControlValidation = "HTTP"`. Azure accesează un URL temporar pe containerul activ pentru a valida proprietatea domeniului.

**Lecție:** Domenii apex vs subdomenii au comportamente diferite în DNS și în Azure. Dacă ai `www.domeniu.xyz` poți folosi CNAME; dacă ai `domeniu.xyz` (fără www) trebuie să folosești HTTP sau TXT validation.

---

## 6. RequireCustomHostnameInEnvironment — ordinea operațiilor SSL

**Problema:** La crearea certificatului, Azure a returnat:
> `RequireCustomHostnameInEnvironment: The custom hostname must be added to the container app before creating the certificate`

**Cauza:** Azure are un proces SSL în 3 pași care trebuie respectat strict:
1. Înregistrează hostname-ul pe Container App
2. Creează certificatul
3. Leagă certificatul de hostname

Codul inițial omitea pasul 1.

**Soluția:** Adăugat resursă `terraform_data` cu `local-exec` provisioner care rulează az CLI:
```hcl
resource "terraform_data" "add_hostname" {
  provisioner "local-exec" {
    command = "az containerapp hostname add --name ... --hostname boschaiops.xyz"
  }
}
```
`azapi_resource.managed_certificate` are `depends_on = [terraform_data.add_hostname]` pentru a garanta ordinea.

**Lecție:** Azure Container Apps SSL nu e o operație atomică. Resursa `azurerm_container_app_environment_managed_certificate` nu există în azurerm 3.x, iar documentația Azure nu menționează clar că hostname-ul trebuie adăugat separat înainte de certificat.

---

## 7. Conflict azurerm vs azapi_update_resource pe blocul ingress

**Problema:** După `terraform apply` cu succes (HTTPS funcționa), la un `terraform plan` următor Terraform detecta o "diferență" și voia să reverte binding-ul SSL creat de azapi.

**Cauza:** `azapi_update_resource` modifică resursa Azure direct prin REST API (PATCH), în afara state-ului gestionat de azurerm. La `plan`, azurerm compara starea din Azure cu starea sa din `.tfstate` și vedea o modificare neașteptată pe blocul `ingress`.

**Soluția:** Adăugat `lifecycle { ignore_changes = [ingress] }` pe `azurerm_container_app`:
```hcl
lifecycle {
  ignore_changes = [ingress]
}
```
Astfel azurerm nu mai atinge blocul `ingress` — azapi rămâne singurul responsabil de el.

**Lecție:** Când folosești două provideri (azurerm + azapi) pe aceeași resursă Azure, trebuie să stabilești clar "cine e responsabil de ce". `lifecycle { ignore_changes }` este mecanismul Terraform pentru a delega controlul unei secțiuni altui provider.

---

## 8. Convertire path-uri de Git Bash (MSYS_NO_PATHCONV)

**Problema:** Comenzile az CLI cu ID-uri de resurse Azure eșuau în Git Bash:
> `az resource delete --ids /subscriptions/ae22.../resourceGroups/...`
> Git Bash transforma `/subscriptions/` în `C:/Program Files/Git/subscriptions/`

**Cauza:** Git Bash (MSYS2) convertește automat string-urile care par a fi path-uri Unix în path-uri Windows. ID-urile de resurse Azure `/subscriptions/.../resourceGroups/...` arată exact ca path-uri Unix.

**Soluția:**
```bash
MSYS_NO_PATHCONV=1 az resource delete --ids /subscriptions/...
```
Variabila de mediu `MSYS_NO_PATHCONV=1` dezactivează conversia pentru comanda respectivă.

**Lecție:** Pe Windows cu Git Bash, az CLI comenzile cu Azure resource IDs necesită `MSYS_NO_PATHCONV=1`. Alternativ, folosește PowerShell sau CMD unde problema nu există.

---

## 9. SQLite incompatibil cu Azure File Share (SMB)

**Problema:** OpenWebUI pornea dar afișa eroarea:
> `unable to open database file` sau `database is locked`

**Cauza:** OpenWebUI stochează implicit baza de date SQLite la `/app/backend/data` — care era montat pe Azure File Share. Azure File Share folosește protocolul SMB, care nu suportă POSIX advisory file locking (flock/fcntl). SQLite necesită file locking pentru a preveni coruperea datelor la scrieri concurente.

**Prima încercare de soluție:** `DATA_DIR=/tmp/openwebui` — a eșuat cu `unable to open database file` pentru că directorul nu exista în container.

**Soluția finală:** `DATA_DIR=/tmp` — `/tmp` există întotdeauna și SQLite funcționează normal pe storage local.

**Dezavantaj documentat:** Baza de date nu persistă după restart. Conversațiile și setările utilizatorilor se pierd.

**Soluția corectă pe termen lung:** Înlocuirea SQLite cu Azure Database for PostgreSQL. OpenWebUI suportă PostgreSQL nativ prin variabila de mediu `DATABASE_URL`. PostgreSQL suportă conexiuni concurente și stochează datele persistent în Azure.

**Lecție:** SMB (Azure File Share, Windows File Share) nu suportă POSIX file locking. Orice aplicație care depinde de SQLite sau alte baze de date bazate pe file locking va eșua pe Azure File Share. Aceasta nu este o limitare a Azure, ci a protocolului SMB.

---

## 10. Certificat blocat (CertificateInUse) la ștergere

**Problema:** La `terraform destroy`, ștergerea certificatului eșua cu:
> `CertificateInUse: The certificate is currently in use and cannot be deleted`

**Cauza:** Certificatul era legat de hostname-ul containerului. Azure nu permite ștergerea unui certificat care e activ pe o resursă.

**Soluția:** Dezlegat manual hostname-ul înainte de ștergere:
```bash
az containerapp hostname delete --name ca-openwebui-xxx --resource-group rg-... --hostname boschaiops.xyz
MSYS_NO_PATHCONV=1 az resource delete --ids /subscriptions/.../managedCertificates/cert-openwebui
```
Apoi `terraform destroy` a funcționat.

**Lecție:** Resursele gestionate parțial de azapi (în afara state-ului azurerm) pot necesita cleanup manual. Când folosești `azapi_update_resource` pentru binding SSL, `terraform destroy` poate lăsa urme care trebuie șterse manual.

---

## 11. Sufix random → sufix fix în tfvars

**Problema:** `random_string` genera un sufix nou la fiecare `destroy` + `apply` → FQDN nou → IP nou → DNS manual în Namecheap la fiecare redeploy.

**Soluția:** Înlocuit `random_string` cu o variabilă `suffix` în `terraform.tfvars` cu valoare fixă (`boshaiops23`). Resursele au mereu același nume — DNS-ul rămâne valid.

**Lecție:** `random_string` e util pentru deployuri unice (CI/CD, PR environments). Pentru infrastructură stabilă cu DNS configurat, sufixul trebuie să fie predictibil și stabil.

---

## 12. DNS gestionat manual în Namecheap → Azure DNS Zone

**Problema:** La fiecare `destroy` + `apply`, IP-ul Container App Environment se schimba. A record-ul și TXT record-ul (`asuid`) trebuiau actualizate manual în Namecheap — imposibil de automatizat complet.

**Soluția:** Creat `azurerm_dns_zone` în Terraform cu `azurerm_dns_a_record` și `azurerm_dns_txt_record`. Nameserverele din Namecheap au fost schimbate la Azure DNS (`ns1-01.azure-dns.com` etc.) o singură dată. Acum Terraform actualizează automat DNS-ul la fiecare apply.

**Lecție:** Dacă DNS-ul trebuie să se sincronizeze cu infrastructura Terraform, mută-l într-un provider Terraform (Azure DNS, Cloudflare, Route53). Managementul manual al DNS în registrar e o sursă constantă de erori în redeploy-uri.

---

## 13. Certificat SSL eșuează dacă rulează înainte de propagarea DNS

**Problema:** `azapi_resource.managed_certificate` și `azurerm_dns_a_record` rulau în paralel în același apply. Certificatul încerca validarea HTTP înainte ca A record-ul să se propage → `FailedARecordValidation`.

**Soluția:** Adăugat `terraform_data.wait_for_dns` — un provisioner care face polling la DNS (8.8.8.8) la fiecare 15 secunde, până domeniul rezolvă la IP-ul corect (max 10 minute). `add_hostname` și implicit certificatul depind de această resursă.

**Lecție:** Propagarea DNS nu e instantanee — între crearea unui record și momentul în care e vizibil global pot trece secunde sau minute. Orice proces care depinde de DNS trebuie să aștepte activ confirmarea propagării, nu să presupună că e gata.

---

## 14. Key Vault soft-delete blochează redeployul cu același nume

**Problema:** La `terraform destroy` + `terraform apply` cu același sufix, Key Vault intra în soft-delete (7 zile). La apply, Azure returna `VaultAlreadyExists` — numele era rezervat de vault-ul șters.

**Soluția:** Adăugat `terraform_data.purge_key_vault` cu destroy provisioner care rulează `az keyvault purge` automat când Terraform șterge Key Vault-ul.

**Lecție:** Key Vault (și alte resurse Azure cu soft-delete) rezervă numele după ștergere. Pentru redeploy cu același nume, purge-ul trebuie automatizat. Alternativ, se poate folosi un sufix diferit la fiecare deploy dacă nu ai nevoie de DNS stabil.

---

## Rezumat — ce am învățat

| Domeniu | Lecție |
|---------|--------|
| **Azure DNS** | Domenii apex nu suportă CNAME; folosește A record + HTTP validation |
| **DNS management** | Mută DNS în Azure DNS Zone gestionat de Terraform pentru redeploy complet automat |
| **Propagare DNS** | Polling activ înainte de operații care depind de DNS — nu presupune că e gata |
| **Sufix stabil** | Folosește sufix fix în tfvars pentru infrastructură cu DNS; random_string e pentru deployuri efemere |
| **Azure Container Apps SSL** | Procesul are 3 pași distincți care trebuie respectați în ordine |
| **Key Vault soft-delete** | Purge automat la destroy pentru a putea reutiliza același nume |
| **Terraform + azapi** | Când doi provideri gestionează aceeași resursă, `lifecycle { ignore_changes }` delimitează responsabilitățile |
| **azapi 2.x** | Sintaxa `body` s-a schimbat incompatibil față de 1.x; documentează versiunile |
| **SMB / Azure File Share** | Nu suportă POSIX file locking — SQLite nu funcționează |
| **Terraform modules + provideri non-HashiCorp** | Declară explicit în `versions.tf` al modulului |
| **Azure namespace registration** | Namespace-uri noi trebuie înregistrate explicit pe subscripție |
