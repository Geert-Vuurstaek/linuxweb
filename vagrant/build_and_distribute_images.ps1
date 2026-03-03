$ErrorActionPreference = "Stop"

$Images = @("gv-api:1.3", "frontend-apache")
$Nodes = @("k8s-master", "k8s-worker1", "k8s-worker2")

$vagrantCmd = $env:VAGRANT_CMD
if ([string]::IsNullOrWhiteSpace($vagrantCmd)) {
    $found = Get-Command vagrant -ErrorAction SilentlyContinue
    if (-not $found) {
        throw "vagrant niet gevonden in PATH. Zet `$env:VAGRANT_CMD = 'C:/Program Files/Vagrant/bin/vagrant.exe' of installeer Vagrant."
    }
    $vagrantCmd = $found.Source
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker niet gevonden in PATH. Start Docker Desktop en probeer opnieuw."
}

Write-Host "[INFO] Bouwen van images op host..."
docker build -t gv-api:1.3 ../api
docker build -t frontend-apache ../frontend

foreach ($image in $Images) {
    $safeImageName = $image.Replace(":", "_")
    $archive = Join-Path $env:TEMP "$safeImageName.tar"
    $remoteArchive = "/tmp/$safeImageName.tar"

    Write-Host "[INFO] Maak archive voor $image..."
    docker save -o $archive $image
    if ($LASTEXITCODE -ne 0) { throw "docker save mislukt voor $image" }

    foreach ($node in $Nodes) {
        Write-Host "[INFO] Kopieer $image naar $node..."
        & $vagrantCmd upload "$archive" "$remoteArchive" $node
        if ($LASTEXITCODE -ne 0) { throw "vagrant upload mislukt voor $node" }

        & $vagrantCmd ssh $node -c "sudo ctr -n k8s.io images import '${remoteArchive}'"
        if ($LASTEXITCODE -ne 0) { throw "image import mislukt op $node" }

        & $vagrantCmd ssh $node -c "rm -f '${remoteArchive}'"
        if ($LASTEXITCODE -ne 0) { throw "cleanup mislukt op $node" }
    }

    Remove-Item -Force -ErrorAction SilentlyContinue $archive
}

Write-Host "[INFO] Images zijn beschikbaar op alle nodes."