# Dot-source this at the start of every lab session:
#
#     . .\lab\env.ps1
#
# The leading dot is not decoration - it is PowerShell's equivalent of bash's `source`.
# Without it the script runs in a child process and the KUBECONFIG it sets dies with it.
# (`source` itself does not exist in PowerShell, which is why lab/env.sh cannot be used here.)
#
# It points KUBECONFIG at a file that contains ONLY this course's kind cluster, so a
# stray `kubectl delete` cannot possibly land on a work cluster. Your normal kubeconfig
# is untouched, and a new shell goes back to it.
#
# If you would rather use your ordinary kubeconfig, that works too - just run
# `kubectl config use-context kind-k8s-lab` and check `kubectl config current-context`
# before anything destructive. The isolated file is the version that cannot bite you.

if ($MyInvocation.InvocationName -ne '.') {
  Write-Host "env.ps1 must be DOT-SOURCED, or the KUBECONFIG it sets is thrown away:" -ForegroundColor Yellow
  Write-Host "    . .\lab\env.ps1"
  exit 1
}

$_labDir = $PSScriptRoot
$_kubeconfig = Join-Path $_labDir '.kubeconfig'

if (-not (Test-Path $_kubeconfig)) {
  kind export kubeconfig --name k8s-lab --kubeconfig $_kubeconfig
  if ($LASTEXITCODE -ne 0) {
    Write-Host "could not export the kind kubeconfig - is the cluster up? (.\lab\lab.ps1 up)" -ForegroundColor Red
    return
  }
}

$env:KUBECONFIG = $_kubeconfig
Write-Host "KUBECONFIG -> $env:KUBECONFIG"
kubectl config current-context
