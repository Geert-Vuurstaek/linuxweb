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