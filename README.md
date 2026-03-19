# Kubernetes Webstack — Geert Vuurstaek

## Architectuur

```
          ┌───────────────────────────────────┐
          │ gv-webstack.duckdns.org (HTTPS)   │  ← DuckDNS → MetalLB IP
          │ gv.local (HTTP)                   │  ← hosts entry
          └────────────────┬──────────────────┘
                           │
                  ┌────────▼─────────┐
                  │  ingress-nginx   │  LoadBalancer (MetalLB 192.168.56.100-120)
                  │  TLS termination │  ← Let's Encrypt cert via cert-manager
                  └────────┬─────────┘
                    ┌──────┴──────┐
                    │             │
             ┌──────▼──┐   ┌─────▼─────┐
             │frontend │   │  /api/*    │
             │ (Apache)│   │  gv-api    │
             │ 2 repl. │   │  2 repl.   │
             └─────────┘   └─────┬──────┘
                                 │
                          ┌──────▼──────┐
                          │ gv-postgres │
                          │ (PVC 5Gi)   │
                          └─────────────┘
```

**Cluster:** 3 nodes via Vagrant + kubeadm

| Node | IP | Rol |
|------|-----|-----|
| k8s-master  | 192.168.56.10 | Control plane |
| k8s-worker1 | 192.168.56.11 | Worker |
| k8s-worker2 | 192.168.56.12 | Worker |

**Extra features:**
- ✅ Kubeadm multi-node cluster (1 master + 2 workers)
- ✅ ArgoCD GitOps (auto-sync vanuit GitHub repo)
- ✅ API scaling (2 replicas verdeeld over workers via pod anti-affinity)
- ✅ Healthchecks (liveness + readiness probes op `/health`)
- ✅ Prometheus monitoring (scrape gv-api + kube-state-metrics)
- ✅ Grafana dashboards (cluster overview, API metrics, pod spreiding)
- ✅ HTTPS met Let's Encrypt certificaat (cert-manager + DuckDNS DNS-01 challenge)

---

## Stap-voor-stap opzetten

### Vereisten
- VirtualBox 7+
- Vagrant 2.4+
- Docker Desktop (voor image builds)
- Git
- PowerShell (Windows)

### Stap 1 — VMs aanmaken
```powershell
cd vagrant
vagrant up
```
Dit maakt 3 VMs aan, installeert containerd + kubeadm, en initialiseert het cluster.
De master draait `init-master.sh` (kubeadm init + Flannel CNI met `--iface=enp0s8`), de workers draaien `join-workers.sh`.

> ⏱️ Duurt ca. 10-15 minuten bij eerste keer.

### Stap 2 — Container images bouwen en distribueren
```powershell
./build_and_distribute_images.ps1
```
Bouwt `gv-api:1.3` en `gv-frontend:1.0` lokaal met Docker en uploadt ze naar alle nodes via `vagrant upload` + `ctr import`.

### Stap 3 — Kubernetes manifests deployen
```powershell
./deploy_manifests.ps1
```
Dit script:
- Maakt namespaces aan (`gv-webstack`, `gv-monitoring`)
- Installeert ingress-nginx, MetalLB, ArgoCD
- Deployt de webstack (frontend, API, PostgreSQL)
- Deployt Prometheus + kube-state-metrics
- Configureert ArgoCD Applications voor auto-sync

### Stap 4 — Hosts entry toevoegen
Zoek het EXTERNAL-IP van de ingress:
```powershell
vagrant ssh k8s-master -- kubectl get svc -n ingress-nginx ingress-nginx-controller
```
Voeg toe aan `C:\Windows\System32\drivers\etc\hosts` (als admin):
```
192.168.56.100  gv.local
192.168.56.100  gv-webstack.duckdns.org
```

### Stap 5 — Controleren
- Open **https://gv-webstack.duckdns.org** — HTTPS met geldig Let's Encrypt certificaat
- Open **http://gv.local** — HTTP fallback

Je ziet de naam uit de database en de container hostname.

---

## Toegang tot services

### Webapplicatie
| URL | Omschrijving |
|-----|-------------|
| https://gv-webstack.duckdns.org | Frontend via HTTPS (Let's Encrypt) |
| https://gv-webstack.duckdns.org/api/user | API: naam uit PostgreSQL (HTTPS) |
| https://gv-webstack.duckdns.org/api/container | API: container hostname (HTTPS) |
| https://gv-webstack.duckdns.org/api/health | API: health status (HTTPS) |
| http://gv.local | Frontend (HTTP fallback) |
| http://gv.local/api/user | API: naam uit PostgreSQL |
| http://gv.local/api/container | API: container hostname |
| http://gv.local/api/health | API: health status |

### Prometheus (monitoring)
Port-forward opzetten vanuit de `vagrant/` map:
```powershell
# Terminal 1: port-forward in de VM (draait als background process)
vagrant ssh k8s-master -- "nohup kubectl port-forward --address 0.0.0.0 -n gv-monitoring svc/gv-prometheus 19090:9090 > /tmp/pf-prom.log 2>&1 & sleep 2 ; ss -lntp | grep 19090"

# Terminal 2: SSH tunnel naar localhost (vanuit vagrant/ map)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -i "C:/dev/examen-project/vagrant/.vagrant/machines/k8s-master/virtualbox/private_key" -p 2222 -N -L 19090:localhost:19090 vagrant@127.0.0.1
```
Open: **http://localhost:19090/targets**

Verwachte targets (alle UP):
- `gv-api` → `gv-api.gv-webstack.svc.cluster.local:8000`
- `kube-state-metrics` → `kube-state-metrics.gv-monitoring.svc.cluster.local:8080`
- `prometheus` → `localhost:9090`

### Grafana (dashboards)
Port-forward opzetten vanuit de `vagrant/` map:
```powershell
# Terminal 1: port-forward in de VM (draait als background process)
vagrant ssh k8s-master -- "nohup kubectl port-forward --address 0.0.0.0 -n gv-monitoring svc/grafana 13000:3000 > /tmp/pf-grafana.log 2>&1 & sleep 2 ; ss -lntp | grep 13000"

# Terminal 2: SSH tunnel naar localhost (vanuit vagrant/ map)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -i "C:/dev/examen-project/vagrant/.vagrant/machines/k8s-master/virtualbox/private_key" -p 2222 -N -L 13000:localhost:13000 vagrant@127.0.0.1
```
Open: **http://localhost:13000**

**Credentials:** admin / admin (skip password change)

Het "GV Kubernetes Cluster" dashboard opent automatisch met:
- CPU & Memory usage gauges
- Nodes Ready / Pods Running / Pods Not Ready
- API Requests & Responses per endpoint
- Pods per Node & Namespace
- DB Query Duration
- Pod overview tabel (gv-webstack)

### ArgoCD (GitOps)
```powershell
# Terminal 1: port-forward in de VM (draait als background process)
vagrant ssh k8s-master -- "nohup kubectl port-forward --address 0.0.0.0 -n argocd svc/argocd-server 18081:443 > /tmp/pf-argocd.log 2>&1 & sleep 2 ; ss -lntp | grep 18081"

# Terminal 2: SSH tunnel naar localhost (vanuit vagrant/ map)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -i "C:/dev/examen-project/vagrant/.vagrant/machines/k8s-master/virtualbox/private_key" -p 2222 -N -L 18081:localhost:18081 vagrant@127.0.0.1
```
Open: **https://localhost:18081**

**Credentials:**
```powershell
# Username: admin
# Password ophalen:
vagrant ssh k8s-master -- "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

---

## Demo — Naam aanpassen in de database

> Dit toont aan dat de API **live** data uit PostgreSQL leest — geen restart nodig.

### 1. Huidige naam bekijken
Open http://gv.local of https://gv-webstack.duckdns.org — de naam "Geert Vuurstaek" wordt getoond.

Controleer via de API:
```powershell
curl http://gv.local/api/user
# → {"user":"Geert Vuurstaek"}
```

### 2. Naam wijzigen in PostgreSQL
```powershell
# Helper-functie (kopieer deze one-liner 1x in je terminal):
function Run-SQL($query) { $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($query)) ; vagrant ssh k8s-master -- "echo $b64 | base64 -d | kubectl exec -i -n gv-webstack deploy/gv-postgres -- psql -U gv_user -d gv_db" }

# Naam wijzigen:
Run-SQL "UPDATE users SET name='Demo Gebruiker' WHERE id=1;"
# → UPDATE 1
```

> **Waarom base64?** Quotes overleven niet door de lagen PowerShell → Vagrant → Bash → psql.
> De helper-functie `Run-SQL` encodeert de query als base64 en decodeert in Linux.

### 3. Resultaat controleren
Refresh de browser — de nieuwe naam verschijnt **direct** (live database read, geen pod restart).

```powershell
curl http://gv.local/api/user
# → {"user":"Demo Gebruiker"}
```

### 4. Naam terugzetten
```powershell
Run-SQL "UPDATE users SET name='Geert Vuurstaek' WHERE id=1;"
```

### 5. Bonus: data bekijken
```powershell
Run-SQL "SELECT * FROM users;"
#  id |      name
# ----+------------------
#   1 | Geert Vuurstaek
```

---

## Demo — Scaling & pod spreiding aantonen

```powershell
# Pods verdeeld over worker1 en worker2:
vagrant ssh k8s-master -- kubectl get pods -n gv-webstack -o wide

# API heeft 2 replicas, frontend heeft 2 replicas
# Pod anti-affinity zorgt dat ze op verschillende nodes draaien
```

Refresh http://gv.local meerdere keren — de **container hostname** wisselt tussen de 2 API pods.

---

## Demo — Monitoring (Grafana + Prometheus)

### Grafana dashboard
Open **http://localhost:13000** → het "GV Kubernetes Cluster" dashboard toont:
- **Gauges:** Cluster CPU & Memory usage percentage
- **Stats:** Nodes Ready, Pods Running, Pods Not Ready
- **Grafieken:** API requests/responses per endpoint, pods per node/namespace
- **Tabel:** Overzicht van alle gv-webstack pods met node en IP

Genereer wat traffic om data te zien:
```powershell
1..20 | ForEach-Object { Invoke-RestMethod http://gv.local/api/user | Out-Null }
```

### Prometheus (raw queries)
Open http://localhost:19090 en voer een query uit:
- `api_requests_total` — totaal aantal requests per endpoint
- `api_responses_total` — responses per status code
- `kube_pod_info` — alle pods in het cluster

---

## Demo — HTTPS certificaat

Het certificaat is automatisch aangevraagd via cert-manager + DuckDNS DNS-01 challenge:
```powershell
# Certificaat status bekijken
vagrant ssh k8s-master -- kubectl get certificate -n gv-webstack
# → gv-webstack-tls   True    gv-webstack-tls   ...

# Certificaat details
vagrant ssh k8s-master -- "kubectl get secret gv-webstack-tls -n gv-webstack -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -issuer -dates"
# → subject=CN=gv-webstack.duckdns.org
# → issuer=C=US, O=Let's Encrypt, CN=R13
```

Test HTTPS:
```powershell
curl -sk https://gv-webstack.duckdns.org/api/user
# → {"name":"Geert Vuurstaek"}
```

---

## Demo — ArgoCD auto-sync

1. Open https://localhost:18081 → beide apps "Synced / Healthy"
2. Wijzig iets in `k8s/webstack/` (bv. een label) en push naar GitHub
3. ArgoCD detecteert de wijziging automatisch en past het toe

---

## Handige kubectl commando's

```bash
# Cluster status
kubectl get nodes
kubectl get pods -A -o wide

# Webstack
kubectl get pods -n gv-webstack -o wide
kubectl get svc -n gv-webstack
kubectl logs -n gv-webstack deploy/gv-api

# Monitoring
kubectl get pods -n gv-monitoring -o wide
kubectl logs -n gv-monitoring deploy/gv-prometheus

# ArgoCD
kubectl get app -n argocd

# Database shell
kubectl exec -it -n gv-webstack deploy/gv-postgres -- psql -U gv_user -d gv_db
```

---

## VMs pauzeren / hervatten

Wil je de VMs tijdelijk uitzetten zonder alles te verliezen? Gebruik `suspend` en `resume`:

```powershell
cd vagrant

# Alles pauzeren (slaat RAM-staat op naar disk)
vagrant suspend

# Weer hervatten
vagrant resume
```

Je kunt ook de VMs uitzetten (graceful shutdown) en later weer opstarten:

```powershell
# Uitzetten (shutdown)
vagrant halt

# Weer opstarten
vagrant up
```

> **Tip:** Na `vagrant resume` of `vagrant up` kan het ~1 minuut duren voordat alle Kubernetes pods weer `Ready` zijn. Check met:
> ```powershell
> vagrant ssh k8s-master -- kubectl get nodes
> vagrant ssh k8s-master -- kubectl get pods -A
> ```

> **Let op:** Na `suspend`/`resume` vallen zowel de port-forwards in de VM als de SSH tunnels op Windows weg. Herstart ze als volgt:
>
> **Stap 1 — Port-forwards herstarten in de VM:**
> ```powershell
> cd vagrant
> vagrant ssh k8s-master -- "nohup kubectl port-forward --address 0.0.0.0 -n argocd svc/argocd-server 18081:443 > /tmp/pf-argocd.log 2>&1 & nohup kubectl port-forward --address 0.0.0.0 -n gv-monitoring svc/grafana 13000:3000 > /tmp/pf-grafana.log 2>&1 & nohup kubectl port-forward --address 0.0.0.0 -n gv-monitoring svc/gv-prometheus 19090:9090 > /tmp/pf-prom.log 2>&1 & sleep 3 ; ss -lntp | grep -E '18081|13000|19090'"
> ```
>
> **Stap 2 — SSH tunnel starten op Windows (in een apart terminal):**
> ```powershell
> cd vagrant
> ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -i "C:/dev/examen-project/vagrant/.vagrant/machines/k8s-master/virtualbox/private_key" -p 2222 -N -L 18081:localhost:18081 -L 13000:localhost:13000 -L 19090:localhost:19090 vagrant@127.0.0.1
> ```
>
> Daarna beschikbaar:
> - **Grafana**: http://localhost:13000 (admin / admin)
> - **ArgoCD**: https://localhost:18081
> - **Prometheus**: http://localhost:19090
>
> De webstack (`gv.local` / `gv-webstack.duckdns.org`) werkt direct na resume via MetalLB + ingress — daar zijn geen port-forwards voor nodig.

| Commando | Effect | Snelheid hervatten |
|----------|--------|--------------------|
| `vagrant suspend` | RAM opslaan naar disk | Snel (~10s) |
| `vagrant halt` | Graceful shutdown | Langzamer (~1-2 min) |
| `vagrant destroy -f` | VMs volledig verwijderen | Moet opnieuw opzetten |

---

## Troubleshooting

### Troubleshooting — Grafana lokaal niet bereikbaar (13000):

> 1. Controleer of er maar één SSH tunnel actief is naar 13000:
>    ```powershell
>    netstat -ano | findstr :13000
>    ```
>    Stop alle ssh.exe processen die poort 13000 gebruiken:
>    ```powershell
>    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match '13000:localhost:13000' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
>    ```
>    Start daarna de SSH tunnel opnieuw:
>    ```powershell
>    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa -i "C:/dev/examen-project/vagrant/.vagrant/machines/k8s-master/virtualbox/private_key" -p 2222 -N -L 13000:localhost:13000 vagrant@127.0.0.1
>    ```
>
> 2. Controleer of de port-forward op de VM draait:
>    ```powershell
>    vagrant ssh k8s-master -- "ss -lntp | grep 13000"
>    ```
>    Je moet een LISTEN zien op 0.0.0.0:13000.
>
> 3. Controleer of de Grafana pod en service daadwerkelijk draaien:
>    ```powershell
>    vagrant ssh k8s-master -- kubectl get pods -n gv-monitoring
>    vagrant ssh k8s-master -- kubectl get svc -n gv-monitoring
>    ```
>    Pod moet Running zijn, service moet op poort 3000 staan.
>
> 4. Test met curl:
>    ```powershell
>    curl http://localhost:13000
>    ```
>
> 5. Controleer firewall/antivirus (poort 13000 mag niet geblokkeerd zijn).
>
> Zo werkt http://localhost:13000 weer voor Grafana.

> **Tip:** Zet port-forwards altijd één voor één op en test direct met `curl` of in de browser. Zo voorkom je poortconflicten en zie je meteen welke service werkt. Vooral na een VM-restart of bij problemen is dit de meest stabiele aanpak.

### Worker node NotReady
Als een worker `NotReady` wordt (bv. na resume of netwerkproblemen):
```powershell
# Check welke node NotReady is
vagrant ssh k8s-master -- kubectl get nodes

# Herstart containerd + kubelet op de betreffende worker
vagrant ssh k8s-worker2 -- "sudo systemctl restart containerd ; sudo systemctl restart kubelet"

# Wacht ~15 sec en check opnieuw
vagrant ssh k8s-master -- kubectl get nodes
```

### Kernel modules na reboot
Als Flannel crasht na reboot (`br_netfilter` module mist):
```powershell
vagrant ssh <worker> -- "sudo modprobe br_netfilter overlay ; sudo systemctl restart kubelet"
```
Dit is normaal al persistent via `/etc/modules-load.d/k8s.conf` (ingesteld door `provision.sh`).

### Troubleshooting — ArgoCD lokaal niet bereikbaar (18081):

> 1. Controleer of er maar één SSH tunnel actief is naar 18081:
>    ```powershell
>    netstat -ano | findstr :18081
>    ```
>    Stop alle ssh.exe processen die poort 18081 gebruiken:
>    ```powershell
>    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match '18081:localhost:18081' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
>    ```
>    Start daarna de SSH tunnel opnieuw.
> 
> 2. Controleer of de port-forward op de VM draait:
>    ```powershell
>    vagrant ssh k8s-master -- "ss -lntp | grep 18081"
>    ```
>    Je moet een LISTEN zien op 0.0.0.0:18081.
> 
> 3. Controleer of de ArgoCD pod en service daadwerkelijk draaien:
>    ```powershell
>    vagrant ssh k8s-master -- kubectl get pods -n argocd
>    vagrant ssh k8s-master -- kubectl get svc -n argocd
>    ```
>    Pod moet Running zijn, service moet op poort 443 staan.
> 
> 4. Test met curl:
>    ```powershell
>    curl.exe -k https://localhost:18081
>    ```
>    Accepteer SSL warnings in de browser.
> 
> 5. Start de SSH tunnel in een nieuwe terminal als je net processen hebt gestopt.
> 
> 6. Controleer firewall/antivirus (poort 18081 mag niet geblokkeerd zijn).
> 
> Zo werkt https://localhost:18081 weer voor ArgoCD.

> **Let op:** Port-forwards kunnen elkaar beïnvloeden. Start bij troubleshooting alleen de port-forward voor de app die je wilt testen (bv. ArgoCD), en voeg de andere pas toe als alles werkt. Soms werkt het stabieler om port-forwards één voor één te starten en te testen.
> 
> Bij SSL/TLS errors in curl of browser:
> - Accepteer SSL warnings in de browser.
> - Gebruik incognito/private mode om caching te omzeilen.
> - Test met curl.exe -k om te zien of de endpoint bereikbaar is.
> - Herstart port-forward en SSH tunnel als je een handshake error krijgt.
> 
> Zo voorkom je conflicten en kun je snel troubleshooten per app.

---

## Reset / opruimen
```powershell
cd vagrant
vagrant destroy -f
```
