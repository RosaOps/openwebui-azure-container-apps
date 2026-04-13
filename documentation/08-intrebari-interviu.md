# Întrebări posibile la interviu și răspunsuri

---

## Despre proiect în general

**"Explică-mi ce ai construit."**

> Am deployat OpenWebUI — o interfață web pentru AI — pe Azure Container Apps folosind Terraform ca Infrastructure as Code.
> Infrastructura e organizată pe module Terraform: un modul pentru storage persistent, unul pentru Managed Identity, unul pentru Key Vault cu gestiunea secretelor, și unul pentru Container App cu autoscaling și health probes. Totul e versionat în Git și reproductibil pe orice subscription Azure.

---

## Despre structura cu module

**"De ce ai ales să organizezi codul pe module Terraform?"**

> Modulele separă responsabilitățile — fiecare modul se ocupă de o singură parte a infrastructurii. Asta face codul mai ușor de înțeles, de modificat și de reutilizat. Dacă mâine vreau un al doilea environment (staging, producție), pot instanția aceleași module cu parametri diferiți fără să duplichez cod. E cum se scrie Terraform în echipe și în producție.

**"Cum comunică modulele între ele?"**

> Prin outputs și inputs. Fiecare modul declară ce returnează în `outputs.tf`. Root `main.tf` preia acele outputuri și le pasează ca inputs altor module. De exemplu, `module.storage` returnează `account_name` și `primary_access_key`, pe care `module.container_app` le primește ca variabile. Terraform rezolvă automat ordinea de creare din aceste dependențe.

**"Ce este `versions.tf` din modulul container_app și de ce există?"**

> Când un modul folosește un provider care nu e standard (cum e `azapi`), trebuie să îl declare explicit în modul cu sursa corectă `azure/azapi`. Fără asta, Terraform căuta greșit `hashicorp/azapi` care nu există și dădea eroare la `terraform init`. Lecție învățată din practică.

---

## Despre Terraform

**"De ce ai împărțit codul în mai multe fișiere .tf?"**

> Terraform citește toate fișierele `.tf` din director și le unește. Am ales să le împart tematic pentru lizibilitate: `providers.tf` pentru configurație, `variables.tf` pentru parametri, `main.tf` pentru logică, `outputs.tf` pentru rezultate. Oricine caută configurația unui provider știe exact unde să se uite.

**"Ce face `terraform plan` față de `terraform apply`?"**

> `terraform plan` compară starea curentă (state file) cu codul și afișează ce urmează să se schimbe — fără să facă nimic real. E o previzualizare. `terraform apply` execută efectiv schimbările. Întotdeauna rulez `plan` înainte de `apply` ca să verific că nu fac accidental ceva distructiv.

**"Ce este state file-ul și de ce e important?"**

> State file-ul este memoria lui Terraform — ține evidența tuturor resurselor create și ID-urile lor Azure. Fără el, Terraform nu știe ce există deja. E important să nu fie comis în Git și în producție se stochează remote (ex: Azure Blob Storage) ca toată echipa să folosească același state.

**"Ce este un `depends_on` și când îl folosești?"**

> Terraform determină ordinea de creare din referințe — dacă A folosește ID-ul lui B, știe că B trebuie creat primul. Dar uneori există dependențe invizibile. Am adăugat `depends_on = [module.keyvault]` pe `module.container_app` pentru că RBAC-ul trebuie să fie activ înainte să pornească containerul. Terraform nu vede această dependență din cod, deci o declar explicit.

---

## Despre Azure Container Apps

**"De ce ai ales Container Apps și nu Kubernetes (AKS)?"**

> Pentru o singură aplicație, AKS e overkill — overhead de gestionare a clusterului, costuri mai mari, complexitate mult mai mare. Container Apps oferă același lucru (scaling, ingress, managed certificates) fără să trebuiască să gestionez Kubernetes. E PaaS vs IaaS — mă ocup doar de aplicație, nu de infrastructură.

**"Explică-mi cum funcționează scalingul."**

> Am configurat un CPU-based scale rule: când utilizarea medie CPU depășește 75% din 1 core alocat, Azure pornește automat o replică nouă. Minimul e 1 replică, maximul e 10. Când traficul scade, replicile extra sunt oprite. Tot procesul e automat prin KEDA (Kubernetes Event-Driven Autoscaling) care rulează sub capotă în Container Apps.

**"Ce se întâmplă cu datele dacă containerul se restartează?"**

> Datele sunt persistente — am montat Azure File Shares în container. `/app/backend/data` și `/app/chat_frontend/models` sunt stocate în Azure Storage, nu în containerul efemer. Containerul poate fi restartat sau recreat — toate replicile accesează aceleași date din Storage.

---

## Despre securitate

**"De ce ai ales Managed Identity în loc de un connection string sau API key?"**

> Cu un connection string ai o problemă circulară: unde stochezi credențialul? Dacă îl pui în cod → se vede pe GitHub. Managed Identity rupe acest cerc — nu există nicio parolă. Azure atestă identitatea containerului prin mecanisme interne, Key Vault verifică atestarea și returnează secretul. Zero secrete de gestionat manual.

**"Explică RBAC — ce permisiuni ai dat și de ce?"**

> Două roluri: "Key Vault Administrator" pentru contul meu de Terraform (ca să scrie secretele la deployment) și "Key Vault Secrets User" pentru Managed Identity (ca să citească secretele la runtime). Principiul Least Privilege — containerul are doar minimul necesar: poate citi, nu poate modifica sau șterge.

**"De ce User-Assigned și nu System-Assigned Managed Identity?"**

> User-Assigned e independentă de Container App. Dacă recreez Container App-ul, identitatea și permisiunile pe Key Vault rămân intacte. Cu System-Assigned, la recreerea Container App-ului primesc o identitate nouă și trebuie să reconfigurez toate permisiunile. User-Assigned e mai robust pentru deployments repetate.

---

## Despre networking

**"Cum funcționează custom domain cu SSL?"**

> Am un domeniu la Namecheap. Am adăugat un CNAME care pointează `boschaiops.xyz` spre FQDN-ul implicit Azure. Azure validează că dețin domeniul prin CNAME și emite automat un certificat SSL gestionat — îl reînnoiește și el automat. Eu nu fac nimic manual pentru SSL.

**"De ce ai folosit azapi provider pentru certificat?"**

> Resursa `azurerm_container_app_environment_managed_certificate` există doar în azurerm 4.x. Folosesc 3.x pentru stabilitate (4.x are breaking changes). `azapi` apelează direct Azure REST API — aceeași resursă Azure, același comportament, alt provider. E soluția oficială recomandată de Microsoft și HashiCorp când azurerm nu acoperă o funcționalitate.

**"De ce ai făcut deployment în două faze?"**

> Există o dependență circulară: am nevoie de FQDN-ul Container App-ului ca să configurez DNS, și am nevoie de DNS configurat ca Azure să valideze domeniul și să emită certificatul. Faza 1 deployează fără certificat și îmi dă FQDN-ul. Configurez CNAME manual. Faza 2 creează certificatul.

---

## Despre probleme întâlnite

**"Ai întâmpinat probleme în timpul deploymentului?"**

> Da, câteva interesante:
> 1. **Namespace neînregistrat** (`Microsoft.App`) — subscription nou, trebuia înregistrat explicit
> 2. **Capacity error în West Europe** — Free tier la capacitate maximă, am schimbat în North Europe
> 3. **Resource Group cu resurse parțiale** — după eșecul din West Europe, Azure lăsase un Container App Environment. Am adăugat `prevent_deletion_if_contains_resources = false` în provider
> 4. **`azurerm_container_app_environment_managed_certificate` inexistent în 3.x** — am folosit azapi
> 5. **`versions.tf` lipsă în modul** — Terraform căuta `hashicorp/azapi` în loc de `azure/azapi`, rezolvat prin declararea explicită a provider-ului în modul
>
> Fiecare problemă a avut o soluție logică.

---

## Despre îmbunătățiri

**"Ce ai adăuga la proiect dacă ar fi producție?"**

> 1. **Remote state** — state file în Azure Blob Storage cu locking pentru echipă
> 2. **CI/CD pipeline** — GitHub Actions cu `terraform plan` la PR și `terraform apply` la merge
> 3. **Application Insights** — monitoring, logging, alerting
> 4. **Private networking** — VNet, private endpoints pentru Key Vault și Storage
> 5. **Pinned image version** — `:v0.6.0` în loc de `:main` pentru reproducibilitate
> 6. **Backup policy** — snapshot-uri automate pentru File Shares
