#!/usr/bin/env pwsh
# k8s-lab driver -- the PowerShell twin of lab.sh. Same commands, same progress file,
# so you can switch shells mid-course and lose nothing.
#
#   .\lab\lab.ps1              where you are, what's next
#   .\lab\lab.ps1 up           create the kind cluster
#   .\lab\lab.ps1 check NN     grade exercise NN
#   .\lab\lab.ps1 hint NN      a nudge, not the answer
#   .\lab\lab.ps1 solve NN     print the solution manifests
#   .\lab\lab.ps1 reset NN     delete exercise NN's namespace, start it over
#   .\lab\lab.ps1 down         delete the cluster (keeps the course files)
#
# Every exercise lives in its own namespace, lesson-NN, so nothing you do in one
# can break another.
#
# The 25 checkers are bash scripts and stay that way - they are the graded contract of
# the course, and two copies of a grader is how a course starts lying to you. `check`
# runs them through Git Bash, which this script locates itself (see Get-GitBash for why
# it must not simply trust `bash` on PATH).

param(
  [Parameter(Position = 0)] [string] $Command = 'status',
  [Parameter(Position = 1)] [string] $Number
)

$Lab      = $PSScriptRoot
$Root     = Split-Path -Parent $Lab
$Progress = Join-Path $Lab '.progress'
$Manifest = Join-Path $Lab 'manifest.tsv'
$Modules  = Join-Path $Lab 'modules.tsv'
$Cluster  = 'k8s-lab'
$Ctx      = "kind-$Cluster"

if (-not (Test-Path $Progress)) { New-Item -ItemType File -Path $Progress | Out-Null }

# Never grade against whatever context happens to be current - a kubeconfig with a work
# cluster in it is exactly how accidents happen. Prefer the lab's own kubeconfig, and
# pin the context on every call regardless.
$LabKubeconfig = Join-Path $Lab '.kubeconfig'
if (Test-Path $LabKubeconfig) { $env:KUBECONFIG = $LabKubeconfig }

function k { kubectl --context $Ctx @args }

function Pad([string]$n) { '{0:00}' -f [int]$n }

function Get-Rows {
  Get-Content $Manifest | Where-Object { $_.Trim() } | ForEach-Object {
    $c = $_ -split "`t"
    [pscustomobject]@{ nn = $c[0]; module = $c[1]; lesson = $c[2]; title = $c[3] }
  }
}

function Get-Row([string]$n) { Get-Rows | Where-Object { $_.nn -eq $n } | Select-Object -First 1 }

# the module's subject, so the listing says what a module is about
function Get-ModuleTitle([string]$m) {
  foreach ($line in Get-Content $Modules) {
    $c = $line -split "`t"
    if ($c[0] -eq $m) { return $c[1] }
  }
  return ''
}

function Get-LessonPath([string]$n) {
  $r = Get-Row $n
  if (-not $r) { return $null }
  "lessons/module-$($r.module)/lesson-$($r.lesson).md"
}

function Test-ClusterUp {
  kubectl --context $Ctx cluster-info 2>&1 | Out-Null
  return ($LASTEXITCODE -eq 0)
}

# `bash` on a Windows PATH is usually C:\Windows\System32\bash.exe - the WSL launcher,
# which is a different machine with its own filesystem and no kubectl on it. Running the
# checkers there fails in ways that look like YOUR exercise is broken. So find Git Bash
# by path instead of trusting the name.
function Get-GitBash {
  $candidates = @()
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) {
    # ...\Git\cmd\git.exe or ...\Git\bin\git.exe  ->  ...\Git\bin\bash.exe
    $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
    $candidates += (Join-Path $gitRoot 'bin\bash.exe')
  }
  $candidates += @(
    'C:\Program Files\Git\bin\bash.exe'
    'C:\Program Files (x86)\Git\bin\bash.exe'
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
  )
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}

function Invoke-Checker([string]$ScriptPath) {
  $bash = Get-GitBash
  if (-not $bash) {
    Write-Host "  Git Bash not found, and the 25 checkers are bash scripts."
    Write-Host "  Install Git for Windows (https://git-scm.com/download/win) - the same Git Bash"
    Write-Host "  the course was written in - and run this again."
    Write-Host "  (WSL's bash will not do: it is a separate machine with no kubectl on it.)"
    return 127
  }
  # Write-Host, not bare output: anything a function *emits* is captured by the caller's
  # `$rc = Invoke-Checker ...`, which would swallow every PASS/FAIL line into the variable
  # and leave the student staring at an empty grade.
  & $bash ($ScriptPath -replace '\\', '/') 2>&1 | ForEach-Object { Write-Host $_ }
  return $LASTEXITCODE
}

function Invoke-Up {
  if (-not (Test-ClusterUp)) {
    kind create cluster --config (Join-Path $Lab 'cluster\kind-config.yaml') --wait 180s
    if ($LASTEXITCODE -ne 0) { return }
  } else {
    Write-Host "cluster '$Cluster' is already up"
  }
  kind export kubeconfig --name $Cluster --kubeconfig $LabKubeconfig 2>&1 | Out-Null
  Write-Host ""
  Write-Host "Now isolate your shell from any other cluster in your kubeconfig:"
  Write-Host "    . .\lab\env.ps1"
}

function Invoke-Down { kind delete cluster --name $Cluster }

function Show-Status {
  Write-Host ""
  Write-Host "  Kubernetes, from Docker to mastery -- lab progress"
  Write-Host ""
  if (Test-ClusterUp) {
    $nodes = @(k get nodes --no-headers 2>$null).Count
    Write-Host ("  cluster: UP   ({0} nodes, context {1})" -f $nodes, $Ctx)
  } else {
    Write-Host "  cluster: DOWN -- run: .\lab\lab.ps1 up"
  }
  Write-Host ""

  $done = @(Get-Content $Progress | Where-Object { $_.Trim() })
  $next = ''; $doneCount = 0; $total = 0; $lastMod = ''
  foreach ($r in Get-Rows) {
    $total++
    if ($r.module -ne $lastMod) {
      Write-Host ""
      Write-Host ("  Module {0} -- {1}" -f $r.module, (Get-ModuleTitle $r.module))
      $lastMod = $r.module
    }
    $mark = '[ ]'
    if ($done -contains $r.nn) { $mark = '[x]'; $doneCount++ }
    elseif (-not $next) { $next = $r.nn }
    Write-Host ("    {0} {1}  {2}" -f $mark, $r.nn, $r.title)
  }

  Write-Host ""
  Write-Host ("  {0} of {1} exercises complete" -f $doneCount, $total)
  Write-Host ""
  if ($next) {
    Write-Host ("  next up: {0}" -f (Get-LessonPath $next))
    Write-Host ("  read it, do it, then:  .\lab\lab.ps1 check {0}" -f $next)
  } else {
    Write-Host "  Every exercise is complete. That is the whole course."
    Write-Host "  Tear the cluster down with: .\lab\lab.ps1 down"
  }
  Write-Host ""
}

function Invoke-Check([string]$n) {
  $n = Pad $n
  $script = Join-Path $Lab "checks\$n.sh"
  if (-not (Test-Path $script)) { Write-Host "no checker for exercise $n"; exit 1 }
  if (-not (Test-ClusterUp))    { Write-Host "cluster is down -- run: .\lab\lab.ps1 up"; exit 1 }
  Write-Host ""
  Write-Host ("  exercise {0} -- {1}" -f $n, (Get-Row $n).title)
  Write-Host "  --------------------------------------------------------------"
  $rc = Invoke-Checker $script
  Write-Host "  --------------------------------------------------------------"
  if ($rc -eq 0) {
    if (@(Get-Content $Progress) -notcontains $n) { Add-Content -Path $Progress -Value $n }
    Write-Host "  PASS -- exercise $n complete."
    Write-Host ""
    exit 0
  }
  Write-Host "  Not yet. Fix the FAIL lines above and run this again."
  Write-Host "  Nudge: .\lab\lab.ps1 hint $n     Answer: .\lab\lab.ps1 solve $n"
  Write-Host ""
  exit 1
}

function Show-Hint([string]$n) {
  $n = Pad $n
  $f = Join-Path $Root (Get-LessonPath $n)
  if (-not (Test-Path $f)) { Write-Host "lesson file not found: $f"; exit 1 }
  $p = $false
  foreach ($line in Get-Content $f) {
    if ($line -match '^## Hints') { $p = $true }
    if ($p -and $line -match '^## Solution') { break }
    if ($p) { Write-Output $line }
  }
}

function Show-Solution([string]$n) {
  $n = Pad $n
  $dir = Join-Path $Lab "solutions\$n"
  if (Test-Path $dir) {
    foreach ($f in Get-ChildItem -Recurse -File $dir) {
      Write-Output ("===== {0} =====" -f ($f.FullName.Substring($Root.Length + 1) -replace '\\', '/'))
      Get-Content $f.FullName | ForEach-Object { Write-Output $_ }
      Write-Host ""
    }
  }
  $f = Join-Path $Root (Get-LessonPath $n)
  if (Test-Path $f) {
    $p = $false
    foreach ($line in Get-Content $f) {
      if ($line -match '^## Solution') { $p = $true }
      if ($p) { Write-Host $line }
    }
  }
}

function Invoke-Reset([string]$n) {
  $n = Pad $n
  k delete namespace "lesson-$n" --ignore-not-found
  # Materialise first: a pipeline that filters down to nothing never reaches Set-Content,
  # which would silently leave the exercise still marked done.
  $kept = @(@(Get-Content $Progress) | Where-Object { $_ -ne $n })
  Set-Content -Path $Progress -Value $kept
  Write-Host "exercise $n reset"
}

switch ($Command) {
  ''       { Show-Status }
  'status' { Show-Status }
  'up'     { Invoke-Up }
  'down'   { Invoke-Down }
  'check'  { if (-not $Number) { Write-Host 'usage: lab.ps1 check NN'; exit 1 }; Invoke-Check $Number }
  'hint'   { if (-not $Number) { Write-Host 'usage: lab.ps1 hint NN';  exit 1 }; Show-Hint $Number }
  'solve'  { if (-not $Number) { Write-Host 'usage: lab.ps1 solve NN'; exit 1 }; Show-Solution $Number }
  'reset'  { if (-not $Number) { Write-Host 'usage: lab.ps1 reset NN'; exit 1 }; Invoke-Reset $Number }
  default  { Write-Host 'usage: lab.ps1 [status|up|down|check NN|hint NN|solve NN|reset NN]' }
}
