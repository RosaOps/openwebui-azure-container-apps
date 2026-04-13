# Arhitectura proiectului — de ce am ales fiecare componentă

---

## Toate resursele create și rolul lor

### 1. Resource Group — `rg-openwebui-xxxxxx`

Un Resource Group în Azure este ca un **dosar** care conține toate resursele unui proiect.

**De ce îl folosim?**
- Organizare — toate resursele proiectului sunt într-un singur loc
- Ștergere ușoară — dacă ștergi Resource Group-ul, se șterg toate resursele din el
- Costuri — poți vedea cât costă tot proiectul împreună

**De ce are un sufix (`boshaiops23`)?**
Unele resurse Azure trebuie să aibă **nume globale unice** (Storage Account, Key Vault). Sufixul garantează unicitate — dacă doi oameni rulează același cod nu va da conflict. Sufixul e fix în `terraform.tfvars` (nu mai e generat aleatoriu) astfel că la orice `destroy` + `apply` resursele primesc același nume și DNS-ul rămâne valid.

---

### 2. Module storage — Storage Account + 2 File Shares

**Ce este un Storage Account?**
Un cont de stocare în Azure — ca un hard disk în cloud.

**Ce sunt File Share-urile?**
Un File Share este ca o **unitate de rețea** (similar cu un folder partajat). L-am montat în container ca un folder local.

**De ce avem 2 file shares?**
OpenWebUI are două tipuri de date cu scopuri diferite:

| File Share | Montat la | Ce conține |
|------------|-----------|------------|
| `models` | `/app/chat_frontend/models` | Modele AI, configurări frontend |
| `data` | `/app/backend/data` | Fișiere de date ale aplicației (upload-uri, assets) |

**De ce este important storage-ul persistent?**
Containerele sunt **efemere** — când se restartează, tot ce era în ele dispare. Fără volume montate, ai pierde toate fișierele la fiecare restart. Cu File Shares, datele supraviețuiesc.

**Limitare SQLite pe Azure File Share:**
Azure File Share folosește protocolul SMB, care nu suportă POSIX file locking. SQLite are nevoie de file locking pentru a preveni coruperea bazei de date la scrieri concurente. Din acest motiv, containerul are variabila de mediu `DATA_DIR=/tmp` — SQLite rulează pe **storage-ul local al containerului**, nu pe File Share.

Consecință: baza de date (conversații, utilizatori, setări) **nu persistă după restart**. Aceasta este o limitare documentată a soluției actuale. Pentru producție, recomandarea este înlocuirea SQLite cu **Azure Database for PostgreSQL** — acesta suportă conexiuni concurente și persistență completă.

---

### 3. Module identity — User-Assigned Managed Identity

**Ce este o Managed Identity?**
O identitate gestionată de Azure, pe care o atribuim containerului. Cu ea, containerul poate accesa Key Vault **fără parole sau connection strings**.

**De ce User-Assigned și nu System-Assigned?**
- **System-Assigned**: legată de Container App, dispare dacă îl ștergi
- **User-Assigned**: independentă, supraviețuiește dacă recreezi Container App-ul

Am ales User-Assigned pentru că putem configura permisiunile Key Vault **înainte** să creăm Container App-ul. Terraform poate face asta în ordinea corectă.

---

### 4. Module keyvault — Key Vault + RBAC + Secret

**Ce este Azure Key Vault?**
Un seif digital unde stochezi secrete: parole, chei API, certificate.

**Ce secret am stocat?**
`WEBUI_SECRET_KEY` — o cheie aleatorie de 32 caractere generată automat de Terraform. OpenWebUI o folosește pentru a semna sesiunile utilizatorilor.

**De ce nu am pus cheia direct în cod?**
Dacă pui valoarea direct în Terraform → se vede pe GitHub → oricine o poate folosi.
Cu Key Vault → secretul stă în seif → containerul îl citește la runtime prin Managed Identity → nu apare niciodată în cod.

**Cele 2 roluri RBAC atribuite:**
- **Key Vault Administrator** → contul tău (ca Terraform să poată scrie secretul la deployment)
- **Key Vault Secrets User** → Managed Identity (ca containerul să poată citi secretul la runtime)

---

### 5. Azure DNS Zone — `boschaiops.xyz`

Un DNS Zone în Azure este un serviciu care gestionează înregistrările DNS pentru un domeniu.

**De ce am mutat DNS-ul din Namecheap în Azure?**
- Namecheap nu poate fi controlat de Terraform — la orice `destroy` + `apply`, IP-ul environment-ului se schimbă și trebuia actualizat manual
- Azure DNS Zone e gestionat de Terraform → A record și TXT record se actualizează automat la fiecare deploy
- Namecheap e configurat o singură dată cu nameserverele Azure (`ns1-01.azure-dns.com` etc.) — după aceea nu mai e atins niciodată

**Ce conține DNS Zone-ul:**
| Record | Tip | Valoare |
|--------|-----|---------|
| `@` | A | IP-ul Container App Environment (actualizat automat) |
| `asuid` | TXT | ID-ul de verificare al domeniului (actualizat automat) |

---

### 6. Module container_app — Container App Environment + Container App

**Container App Environment** = platforma comună pe care rulează containerele.
**Container App** = containerul care rulează efectiv OpenWebUI.

Configurații importante:
- **Image**: `ghcr.io/open-webui/open-webui:main`
- **Port**: 8080
- **CPU**: 1.0 core, **Memory**: 2Gi
- **Scaling**: min 1 / max 10 replici, CPU 75%
- **Volumes**: cele 2 file shares montate
- **Secret**: `WEBUI_SECRET_KEY` citit din Key Vault via Managed Identity

---

## Cum comunică modulele între ele

```
main.tf (root)
    │
    ├── module.storage
    │       └── outputs: account_name, access_key, share names
    │                           │
    ├── module.identity          │
    │       └── outputs: id, principal_id, client_id
    │                           │
    ├── module.keyvault ◄────────┤ (primește principal_id pentru RBAC)
    │       └── outputs: key_vault_name, secret_versionless_id
    │                           │
    └── module.container_app ◄──┘ (primește toate outputurile de mai sus)
            depends_on: [module.keyvault]
```

**De ce `depends_on = [module.keyvault]` pe container_app?**
Terraform ghicește ordinea din referințe, dar RBAC-ul pe Key Vault trebuie să fie **complet propagat** înainte ca containerul să pornească și să acceseze secretele. Fără `depends_on` explicit, există risc de race condition.

---

## Fluxul complet la runtime

```
1. Utilizatorul accesează boschaiops.xyz

2. DNS Namecheap → CNAME → ca-openwebui-xxx.northeurope.azurecontainerapps.io

3. Azure Container Apps primește request-ul
   ├── Verifică certificatul SSL (Azure Managed Certificate)
   └── Routează la containerul OpenWebUI

4. Containerul la pornire:
   ├── Se autentifică la Key Vault via Managed Identity (fără parole)
   ├── Citește WEBUI_SECRET_KEY din Key Vault
   └── Pornește OpenWebUI cu secretul disponibil ca env var

5. La fiecare request:
   ├── Baza de date SQLite → /tmp (storage local container, nu persistă)
   ├── Datele aplicației → /app/backend/data (Azure File Share, persistent)
   └── Modelele → /app/chat_frontend/models (Azure File Share, persistent)

6. Răspunsul ajunge înapoi la utilizator prin HTTPS
```
