#!/usr/bin/env pwsh
# Remove this course from the machine. The PowerShell twin of cleanup.sh.
#
#   .\lab\cleanup.ps1          delete the cluster and every image it pulled
#   .\lab\cleanup.ps1 -All     the above, plus the kind and helm binaries and the PATH entry
#
# Nothing here touches Docker itself, your other containers, your other images, or your
# real kubeconfig. Deleting the kind cluster removes all 25 lesson namespaces with it -
# there is no need to clean those up first.

param([switch] $All)

$Cluster = 'k8s-lab'
$BinDir  = 'C:\Users\TalGiladi\bin'
$Lab     = $PSScriptRoot

Write-Host "==> deleting the kind cluster (its 3 node containers, and everything running in them)"
kind delete cluster --name $Cluster

Write-Host "==> removing the lab kubeconfig and progress file"
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Lab '.kubeconfig'), (Join-Path $Lab '.progress')

Write-Host "==> removing the context from your real kubeconfig, if kind left one behind"
kubectl config delete-context "kind-$Cluster" 2>&1 | Out-Null
kubectl config delete-cluster "kind-$Cluster" 2>&1 | Out-Null
kubectl config delete-user    "kind-$Cluster" 2>&1 | Out-Null

Write-Host "==> removing the images this course pulled or built"
$pattern = '^(kindest/node|hello|nginx:1\.2[79]-alpine|busybox:1\.37|registry\.k8s\.io/ingress-nginx|registry\.k8s\.io/metrics-server|mcr\.microsoft\.com/dotnet)'
foreach ($img in (docker images --format '{{.Repository}}:{{.Tag}}' 2>$null | Where-Object { $_ -match $pattern })) {
  Write-Host "    $img"
  docker rmi -f $img 2>&1 | Out-Null
}
docker image prune -f 2>&1 | Out-Null
docker builder prune -f 2>&1 | Out-Null

if ($All) {
  Write-Host "==> removing the kind and helm binaries"
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BinDir 'kind.exe'), (Join-Path $BinDir 'helm.exe')
  if ((Test-Path $BinDir) -and -not (Get-ChildItem -Force $BinDir)) { Remove-Item -Force $BinDir }

  Write-Host "==> removing $BinDir from the user PATH"
  $p = [Environment]::GetEnvironmentVariable('Path', 'User')
  $new = (($p -split ';') | Where-Object { $_ -and $_ -ne $BinDir }) -join ';'
  [Environment]::SetEnvironmentVariable('Path', $new, 'User')
  Write-Host "    PATH cleaned"

  Write-Host ""
  Write-Host "Helm also keeps a small cache; remove it if you want nothing left:"
  Write-Host '  Remove-Item -Recurse -Force "$env:LOCALAPPDATA\helm", "$env:APPDATA\helm"'
  Write-Host ""
  Write-Host "And the course itself, if you are done with it:"
  Write-Host '  Remove-Item -Recurse -Force "C:\Users\TalGiladi\OneDrive\repos\course-creator\kubernetes"'
}

Write-Host ""
Write-Host "What is left of the lab:"
docker ps -a --filter "name=$Cluster" --format '  container: {{.Names}}'
docker images 'kindest/node' --format '  image: {{.Repository}}:{{.Tag}}'
docker images 'hello'        --format '  image: {{.Repository}}:{{.Tag}}'
Write-Host "  (nothing listed above means nothing is left)"
