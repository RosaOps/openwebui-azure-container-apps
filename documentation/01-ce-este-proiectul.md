# Ce este acest proiect și de ce există

---

## Contextul — ce ți s-a cerut

Ai primit un assessment tehnic care spune:
> "Deployează OpenWebUI pe Azure Container Apps folosind Terraform."

Adică: rulează o aplicație AI în cloud, folosind cod ca să creezi toată infrastructura.

---

## Ce este OpenWebUI

OpenWebUI este o **interfață web pentru modele AI** — practic un ChatGPT pe care îl găzduiești tu.

Arată exact ca ChatGPT: o fereastră de chat unde scrii mesaje și primești răspunsuri de la un model AI.

**De ce există OpenWebUI?**
Multe companii și persoane vor să folosească modele AI (cum ar fi GPT, LLaMA, Mistral) dar nu vor să depindă de OpenAI sau să trimită datele lor la un serviciu extern. Cu OpenWebUI poți rula totul pe infrastructura ta proprie — datele rămân la tine.

**Ce face AI-ul din ea?**
OpenWebUI în sine nu este AI-ul — este doar interfața (fereastra de chat). AI-ul vine dintr-un model separat conectat la ea. În proiectul nostru am deployat doar interfața — modelul AI se conectează separat.

---

## Ce este Azure

Azure este platforma de cloud a Microsoft. În loc să cumperi un server fizic, "închiriezi" resurse la Microsoft și plătești doar cât folosești.

Resursele pe care le-am folosit:
- **Container Apps** — rulează aplicația noastră
- **Storage Account** — păstrează datele aplicației
- **Key Vault** — păstrează secretele (parole, chei)
- **Managed Identity** — permite aplicației să acceseze alte servicii fără parole

---

## Ce este Terraform

Terraform este un instrument care îți permite să descrii infrastructura ca **cod**.

Fără Terraform: intri în Azure Portal, dai click prin meniuri, creezi resurse manual.
Cu Terraform: scrii cod care descrie ce vrei, rulezi o comandă, și totul se creează automat.

**De ce e mai bun codul față de click-uri?**
- **Reproductibil** — oricine poate recrea exact aceeași infrastructură
- **Versionat** — vezi în Git cine a schimbat ce și când
- **Consistent** — nu uiți să configurezi ceva
- **Rapid** — creezi sau ștergi tot cu o comandă

---

## Structura proiectului

Codul e organizat pe **module** — fiecare modul se ocupă de o parte a infrastructurii:

```
Bosh/
├── main.tf                    ← Resource Group + apelează modulele
├── variables.tf               ← variabilele root (subscription, location, domain etc.)
├── outputs.tf                 ← ce afișează Terraform după deploy
├── providers.tf               ← ce provideri folosim (azurerm, azapi, random)
├── terraform.tfvars           ← valorile tale concrete (gitignored)
├── terraform.tfvars.example   ← template pentru oricine clonează repo-ul
├── .gitignore
├── README.md
└── modules/
    ├── storage/               ← Storage Account + 2 File Shares
    ├── identity/              ← User-Assigned Managed Identity
    ├── keyvault/              ← Key Vault + RBAC + secret auto-generat
    └── container_app/         ← Container App Environment + Container App
```

**De ce module?**
Fiecare modul e independent și reutilizabil. Dacă mâine vrei să adaugi un al doilea Container App, nu trebuie să duplici codul — creezi o nouă instanță a modulului. E cum se scrie Terraform în producție.

---

## Pe scurt — ce am construit

```
Internet
    │
    ▼
boschaiops.xyz (domeniul tău)
    │
    ▼ HTTPS (certificat SSL gestionat de Azure)
    │
    ▼
Azure Container Apps (rulează OpenWebUI)
    │
    ├── Azure File Share "models" ──► /app/chat_frontend/models
    ├── Azure File Share "data"   ──► /app/backend/data
    │
    └── Azure Key Vault (secretul WEBUI_SECRET_KEY)
         └── accesat prin Managed Identity (fără parole)
```

Utilizatorul accesează `https://boschaiops.xyz`, vede interfața OpenWebUI, iar datele sunt salvate persistent în Azure Storage.

---

## Costul estimat

- ~$72/lună dacă rulează non-stop (1 replică, 1 CPU, 2Gi RAM)
- Free trial Azure: $200 credit = ~2.5 luni de rulare
- După interviu: `terraform destroy` → cost $0
