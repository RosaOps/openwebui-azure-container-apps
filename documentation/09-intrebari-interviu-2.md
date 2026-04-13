# Încă 15 întrebări posibile la interviu

---

## Despre Terraform avansat

**"Ce este un `data source` în Terraform și de ce l-ai folosit?"**

> Un `data source` citește informații din resurse existente, fără să le creeze sau modifice. Am folosit `data "azurerm_client_config" "current"` pentru a citi automat tenant_id și object_id-ul contului Azure logat în momentul deploymentului. Alternativa ar fi să le hardcodez ca variabile — mai fragil și mai incomod.

---

**"Ce este `sensitive = true` pe o variabilă și de ce contează?"**

> Marchează o valoare ca sensibilă — Terraform nu o va afișa în output-ul din terminal (apare ca `(sensitive value)`). Am marcat `primary_access_key` al Storage Account-ului și valoarea secretului din Key Vault ca sensitive. E important pentru securitate: dacă cineva îți vede terminalul sau log-urile din CI/CD, nu vede credențialele.

---

**"Cum ai gestiona state file-ul în producție, cu o echipă?"**

> Local state file nu funcționează cu o echipă — doi oameni pot face apply simultan și corupe state-ul. Soluția e **remote state** cu locking:
> ```hcl
> terraform {
>   backend "azurerm" {
>     resource_group_name  = "rg-terraform-state"
>     storage_account_name = "sttfstate"
>     container_name       = "tfstate"
>     key                  = "openwebui.tfstate"
>   }
> }
> ```
> State-ul e stocat în Azure Blob Storage. Locking-ul previne două persoane să facă apply simultan. E best practice standard pentru echipe.

---

**"Ce este `terraform.tfvars.example` și de ce există?"**

> Este un template — arată evaluatorului/colegului ce variabile trebuie completate, fără să expun valorile mele reale. `terraform.tfvars` (cu valorile reale) e gitignored. Oricine clonează repo-ul face `cp terraform.tfvars.example terraform.tfvars` și completează cu propriile valori. E o practică standard pentru proiecte IaC publice sau shared.

---

**"Ce se întâmplă dacă rulezi `terraform apply` de două ori la rând fără schimbări?"**

> Terraform compară starea curentă din state file cu codul și cu resursele Azure reale. Dacă nu e nicio diferență, afișează "No changes. Infrastructure is up-to-date." și nu face nimic. Terraform e **idempotent** — poți rula de oricâte ori, rezultatul e același. Nu creează duplicate.

---

## Despre Azure și arhitectură

**"Ce este un Resource Provider în Azure și de ce a trebuit să înregistrăm `Microsoft.App`?"**

> Azure e organizat pe Resource Providers — fiecare provider gestionează un tip de resursă. `Microsoft.App` gestionează Container Apps, `Microsoft.KeyVault` gestionează Key Vault-uri etc. Pe un subscription nou, nu toți providerii sunt activați implicit — unii trebuie înregistrați manual. `Microsoft.App` e unul dintre ei. Înregistrarea e o singură dată per subscription.

---

**"De ce ai setat `account_replication_type = "LRS"` la Storage Account?"**

> LRS (Locally Redundant Storage) = datele sunt copiate de 3 ori în același datacenter. E cel mai ieftin tier de replicare. Pentru un proiect demo/assessment e suficient. În producție aș folosi GRS (Geo-Redundant Storage) — datele sunt replicate și într-un datacenter din altă regiune, protejând împotriva unui dezastru regional. ZRS (Zone-Redundant) e o altă opțiune — replicare în 3 zone de disponibilitate din aceeași regiune.

---

**"Cum ai verifica că secretul din Key Vault ajunge efectiv în container?"**

> Prin Azure CLI sau Portal:
> ```bash
> az containerapp exec \
>   --name ca-openwebui-xxxxxx \
>   --resource-group rg-openwebui-xxxxxx \
>   --command "printenv WEBUI_SECRET_KEY"
> ```
> Comanda deschide un shell în container și listează variabila de mediu. Dacă afișează o valoare (nu goală), secretul a fost injectat corect din Key Vault.

---

**"Ce este `soft_delete_retention_days` la Key Vault și de ce e setat la 7?"**

> Soft delete înseamnă că un secret sau Key Vault "șters" nu dispare imediat — rămâne în stare "deleted" pentru perioada configurată (7 zile la noi). În această perioadă poate fi recuperat dacă a fost șters accidental. Avem și `purge_soft_delete_on_destroy = true` în provider, care curăță complet la `terraform destroy` — altfel Key Vault-ul ar rămâne în stare "soft deleted" și nu ai putea recrea un altul cu același nume timp de 7 zile.

---

**"Ce diferență e între `transport = "auto"` și `transport = "http"` la ingress?"**

> `auto` = Azure detectează automat protocolul. Dacă clientul suportă HTTP/2, folosește HTTP/2 (mai rapid, multiplexing). Dacă nu, fallback la HTTP/1.1. `http` forțează HTTP/1.1. Am ales `auto` pentru că e mai performant fără niciun dezavantaj — browserele moderne suportă HTTP/2.

---

## Despre decizii de design

**"De ce ai generat `WEBUI_SECRET_KEY` cu Terraform în loc să îl ceri ca variabilă?"**

> Dacă aș fi cerut-o ca variabilă, utilizatorul ar trebui să genereze manual o parolă sigură și să o pună în terraform.tfvars. E mai ușor să greșești (parole slabe, reutilizate). Prin `random_password`, Terraform generează automat o cheie criptografic sigură de 32 caractere. Mai simplu, mai sigur, mai puțin loc de greșeli umane.

---

**"Ce este `revision_mode = "Single"` și când ai folosi "Multiple"?"**

> `Single` = există o singură revizie activă la un moment dat. Când faci un nou deployment, noua versiune înlocuiește complet pe cea veche. `Multiple` = poți avea mai multe revizii active simultan cu traffic splitting — ex: 90% din trafic la versiunea stabilă, 10% la versiunea nouă (canary deployment / blue-green). Am ales `Single` pentru simplitate — nu avem nevoie de canary releases pentru un proiect demo.

---

**"Cum ai face update la OpenWebUI la o versiune nouă?"**

> Schimb tag-ul imaginii în `container_app.tf`:
> ```hcl
> image = "ghcr.io/open-webui/open-webui:v0.4.0"  # în loc de :main
> ```
> Și ruleze `terraform apply`. Azure Container Apps creează o nouă revizie cu noua imagine și o activează. Datele rămân intacte pentru că sunt în Azure File Shares, nu în container. Zero downtime dacă ai `min_replicas >= 1`.

---

**"De ce `min_replicas = 1` și nu 0 — nu ar fi mai ieftin cu 0?"**

> Cu 0, când nu e nimeni pe site Azure oprește containerul complet. Când vine primul utilizator, Azure trebuie să pornească containerul de la zero — proces care durează 20-60 secunde pentru OpenWebUI (**cold start**). Utilizatorul vede un loading îndelungat sau timeout. Cu min = 1, există mereu o instanță pornită, primul request e servit instant. Costul diferenței e mic (o replică mică idle) față de experiența proastă a utilizatorului cu cold start.

---

**"Ce ai face dacă `terraform apply` eșuează la jumătate?"**

> Terraform e parțial idempotent la eșecuri. Resursele create cu succes rămân în state file. La un nou `terraform apply`, Terraform știe ce s-a creat deja și încearcă doar ce a mai rămas. Nu recreează ce există deja. Dacă eroarea e legată de o resursă specifică, investighez eroarea (de obicei în output), rezolv cauza (ex: înregistrez un namespace, schimb regiunea) și rulezi din nou `terraform apply`. Exact asta am făcut la erorile cu `Microsoft.App` și cu capacity în West Europe.

---

## Bonus — întrebare deschisă

**"Ce ai adăuga la acest proiect dacă ai mai fi avut timp?"**

> Câteva îmbunătățiri valoroase:
> 1. **Remote backend** pentru state file în Azure Blob Storage — esențial pentru echipă
> 2. **Application Insights** — monitoring, logging, alerting pentru aplicație
> 3. **Private networking** — Container App în VNet, Key Vault cu private endpoint, fără acces public
> 4. **CI/CD pipeline** — GitHub Actions care rulează `terraform plan` la PR și `terraform apply` la merge în main
> 5. **Ollama integration** — un al doilea Container App cu un model AI local, conectat la OpenWebUI
> 6. **Backup policy** — snapshot-uri automate pentru File Shares
> 7. **Pinned image version** — `:v0.3.x` în loc de `:main` pentru reproducibilitate
