# linuxweb

## Snelstart (kubeadm + Vagrant)
1) Ga naar de Vagrant map en start de VMs
```
cd vagrant
vagrant up
```
2) Bouw en verspreid de images naar alle nodes (vereist Docker op de host)
```
./build_and_distribute_images.ps1
```
Dit script gebruikt `vagrant upload` en vereist geen `vagrant-scp` plugin.
Als `vagrant` niet gevonden wordt in je shell, forceer het pad éénmalig:
```
$env:VAGRANT_CMD = "C:/Program Files/Vagrant/bin/vagrant.exe"
./build_and_distribute_images.ps1
```
3) Deploy alle manifests (maakt namespaces aan, installeert ingress-nginx, MetalLB en ArgoCD, daarna de app)
```
./deploy_manifests.ps1
```
Dit script uploadt automatisch de lokale `k8s/` map naar de master en past die daar toe.
Bij trage MetalLB webhook start voert het script automatisch retries uit en zet tijdelijk webhook `failurePolicy=Ignore` om door te kunnen gaan.
4) Hosts entry toevoegen voor de ingress (na deploy: pak het EXTERNAL-IP van ingress-nginx)
```
kubectl get svc -n ingress-nginx ingress-nginx-controller
<EXTERNAL-IP> gv.local
```
5) Applicatie openen: http://gv.local

## Wat staat er na deploy?
- Ingress controller: nginx (via upstream manifest)
- Load balancer: MetalLB met pool 192.168.56.100-192.168.56.120
- GitOps: ArgoCD geïnstalleerd; Application wijst naar deze repo (k8s/webstack)
- Monitoring: Prometheus (namespace gv-monitoring) scrape’t gv-api
- Monitoring: Prometheus (namespace gv-monitoring) scrape’t gv-api + kube-state-metrics (cluster resource/state metrics)
- Webstack (namespace gv-webstack):
  - gv-frontend (Apache met reverse proxy naar `/api`)
  - gv-api (FastAPI, liveness/readiness probes)
  - gv-postgres met init SQL en PVC (5Gi, storageClass `standard`)

## Toegang en checks
- Web: http://gv.local
- API: http://gv.local/api/user en http://gv.local/api/container
- Prometheus targets: open `http://192.168.56.12:31025/targets` (of `kubectl get svc -n gv-monitoring gv-prometheus` en gebruik de NodePort)
  - Verwachte extra targets: `192.168.56.12:30080` (gv-api) en `192.168.56.12:30081` (kube-state-metrics)
- ArgoCD UI: `kubectl port-forward -n argocd svc/argocd-server 8081:443` → https://localhost:8081 (user `admin`, wachtwoord: `kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode`)

## Reset / opruimen
- VMs verwijderen (vanuit `vagrant/`): `vagrant destroy -f`
- Cluster reset op nodes (indien nodig):
  - `sudo kubeadm reset -f`
  - `sudo rm -rf /etc/cni/net.d`
  - `sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X`
  - Control plane: `rm -rf $HOME/.kube`

## Demo snippets
- `kubectl get nodes`
- `kubectl get pods -n gv-webstack -o wide`
- Data aanpassen: `kubectl exec -n gv-webstack deploy/gv-postgres -- psql -U gv_user -d gv_db -c "UPDATE users SET name='Geert Vuurstaek' WHERE id=1;"`
- Metrics: query `api_requests_total` in Prometheus

## Opmerking over `/api/user`
- De API leest de naam uit PostgreSQL (`users` tabel, `id=1`) en retourneert die via `/api/user`.
- Init van schema/seed gebeurt via `db/init.sql` tijdens PostgreSQL initialisatie.
- API image tag is `gv-api:1.3`; herbouw en herdeploy na codewijzigingen.
- PostgreSQL gebruikt nu PVC/PV `gv-postgres-pvc-v2` / `gv-postgres-pv-v2` om oude volume-state te vermijden.