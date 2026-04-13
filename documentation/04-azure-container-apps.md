# Azure Container Apps — Ce sunt și cum funcționează

---

## Primul pas: ce este un Container

Înainte de Container Apps, trebuie să înțelegi ce e un **container**.

Imaginează-ți că vrei să dai cuiva aplicația ta să o ruleze. Problema clasică:
> "La mine merge, la tine nu merge" — pentru că el are alt sistem de operare, altă versiune de Python, altă configurație.

Un **container** rezolvă asta. Este un pachet care conține:
- Aplicația ta (codul)
- Runtime-ul (Python, Node, Java etc.)
- Toate dependențele (librăriile)
- Configurația

Oriunde rulezi containerul — pe laptopul tău, pe un server, în cloud — se comportă identic.

**Docker** este cel mai popular tool pentru containere. Imaginea Docker pentru OpenWebUI este:
```
ghcr.io/open-webui/open-webui:main
```
`ghcr.io` = GitHub Container Registry (unde e stocată imaginea)
`open-webui/open-webui` = organizație/nume imagine
`:main` = tag-ul (versiunea) — "main" înseamnă ultima versiune din branch-ul principal

---

## De ce Azure Container Apps și nu altceva?

Azure are mai multe servicii pentru a rula containere:

| Serviciu | Ce e | Complexitate |
|----------|------|-------------|
| **Azure Container Instances** | Cel mai simplu — rulezi un container rapid | Minimă — dar fără scaling, fără ingress avansat |
| **Azure Container Apps** | PaaS gestionat — tu te ocupi de app, Azure de infrastructură | Medie — exact ce ne trebuie |
| **Azure Kubernetes Service (AKS)** | Kubernetes complet — control total | Ridicată — prea mult pentru o singură aplicație |
| **Azure App Service** | PaaS pentru web apps | Medie — mai vechi, mai puțin flexibil pentru containere |

**Am ales Container Apps pentru că:**
- Suportă **scaling automat** (inclusiv la 0 replici dacă nu e trafic)
- Are **ingress integrat** cu HTTPS și custom domain
- **Nu trebuie să gestionezi Kubernetes** — Azure face asta
- **Plătești doar cât rulează** containerul (consumption model)
- Suportă **volume mounts** pentru date persistente

---

## Componentele unui Container App deployment

### Container App Environment
```
Container App Environment
└── Container App 1 (OpenWebUI)
└── Container App 2 (alt serviciu, dacă ar fi)
└── Container App 3 (alt serviciu, dacă ar fi)
```

Environment-ul oferă:
- Rețea internă partajată între containere
- Log-uri centralizate
- DNS intern
- Stocare partajată (File Shares montate la nivel de environment)

### Revision Model
Am setat `revision_mode = "Single"`.

Container Apps suportă mai multe **revizii** (versiuni) ale aplicației care rulează simultan — util pentru deployments fără downtime. În modul "Single", există o singură revizie activă la un moment dat. E mai simplu și suficient pentru proiectul nostru.

### Replici
O **replică** = o instanță a containerului care rulează.

- `min_replicas = 1` — mereu cel puțin un container pornit
- `max_replicas = 10` — poate scala până la 10 containere simultane

Când vine mult trafic sau CPU-ul crește, Azure pornește replici noi automat.

---

## Cum ajunge requestul la container

```
1. Browser: https://boschaiops.xyz

2. DNS: boschaiops.xyz → CNAME → ca-openwebui-xxx.northeurope.azurecontainerapps.io

3. Azure Load Balancer primește request-ul

4. Ingress Controller:
   - Verifică certificatul SSL
   - Decriptează HTTPS → HTTP intern
   - Trimite request-ul la o replică disponibilă

5. Containerul OpenWebUI procesează request-ul și răspunde

6. Răspunsul merge înapoi prin același drum
```

### Ce este Ingress?
Ingress = "intrarea" în container din exterior.

Configurarea noastră:
```hcl
ingress {
  external_enabled = true   # accesibil din internet (nu doar intern)
  target_port      = 8080   # portul pe care ascultă OpenWebUI
  transport        = "auto" # detectează automat HTTP/1.1 sau HTTP/2
}
```

Fără `external_enabled = true`, containerul ar fi accesibil doar din alte servicii Azure din același environment — nu din internet.

---

## Health Probes — cum știe Azure că aplicația funcționează

Am configurat două tipuri de probe:

### Liveness Probe
```hcl
liveness_probe {
  transport = "HTTP"
  path      = "/health"
  port      = 8080
}
```

**Ce face:** Azure trimite periodic un request HTTP la `/health`. Dacă OpenWebUI răspunde OK, containerul e considerat "viu". Dacă nu răspunde de mai multe ori la rând, Azure **restartează** containerul automat.

**Analogie:** E ca un om care bate la ușă din oră în oră. Dacă nu răspunzi de 3 ori la rând, cineva vine să verifice ce s-a întâmplat.

### Readiness Probe
```hcl
readiness_probe {
  transport = "HTTP"
  path      = "/health"
  port      = 8080
}
```

**Ce face:** Verifică dacă containerul e **gata să primească trafic**. La startup, OpenWebUI are nevoie de câteva secunde să se inițializeze. Cât timp readiness probe-ul nu trece, Azure nu trimite trafic real la acea replică.

**Diferența față de liveness:**
- Liveness = "E containerul în viață?" → dacă nu, restartează-l
- Readiness = "E containerul pregătit pentru trafic?" → dacă nu, nu trimite trafic la el

---

## De ce Container Apps față de un VPS simplu?

Ai fi putut lua un server virtual (VM) pe Azure și instala aplicația direct. De ce nu am făcut asta?

| | VM clasic | Container Apps |
|--|-----------|----------------|
| Scaling | Manual — tu adaugi servere | Automat — Azure adaugă replici |
| Updates OS | Tu | Azure |
| Load balancing | Tu configurezi | Inclus automat |
| SSL/Certificates | Tu gestionezi | Azure gestionează |
| Plată | Plătești chiar dacă nu e trafic | Plătești doar ce folosești |
| Complexity | Ridicată | Scăzută |

**PaaS vs IaaS:**
- IaaS (Infrastructure as a Service) = VM — tu gestionezi tot deasupra hardware-ului
- PaaS (Platform as a Service) = Container Apps — tu te ocupi doar de aplicație, platforma gestionează restul
