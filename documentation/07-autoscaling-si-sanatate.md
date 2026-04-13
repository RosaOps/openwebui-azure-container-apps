# Autoscaling și Health Monitoring

---

## Ce este Autoscaling și de ce îl folosim

**Problema fără autoscaling:**
Dacă ai un server cu capacitate fixă:
- Trafic normal → serverul e la 20% capacitate → plătești pentru 80% nefolosit
- Spike de trafic (mulți useri simultan) → serverul e la 100% → aplicația devine lentă sau cade

**Soluția cu autoscaling:**
- Trafic normal → 1 replică → plătești puțin
- Trafic mare → Azure pornește automat 2, 3, 5, 10 replici
- Traficul scade → Azure oprește replicile extra

---

## Configurarea noastră

```hcl
template {
  min_replicas = 1
  max_replicas = 10

  custom_scale_rule {
    name             = "cpu-scale-rule"
    custom_rule_type = "cpu"
    metadata = {
      type  = "Utilization"
      value = "75"
    }
  }
}
```

### Min replicas = 1

**De ce nu 0?**
Dacă min = 0, când nu e nimeni pe site, Azure oprește complet containerul.
Avantaj: nu plătești nimic când nu e trafic.
Dezavantaj: primul utilizator care vine trebuie să aștepte 20-60 secunde ca containerul să pornească (**cold start**).

Am ales min = 1 pentru că:
- Aplicația e mereu disponibilă instant
- OpenWebUI are un cold start relativ lung (încărcare modele, inițializare bază de date)
- Assessment-ul cere demo funcțional — nu vrem să așteptăm la prezentare

### Max replicas = 10

Limita superioară. Azure nu va porni mai mult de 10 replici simultan.

**De ce nu infinit?**
- Protecție la costuri — dacă e un atac DDoS, nu vrei 1000 de replici pornite
- OpenWebUI e o singură instanță — datele sunt în Storage, dar aplicația în sine nu e proiectată pentru scaling orizontal masiv
- 10 replici × 1 CPU × 2GB RAM = suficient pentru demonstrație

### Scale rule — CPU la 75%

```hcl
custom_scale_rule {
  custom_rule_type = "cpu"
  metadata = {
    type  = "Utilization"
    value = "75"
  }
}
```

**`type = "Utilization"`** = procentaj din CPU-ul alocat
**`value = "75"`** = 75% din 1 CPU = 0.75 CPU

**Cum funcționează:**
- CPU mediu < 75% pe toate replicile → nu face nimic
- CPU mediu > 75% → pornește o replică nouă
- CPU mediu scade din nou < 75% → după un timp, oprește replica extra

**De ce 75% și nu 50% sau 90%?**
- 50% ar scala prea devreme — risipă de resurse
- 90% ar scala prea târziu — utilizatorii simt degradarea înainte să pornească noua replică
- 75% e un echilibru bun — scala înainte să se simtă problema

**KEDA — ce e în spate?**
Azure Container Apps folosește KEDA (Kubernetes Event-Driven Autoscaling) sub capotă pentru scaling rules. KEDA este un proiect open-source care gestionează scaling pentru containere bazat pe diverse metrici.

---

## Health Probes — monitorizarea stării aplicației

### Liveness Probe

```hcl
liveness_probe {
  transport = "HTTP"
  path      = "/health"
  port      = 8080
  # Defaults: interval=10s, timeout=1s, failure_threshold=3
}
```

**Ce face Azure:**
La fiecare 10 secunde, Azure trimite un request HTTP GET la:
`http://container:8080/health`

**Dacă răspunsul e 200 OK** → containerul e sănătos, totul bine.

**Dacă răspunsul nu vine sau e 5xx** → Azure numără eșecul.
- 1 eșec → avertisment intern
- 2 eșecuri → avertisment
- 3 eșecuri la rând → **Azure restartează containerul**

**De ce e nevoie de liveness probe?**
Fără el, Azure nu știe că aplicația ta a crăpat. Containerul poate fi "pornit" tehnic (procesul rulează) dar aplicația în interior e blocată (deadlock, memory leak, infinit loop). Liveness probe detectează asta și forțează restart.

**Ce returnează `/health` în OpenWebUI?**
```json
{"status": true}
```
Un simplu JSON care confirmă că aplicația e responsivă.

---

### Readiness Probe

```hcl
readiness_probe {
  transport = "HTTP"
  path      = "/health"
  port      = 8080
  # Defaults: interval=10s, timeout=1s, success_threshold=3, failure_threshold=3
}
```

**Ce face Azure:**
Similar cu liveness, dar cu un scop diferit: verifică dacă containerul e **gata să primească trafic**.

**Scenariul tipic:**
```
t=0s   → Azure pornește o replică nouă (din cauza scalingului)
t=1s   → Containerul pornește, dar OpenWebUI încă se inițializează
         (încarcă baza de date, citește configurația, etc.)
t=5s   → Readiness probe: /health → 503 Service Unavailable
         Azure: "Nu trimite trafic la această replică încă"
t=15s  → OpenWebUI e complet pornit
t=15s  → Readiness probe: /health → 200 OK (3 succese consecutive)
         Azure: "Acum poate primi trafic"
t=16s  → Traficul real ajunge la noua replică
```

**Diferența cheie față de liveness:**
| | Liveness | Readiness |
|--|---------|----------|
| Scop | E aplicația în viață? | E gata să servească trafic? |
| Acțiune la eșec | Restartează containerul | Nu trimite trafic la el |
| Când contează | Continuu, în timpul vieții | La startup și periodic |

---

## Cum testezi autoscaling-ul (pentru demo)

Assessment-ul cere: *"Trigger CPU-based scaling and verify replica count changes"*

**Metoda simplă — stress test:**

```bash
# Instalezi un tool de load testing (ex: hey sau wrk)
# Sau folosești Azure Load Testing service

# Exemplu cu hey (simplu HTTP load tester):
hey -n 10000 -c 100 https://boschaiops.xyz

# -n 10000 = 10000 requests total
# -c 100   = 100 requests simultan
```

**Cum verifici că s-a scalat:**
```bash
az containerapp replica list \
  --name ca-openwebui-xxxxxx \
  --resource-group rg-openwebui-xxxxxx \
  --query "[].name"
```

Sau din Azure Portal: Container App → Scale & replicas → vezi câte replici rulează.

---

## Rezumat vizual

```
Stare normală (CPU < 75%):
[Replică 1] ← tot traficul

Spike de trafic (CPU > 75%):
[Replică 1] ← trafic
[Replică 2] ← trafic  (pornită de Azure automat)
[Replică 3] ← trafic  (dacă CPU tot > 75%)
...
[Replică 10] ← trafic (maximum)

După spike (CPU scade):
[Replică 1] ← tot traficul
[Replică 2..10] oprite de Azure automat
```

Totul se întâmplă automat, fără intervenție manuală.
