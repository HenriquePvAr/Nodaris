<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

$ErrorActionPreference = 'Stop'
$taskName = 'Nodaris User Session'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$localRoot = Join-Path $env:LOCALAPPDATA 'Nodaris'
$stateRoot = Join-Path $localRoot 'supervisor'
$stateFile = Join-Path $stateRoot 'state.json'
$stopFile = Join-Path $stateRoot 'stop.request'
$tokenFile = Join-Path $localRoot 'gateway-token.txt'
$profileFile = Join-Path $localRoot 'tunnel-client\profiles\nodaris-local.yaml'
$tunnelExe = Join-Path $localRoot 'tunnel-client\v0.0.15\tunnel-client.exe'
$nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
$tsxCli = Join-Path $repoRoot 'node_modules\tsx\dist\cli.mjs'
$approvedRoot = 'C:\Users\Dell\Downloads\Nodaris'
$maxRestarts = 5
$backoffSeconds = @(5, 15, 30, 60, 120)
$mutex = [Threading.Mutex]::new($false, 'LocalNodaris-M01-Supervisor')
$children = @{}
$restartCounts = @{ agent = 0; gateway = 0; tunnel = 0 }
$statuses = @{ agent = 'pending'; gateway = 'pending'; tunnel = 'pending' }
$circuitOpen = $false

function Write-State([string]$SupervisorStatus) {
  $services = @{}
  foreach ($name in @('agent', 'gateway', 'tunnel')) {
    $pidValue = $null
    if ($children.ContainsKey($name) -and $null -ne $children[$name]) { $pidValue = $children[$name].Id }
    $services[$name] = @{ status = $statuses[$name]; pid = $pidValue; restartCount = $restartCounts[$name] }
  }
  $state = @{ status = $SupervisorStatus; supervisorPid = $PID; updatedAt = [DateTime]::UtcNow.ToString('o'); services = $services }
  $temporary = "$stateFile.tmp"
  [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $stateFile -Force
}

function Test-Port([int]$Port) {
  $client = [Net.Sockets.TcpClient]::new()
  try {
    $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if (-not $pending.AsyncWaitHandle.WaitOne(300)) { return $false }
    $client.EndConnect($pending)
    return $true
  } catch { return $false } finally { $client.Dispose() }
}

function Test-AgentHealth {
  try {
    $headers = @{ Authorization = "Bearer $env:NODARIS_TOKEN" }
    $body = @{ operation = 'health' } | ConvertTo-Json -Compress
    $result = Invoke-RestMethod -Uri 'http://127.0.0.1:3334/rpc' -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 2
    return $result.status -eq 'ok'
  } catch { return $false }
}

function Start-Child([string]$Name, [string]$Executable, [string[]]$Arguments, [int]$Port) {
  if (Test-Port $Port) { throw "Porta local $Port já está ocupada; supervisor não iniciará uma segunda instância." }
  $argumentLine = ($Arguments | ForEach-Object {
      if ($_ -match '\s') { '"' + ($_ -replace '"', '\\"') + '"' } else { $_ }
    }) -join ' '
  $process = Start-Process -FilePath $Executable -ArgumentList $argumentLine -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru
  $children[$Name] = $process
  $statuses[$Name] = 'starting'
  Write-State 'running'
}

function Stop-Child([string]$Name) {
  if ($children.ContainsKey($Name) -and $null -ne $children[$Name]) {
    try {
      $process = Get-Process -Id $children[$Name].Id -ErrorAction SilentlyContinue
      if ($null -ne $process) {
        $taskkill = Join-Path $env:WINDIR 'System32\taskkill.exe'
        Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$process.Id, '/T', '/F') -WindowStyle Hidden -Wait
      }
    } catch { }
    $children[$Name] = $null
  }
  $statuses[$Name] = 'stopped'
}

function Wait-Until([scriptblock]$Condition, [int]$Seconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (& $Condition) { return $true }
    if (Test-Path -LiteralPath $stopFile) { return $false }
    Start-Sleep -Seconds 2
  }
  return $false
}

function Start-Stack {
  $startActions = @{
    agent = { Start-Child 'agent' $nodeExe @($tsxCli, (Join-Path $repoRoot 'apps\agent\src\index.ts')) 3334 }
    gateway = { Start-Child 'gateway' $nodeExe @($tsxCli, (Join-Path $repoRoot 'apps\gateway\src\index.ts')) 3333 }
    tunnel = { Start-TunnelClient }
  }
  $healthChecks = @{
    agent = { Test-AgentHealth }
    gateway = { Test-Port 3333 }
    tunnel = { try { (Invoke-WebRequest -Uri 'http://127.0.0.1:8080/healthz' -TimeoutSec 2 -UseBasicParsing).StatusCode -eq 200 } catch { $false } }
  }
  $timeouts = @{ agent = 45; gateway = 30; tunnel = 45 }

  function Start-TunnelClient {
    $token = $env:NODARIS_TOKEN
    $roots = $env:NODARIS_ALLOWED_ROOTS
    Remove-Item Env:NODARIS_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:NODARIS_ALLOWED_ROOTS -ErrorAction SilentlyContinue
    try { Start-Child 'tunnel' $tunnelExe @('run', '--profile-file', $profileFile) 8080 }
    finally {
      $env:NODARIS_TOKEN = $token
      $env:NODARIS_ALLOWED_ROOTS = $roots
    }
  }

  foreach ($name in @('agent', 'gateway', 'tunnel')) {
    $started = $false
    for ($attempt = 0; $attempt -le $maxRestarts; $attempt++) {
      try {
        & $startActions[$name]
        if (-not (Wait-Until $healthChecks[$name] $timeouts[$name])) { throw "$name não passou no health local." }
        $started = $true
        $statuses[$name] = if ($name -eq 'tunnel') { 'healthy local; control-plane monitorado pelo cliente' } else { 'healthy' }
        Write-State 'running'
        break
      } catch {
        Stop-Child $name
        if (Test-Path -LiteralPath $stopFile) {
          $statuses[$name] = 'stopped_on_request'
          $started = $true
          Write-State 'stopping'
          break
        }
        if ($attempt -ge $maxRestarts) {
          $statuses[$name] = 'circuit_open; intervenção manual necessária'
          $script:circuitOpen = $true
          Write-State 'degraded'
          throw
        }
        $restartCounts[$name]++
        $delay = $backoffSeconds[$attempt]
        $statuses[$name] = "startup_backoff_${delay}s"
        Write-State 'recovering'
        Start-Sleep -Seconds $delay
      }
    }
    if (-not $started) { throw "Inicialização de $name não foi concluída." }
  }
}

function Restart-Child([string]$Name) {
  Stop-Child $Name
  $restartCounts[$Name]++
  if ($restartCounts[$Name] -gt $maxRestarts) {
    $statuses[$Name] = 'circuit_open; intervenção manual necessária'
    $script:circuitOpen = $true
    Write-State 'degraded'
    return
  }
  $delay = $backoffSeconds[$restartCounts[$Name] - 1]
  $statuses[$Name] = "backoff_${delay}s"
  Write-State 'running'
  Start-Sleep -Seconds $delay
  switch ($Name) {
    'agent' {
      Start-Child 'agent' $nodeExe @($tsxCli, (Join-Path $repoRoot 'apps\agent\src\index.ts')) 3334
      if (-not (Wait-Until { Test-AgentHealth } 45)) { throw 'Agente não recuperou health.' }
      $statuses.agent = 'healthy'
    }
    'gateway' {
      Start-Child 'gateway' $nodeExe @($tsxCli, (Join-Path $repoRoot 'apps\gateway\src\index.ts')) 3333
      if (-not (Wait-Until { Test-Port 3333 } 30)) { throw 'Gateway não recuperou o listener local.' }
      $statuses.gateway = 'healthy'
    }
    'tunnel' {
      $token = $env:NODARIS_TOKEN
      $roots = $env:NODARIS_ALLOWED_ROOTS
      Remove-Item Env:NODARIS_TOKEN -ErrorAction SilentlyContinue
      Remove-Item Env:NODARIS_ALLOWED_ROOTS -ErrorAction SilentlyContinue
      try { Start-Child 'tunnel' $tunnelExe @('run', '--profile-file', $profileFile) 8080 }
      finally {
        $env:NODARIS_TOKEN = $token
        $env:NODARIS_ALLOWED_ROOTS = $roots
      }
      if (-not (Wait-Until { try { (Invoke-WebRequest -Uri 'http://127.0.0.1:8080/healthz' -TimeoutSec 2 -UseBasicParsing).StatusCode -eq 200 } catch { $false } } 45)) {
        throw 'Tunnel-client não recuperou o health local.'
      }
      $statuses.tunnel = 'healthy local; cliente tentará reconexão do plano de controle'
    }
  }
}

try {
  if (-not $mutex.WaitOne(0)) { exit 0 }
  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  foreach ($required in @($tokenFile, $profileFile, $tunnelExe, $tsxCli)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw 'Falta um arquivo local necessário; consulte o status sem divulgar segredos.' }
  }
  $env:NODARIS_TOKEN = [IO.File]::ReadAllText($tokenFile).Trim()
  if ($env:NODARIS_TOKEN.Length -lt 32) { throw 'O arquivo Bearer local está vazio ou inválido.' }
  $env:NODARIS_ALLOWED_ROOTS = $approvedRoot
  $env:GATEWAY_HOST = '127.0.0.1'
  $env:GATEWAY_PORT = '3333'
  $env:AGENT_HOST = '127.0.0.1'
  $env:AGENT_PORT = '3334'
  Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
  Write-State 'starting'
  Start-Stack

  while (-not $circuitOpen -and -not (Test-Path -LiteralPath $stopFile)) {
    foreach ($name in @('agent', 'gateway', 'tunnel')) {
      $process = $children[$name]
      if ($null -ne $process -and $process.HasExited) {
        $statuses[$name] = "exited_$($process.ExitCode)"
        Write-State 'recovering'
        try { Restart-Child $name } catch {
          $statuses[$name] = 'circuit_open; reinício falhou; intervenção manual necessária'
          $circuitOpen = $true
          Write-State 'degraded'
        }
      }
    }
    Start-Sleep -Seconds 3
  }
  $shutdownOrder = @('tunnel', 'gateway', 'agent')
  foreach ($name in $shutdownOrder) { Stop-Child $name }
  Write-State $(if ($circuitOpen) { 'degraded' } else { 'stopped' })
} catch {
  foreach ($name in @('tunnel', 'gateway', 'agent')) { Stop-Child $name }
  $statuses.agent = 'error; consulte procedimento local'
  Write-State $(if ($circuitOpen) { 'degraded' } else { 'error' })
} finally {
  try { $mutex.ReleaseMutex() } catch { }
  $mutex.Dispose()
}
