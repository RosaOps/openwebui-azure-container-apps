# Securitate — Managed Identity și Key Vault

---

## Problema pe care o rezolvăm

OpenWebUI are nevoie de o cheie secretă (`WEBUI_SECRET_KEY`) pentru a semna sesiunile utilizatorilor.

**Varianta naivă (GREȘITĂ):**
```hcl
env {
  name  = "WEBUI_SECRET_KEY"
  value = "super-secret-key-123"  # ❌ NICIODATĂ așa
}
```

Probleme:
- Apare în codul sursă pe GitHub — oricine vede repo-ul vede secretul
- Apare în Terraform state file
- Dacă rotatezi cheia, trebuie să modifici codul și să faci redeploy

**Varianta corectă (ce am implementat):**
Secretul stă în Key Vault. Containerul îl citește la runtime fără ca valoarea să apară în cod.

---

## Managed Identity — autentificare fără parole

### Problema clasică
Dacă aplicația ta vrea să acceseze Key Vault, trebuie să se autentifice. Cum?

**Metoda veche (Service Principal cu secret):**
```
Aplicație → "Sunt eu, aplicația X, parola mea e ABC123" → Key Vault
```
Problema: Unde stochezi parola ABC123? Dacă o pui în cod → problemă de securitate. Dacă o pui în altă parte → ciclul se repetă.

**Metoda modernă (Managed Identity):**
```
Aplicație → "Sunt eu, containerul X, Azure confirmă identitatea mea" → Key Vault
```
Nu există parolă. Azure gestionează identitatea în mod automat. Containerul dovedește cine este prin metadate Azure interne — imposibil de falsificat din exterior.

### User-Assigned vs System-Assigned

**System-Assigned Managed Identity:**
```
Container App ──creeaza──► Identity (legată de Container App)
Container App ──șterge──► Identity dispare
```
Problema: Dacă recreezi Container App-ul (ex: în alt deployment), identitatea e nouă și pierzi toate permisiunile configurate.

**User-Assigned Managed Identity (ce am folosit):**
```
Identity (independentă) ──atribuita──► Container App
Identity supraviețuiește dacă Container App e recreat
```
Avantaj: Poți configura permisiunile în Key Vault ÎNAINTE să creezi Container App-ul. Terraform poate face asta în ordinea corectă.

### Cum funcționează tehnic

Când containerul pornește și vrea să citească din Key Vault:
1. Containerul face un request la un endpoint special intern Azure: `http://169.254.169.254/metadata/identity/...`
2. Azure returnează un token de acces temporar semnat criptografic
3. Containerul folosește token-ul pentru a se autentifica la Key Vault
4. Key Vault verifică token-ul, confirmă că identitatea are rolul "Key Vault Secrets User"
5. Key Vault returnează valoarea secretului

Totul se întâmplă automat în câteva milisecunde. Nu există parolă în niciunul din pașii de mai sus.

---

## Azure Key Vault — seiful digital

### Ce stochează Key Vault

Key Vault poate stoca 3 tipuri de date:
- **Secrets** — valori text (parole, connection strings, API keys) — **asta folosim noi**
- **Keys** — chei criptografice (RSA, EC) — pentru operații de criptare
- **Certificates** — certificate SSL/TLS

### Configurarea Key Vault din proiect

```hcl
resource "azurerm_key_vault" "main" {
  enable_rbac_authorization  = true   # folosim RBAC, nu access policies
  purge_protection_enabled   = false  # permite ștergerea completă
  soft_delete_retention_days = 7      # 7 zile pentru recuperare accidentală
}
```

**`enable_rbac_authorization = true`**
Există două sisteme de control al accesului în Key Vault:
- **Access Policies** (metoda veche): configurezi direct pe Key Vault cine are acces la ce
- **RBAC** (metoda nouă, recomandata): folosești roluri Azure standard

Am ales RBAC pentru că:
- E consistent cu restul Azure (aceleași roluri, același sistem)
- E mai ușor de auditat
- E recomandat de Microsoft pentru deployments noi

**`purge_protection_enabled = false`**
Dacă ar fi `true`, nu ai putea șterge complet Key Vault-ul timp de 90 de zile. Am setat `false` pentru că e un proiect demo și vrem să putem face `terraform destroy` ușor.

**`soft_delete_retention_days = 7`**
Dacă ștergi accidental un secret, îl poți recupera timp de 7 zile. E o plasă de siguranță.

---

## RBAC — cine are acces la ce

RBAC = Role-Based Access Control. În loc să dai permisiuni individuale, dai un **rol** care vine cu un set de permisiuni predefinite.

### Rolurile pe care le-am atribuit

**Key Vault Administrator → Contul tău (terraform)**
```hcl
resource "azurerm_role_assignment" "kv_admin" {
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  # object_id = ID-ul contului tău Azure logat
}
```
Permisiuni incluse: citire, scriere, ștergere secrete + gestionare Key Vault.
De ce: Terraform trebuie să scrie secretul `WEBUI-SECRET-KEY` în Key Vault în timpul deploymentului.

**Key Vault Secrets User → Managed Identity (containerul)**
```hcl
resource "azurerm_role_assignment" "kv_secrets_user" {
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
  # principal_id = ID-ul Managed Identity-ului atribuit containerului
}
```
Permisiuni incluse: **doar citire** secrete.
De ce: Containerul are nevoie doar să citească `WEBUI_SECRET_KEY`, nu să modifice sau să șteargă nimic.

**Principiul Least Privilege (cel mai mic privilegiu necesar):**
Containerul are doar ce îi trebuie — citire. Nu poate modifica, nu poate șterge, nu poate vedea alte tipuri de resurse. Dacă containerul ar fi compromis, atacatorul ar putea doar citi secretele existente, nu șterge sau modifica.

---

## Cum ajunge secretul în container — fluxul complet

```
TERRAFORM APPLY:
1. Terraform generează random_password (32 chars)
2. Terraform creează Key Vault
3. Terraform atribuie rol "Key Vault Administrator" contului tău
4. Terraform scrie secretul în Key Vault: WEBUI-SECRET-KEY = "xyz..."
5. Terraform atribuie rol "Key Vault Secrets User" Managed Identity-ului
6. Terraform creează Container App cu referința:
   secret {
     name                = "webui-secret-key"
     key_vault_secret_id = "https://kv-openwebui-xxx.vault.azure.net/secrets/WEBUI-SECRET-KEY"
     identity            = managed_identity_id
   }

LA RUNTIME (când containerul pornește):
7. Azure Container Apps vede că există un secret referit din Key Vault
8. Folosind Managed Identity, se autentifică la Key Vault
9. Citește valoarea secretului WEBUI-SECRET-KEY
10. Injectează valoarea ca variabilă de mediu: WEBUI_SECRET_KEY="xyz..."
11. Containerul OpenWebUI pornește cu WEBUI_SECRET_KEY disponibil

REZULTAT:
- Valoarea secretului nu apare niciodată în cod
- Nu apare în terraform.tfvars
- Nu apare vizibil în state file (e marcat ca sensitive)
- Containerul o are disponibilă ca orice env var
```

---

## De ce `versionless_id` și nu `id`?

```hcl
key_vault_secret_id = azurerm_key_vault_secret.webui_secret_key.versionless_id
```

Fiecare secret din Key Vault are versiuni:
- `id` = URI cu versiune specifică: `.../WEBUI-SECRET-KEY/7b45eeea...`
- `versionless_id` = URI fără versiune: `.../WEBUI-SECRET-KEY`

Dacă folosești `id` (cu versiune):
- Containerul va folosi mereu acea versiune specifică
- Dacă rotezi secretul (schimbi valoarea), trebuie să actualizezi și referința

Dacă folosești `versionless_id` (fără versiune):
- Containerul va folosi mereu **cea mai recentă versiune**
- Rotirea secretului e transparentă — containerul preia automat noua valoare
