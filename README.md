# linuxweb

## ArgoCD demo checklist
- Open ArgoCD UI (port-forward) and log in
	- kubectl port-forward -n argocd svc/gv-argocd-server 8081:443
	- Open https://localhost:8081
	- kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
	- Login user: admin
- Verify app `gv-webstack` is Synced and Healthy
	- kubectl get applications -n argocd
- Show app tree (frontend, api, db, ingress) in UI
- Make a small manifest change in repo, push, and show auto-sync
	- git add k8s/
	- git commit -m "Demo change"
	- git push

## Cleanup (na demo)
- Verwijder ArgoCD app:
	- kubectl delete application -n argocd gv-webstack
- Verwijder ArgoCD:
	- helm uninstall gv-argocd -n argocd
	- kubectl delete namespace argocd

## Reset cluster (kind)
- Verwijder de kind cluster:
	- kind delete cluster --name demo
- Maak opnieuw:
	- kind create cluster --name demo --config k8s/kind/kind-config.yaml

## Reset cluster (kubeadm)
- Op alle nodes:
	- sudo kubeadm reset -f
	- sudo rm -rf /etc/cni/net.d
	- sudo iptables -F
	- sudo iptables -t nat -F
	- sudo iptables -t mangle -F
	- sudo iptables -X
- Op de control node:
	- rm -rf $HOME/.kube

## Demo script (kort)
- Toon cluster en nodes:
	- kubectl get nodes
- Toon pods in namespace:
	- kubectl get pods -n gv-webstack -o wide
- Open webapp: http://gv.local
- Toon API endpoints:
	- http://gv.local/api/user
	- http://gv.local/api/container
- Update naam in DB, refresh pagina:
	- kubectl exec -n gv-webstack deploy/gv-postgres -- psql -U gv_user -d gv_db -c "UPDATE users SET name='Geert Vuurstaek' WHERE id=1;"
- Toon Prometheus Targets en metrics:
	- kubectl port-forward -n gv-monitoring svc/gv-prometheus 9090:9090
	- Open http://localhost:9090/targets
	- Query: api_requests_total
- Toon Grafana dashboard
- ArgoCD demo:
	- Open UI, app is Synced/Healthy
	- Kleine wijziging in repo, push, auto-sync tonen