$ErrorActionPreference = "Stop"

$Master = "k8s-master"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalK8sPath = (Resolve-Path (Join-Path $ScriptDir "..\k8s")).Path
$RemoteK8sPath = "/tmp/k8s"

$vagrantCmd = $env:VAGRANT_CMD
if ([string]::IsNullOrWhiteSpace($vagrantCmd)) {
    $found = Get-Command vagrant -ErrorAction SilentlyContinue
    if (-not $found) {
        throw "vagrant niet gevonden in PATH. Zet `$env:VAGRANT_CMD = 'C:/Program Files/Vagrant/bin/vagrant.exe' of installeer Vagrant."
    }
    $vagrantCmd = $found.Source
}

Write-Host "[INFO] Zorg voor vereiste namespaces..."
& $vagrantCmd ssh $Master -c "kubectl create ns gv-webstack --dry-run=client -o yaml | kubectl apply -f -"
if ($LASTEXITCODE -ne 0) { throw "Namespaces aanmaken mislukt (gv-webstack)." }
& $vagrantCmd ssh $Master -c "kubectl create ns gv-monitoring --dry-run=client -o yaml | kubectl apply -f -"
if ($LASTEXITCODE -ne 0) { throw "Namespaces aanmaken mislukt (gv-monitoring)." }
& $vagrantCmd ssh $Master -c "kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -"
if ($LASTEXITCODE -ne 0) { throw "Namespaces aanmaken mislukt (argocd)." }

Write-Host "[INFO] Upload lokale k8s manifests naar master..."
& $vagrantCmd ssh $Master -c "rm -rf ${RemoteK8sPath}; mkdir -p ${RemoteK8sPath}"
if ($LASTEXITCODE -ne 0) { throw "Remote manifest map voorbereiden mislukt." }
& $vagrantCmd upload "$LocalK8sPath" "$RemoteK8sPath" $Master
if ($LASTEXITCODE -ne 0) { throw "Upload van k8s manifests naar master mislukt." }

Write-Host "[INFO] Install ingress-nginx..."
& $vagrantCmd ssh $Master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.0/deploy/static/provider/cloud/deploy.yaml"
if ($LASTEXITCODE -ne 0) { throw "Installatie ingress-nginx mislukt." }

Write-Host "[INFO] Wachten op ingress-nginx readiness..."
& $vagrantCmd ssh $Master -c "kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=240s"
if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] ingress-nginx controller niet volledig ready binnen timeout; ga verder met retries/fallback." }
& $vagrantCmd ssh $Master -c "kubectl -n ingress-nginx wait --for=condition=complete job/ingress-nginx-admission-create --timeout=180s"
if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] ingress-nginx-admission-create job niet op tijd klaar." }
& $vagrantCmd ssh $Master -c "kubectl -n ingress-nginx wait --for=condition=complete job/ingress-nginx-admission-patch --timeout=180s"
if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] ingress-nginx-admission-patch job niet op tijd klaar." }

Write-Host "[INFO] Install MetalLB..."
& $vagrantCmd ssh $Master -c "kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml"
if ($LASTEXITCODE -ne 0) { throw "Installatie MetalLB mislukt." }

Write-Host "[INFO] Wachten op MetalLB controller/speaker readiness..."
& $vagrantCmd ssh $Master -c "kubectl -n metallb-system rollout status deployment/controller --timeout=240s"
if ($LASTEXITCODE -ne 0) { throw "MetalLB controller werd niet op tijd ready." }
& $vagrantCmd ssh $Master -c "kubectl -n metallb-system rollout status daemonset/speaker --timeout=240s"
if ($LASTEXITCODE -ne 0) { throw "MetalLB speaker werd niet op tijd ready." }

Write-Host "[INFO] Install ArgoCD..."
& $vagrantCmd ssh $Master -c "kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
if ($LASTEXITCODE -ne 0) { throw "Installatie ArgoCD mislukt." }

Write-Host "[INFO] Deploy lokale manifests..."
& $vagrantCmd ssh $Master -c "kubectl apply -f ${RemoteK8sPath}/namespace.yaml"
if ($LASTEXITCODE -ne 0) { throw "Apply namespace.yaml mislukt." }
& $vagrantCmd ssh $Master -c "kubectl apply -f ${RemoteK8sPath}/argocd/"
if ($LASTEXITCODE -ne 0) { throw "Apply argocd manifests mislukt." }
& $vagrantCmd ssh $Master -c "kubectl apply -f ${RemoteK8sPath}/prometheus/"
if ($LASTEXITCODE -ne 0) { throw "Apply prometheus manifests mislukt." }

$metallbApplied = $false
for ($i = 1; $i -le 5; $i++) {
    & $vagrantCmd ssh $Master -c "kubectl apply --request-timeout=15s -f ${RemoteK8sPath}/metallb/ip-pool.yaml"
    if ($LASTEXITCODE -eq 0) {
        $metallbApplied = $true
        break
    }
    Write-Host "[WARN] MetalLB apply nog niet gelukt (poging $i/5), opnieuw proberen in 5s..."
    Start-Sleep -Seconds 5
}
if (-not $metallbApplied) {
    Write-Host "[WARN] MetalLB webhook blijft onbereikbaar; verwijder validating webhook tijdelijk..."
    & $vagrantCmd ssh $Master -c "kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --ignore-not-found"
    if ($LASTEXITCODE -ne 0) { throw "Kon MetalLB validating webhook niet verwijderen." }

    & $vagrantCmd ssh $Master -c "kubectl apply --request-timeout=15s -f ${RemoteK8sPath}/metallb/ip-pool.yaml"
    if ($LASTEXITCODE -ne 0) { throw "Apply metallb pool mislukt, ook zonder validating webhook." }

    Write-Host "[INFO] Herstel MetalLB core manifests (incl. webhook config)..."
    & $vagrantCmd ssh $Master -c "kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml"
    if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] Herstellen MetalLB webhook config mislukte; cluster blijft werken zonder die validatie." }
}
& $vagrantCmd ssh $Master -c "kubectl apply -f ${RemoteK8sPath}/webstack/"
if ($LASTEXITCODE -ne 0) { throw "Apply webstack manifests mislukt." }

$ingressApplied = $false
for ($i = 1; $i -le 5; $i++) {
    & $vagrantCmd ssh $Master -c "kubectl apply --request-timeout=15s -f ${RemoteK8sPath}/ingress.yaml"
    if ($LASTEXITCODE -eq 0) {
        $ingressApplied = $true
        break
    }

    Write-Host "[WARN] Ingress apply nog niet gelukt (poging $i/5), opnieuw proberen in 5s..."
    Start-Sleep -Seconds 5
}

if (-not $ingressApplied) {
    Write-Host "[WARN] Ingress webhook blijft onbereikbaar; verwijder validating webhook tijdelijk..."
    & $vagrantCmd ssh $Master -c "kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found"
    if ($LASTEXITCODE -ne 0) { throw "Kon ingress-nginx validating webhook niet verwijderen." }

    & $vagrantCmd ssh $Master -c "kubectl apply --request-timeout=15s -f ${RemoteK8sPath}/ingress.yaml"
    if ($LASTEXITCODE -ne 0) { throw "Apply ingress.yaml mislukt, ook zonder validating webhook." }

    Write-Host "[INFO] Herstel ingress-nginx manifests (incl. admission webhook)..."
    & $vagrantCmd ssh $Master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.0/deploy/static/provider/cloud/deploy.yaml"
    if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] Herstellen ingress-nginx webhook config mislukte; cluster werkt verder zonder die validatie." }
}

Write-Host "[INFO] Alle manifests zijn uitgerold."