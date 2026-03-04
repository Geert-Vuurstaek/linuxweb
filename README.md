# Kubernetes Webstack — Geert Vuurstaek

## Architectuur

```
                  ┌──────────────────┐
                  │   gv.local       │  ← hosts entry naar MetalLB EXTERNAL-IP
                  └────────┬─────────┘
                           │
                  ┌────────▼─────────┐
                  │  ingress-nginx   │  LoadBalancer (MetalLB 192.168.56.100-120)
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
Voeg toe aan `C:\Windows\System32\drivers\etc\hosts`:
```
192.168.56.1xx  gv.local
```
(Vervang `1xx` door het daadwerkelijke MetalLB IP)

### Stap 5 — Controleren
Open **http://gv.local** in je browser. Je ziet de naam uit de database en de container hostname.

---

## Toegang tot services

### Webapplicatie
| URL | Omschrijving |
|-----|-------------|
| http://gv.local | Frontend (toont naam + container) |
| http://gv.local/api/user | API: naam uit PostgreSQL |
| http://gv.local/api/container | API: container hostname |
| http://gv.local/api/health | API: health status |

### Prometheus (monitoring)
Port-forward opzetten vanuit de `vagrant/` map:
```powershell
# Terminal 1: port-forward in de VM
vagrant ssh k8s-master -- kubectl port-forward --address 0.0.0.0 -n gv-monitoring svc/gv-prometheus 19090:9090

# Terminal 2: SSH tunnel naar localhost (vanuit vagrant/ map)
ssh -o StrictHostKeyChecking=no -i ".vagrant/machines/k8s-master/virtualbox/private_key" -p 2222 -N -L 19090:localhost:19090 vagrant@127.0.0.1
```
Open: **http://localhost:19090/targets**

Verwachte targets (alle UP):
- `gv-api` → `gv-api.gv-webstack.svc.cluster.local:8000`
- `kube-state-metrics` → `kube-state-metrics.gv-monitoring.svc.cluster.local:8080`
- `prometheus` → `localhost:9090`

### ArgoCD (GitOps)
```powershell
# Terminal 1: port-forward in de VM
vagrant ssh k8s-master -- kubectl port-forward --address 0.0.0.0 -n argocd svc/argocd-server 18081:443

# Terminal 2: SSH tunnel naar localhost (vanuit vagrant/ map)
ssh -o StrictHostKeyChecking=no -i ".vagrant/machines/k8s-master/virtualbox/private_key" -p 2222 -N -L 18081:localhost:18081 vagrant@127.0.0.1
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

### 1. Huidige naam bekijken
Open http://gv.local — de naam "Geert Vuurstaek" wordt getoond.

Of via de API:
```powershell
curl http://gv.local/api/user
# → {"user":"Geert Vuurstaek"}
```

### 2. Naam wijzigen in PostgreSQL
```powershell
vagrant ssh k8s-master -- kubectl exec -n gv-webstack deploy/gv-postgres -- psql -U gv_user -d gv_db -c "UPDATE users SET name='Demo Gebruiker' WHERE id=1;"
```

### 3. Resultaat controleren
Refresh http://gv.local — de nieuwe naam verschijnt direct (geen restart nodig, de API leest live uit de database).

```powershell
curl http://gv.local/api/user
# → {"user":"Demo Gebruiker"}
```

### 4. Naam terugzetten
```powershell
vagrant ssh k8s-master -- kubectl exec -n gv-webstack deploy/gv-postgres -- psql -U gv_user -d gv_db -c "UPDATE users SET name='Geert Vuurstaek' WHERE id=1;"
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

## Demo — Prometheus metrics

Open http://localhost:19090 en voer een query uit:
- `api_requests_total` — toont totaal aantal requests per endpoint
- `api_responses_total` — toont responses per status code
- `kube_pod_info` — toont alle pods in het cluster

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

## Reset / opruimen
```powershell
cd vagrant
vagrant destroy -f
```
