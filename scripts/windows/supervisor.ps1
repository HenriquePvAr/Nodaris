<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

$ErrorActionPreference = 'Stop'
$taskName = 'Nodaris User Session'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$localRoot = Join-Path $env:LOCALAPPDATA 'Nodaris'
$stateRoot = Join-Path $localRoot 'supervisor'
$stateFile = Join-Path $stateRoot 'state.json'
$diagnosticsFile = Join-Path $stateRoot 'startup-events.jsonl'
$diagnosticsScript = Join-Path $PSScriptRoot 'diagnostics.ps1'
$stopFile = Join-Path $stateRoot 'stop.request'
$tokenFile = Join-Path $localRoot 'gateway-token.txt'
$profileFile = Join-Path $localRoot 'tunnel-client\profiles\nodaris-local.yaml'
$tunnelExe = Join-Path $localRoot 'tunnel-client\v0.0.15\tunnel-client.exe'
$nodeExe = $null
$tsxCli = Join-Path $repoRoot 'node_modules\tsx\dist\cli.mjs'
$approvedRoot = 'C:\Users\Dell\Downloads\Nodaris'
$maxRestarts = 5
$mutex = [Threading.Mutex]::new($false, 'LocalNodaris-M01-Supervisor')
$children = @{}
$restartCounts = @{ agent = 0; gateway = 0; tunnel = 0 }
$statuses = @{ agent = 'pending'; gateway = 'pending'; tunnel = 'pending' }
$circuitOpen = $false
$activeAttempt = 0
$activeTimeout = -1
$lastAgentHealthReason = 'health_request_failed'
$lastTunnelReadiness = 'unknown'
$lastTunnelReadinessLogged = ''
$startupPhase = 'configuration'
$startupTimer = [Diagnostics.Stopwatch]::StartNew()
. $diagnosticsScript

function Write-Diagnostic([string]$Component, [string]$Stage, [string]$Status, [string]$ReasonCode, [int]$Attempt = 0, [long]$DurationMs = 0, [int]$TimeoutSeconds = -1, [int]$BackoffSeconds = -1) {
  try {
    Write-NodarisDiagnosticEvent -Path $diagnosticsFile -Component $Component -Stage $Stage -Status $Status -ReasonCode $ReasonCode -Attempt $Attempt -DurationMs $DurationMs -TimeoutSeconds $TimeoutSeconds -BackoffSeconds $BackoffSeconds
  } catch { }
}

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
    if ($result.status -eq 'ok') {
      $script:lastAgentHealthReason = 'health_passed'
      return $true
    }
    $script:lastAgentHealthReason = 'health_unhealthy'
    return $false
  } catch {
    $statusCode = 0
    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
    if ($statusCode -in @(401, 403)) { $script:lastAgentHealthReason = 'health_http_unauthorized' }
    elseif ($statusCode -ge 400 -and $statusCode -lt 600) { $script:lastAgentHealthReason = 'health_http_error' }
    else { $script:lastAgentHealthReason = 'health_transport_error' }
    return $false
  }
}

function Test-GatewayHealth {
  $healthy = Test-Port 3333
  $script:lastAgentHealthReason = if ($healthy) { 'health_passed' } else { 'local_listener_unavailable' }
  return $healthy
}

function Test-TunnelLocalHealth {
  try {
    $healthy = (Invoke-WebRequest -Uri 'http://127.0.0.1:8080/healthz' -TimeoutSec 2 -UseBasicParsing).StatusCode -eq 200
    $script:lastAgentHealthReason = if ($healthy) { 'health_passed' } else { 'health_unhealthy' }
    return $healthy
  } catch {
    $statusCode = 0
    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
    if ($statusCode -ge 400 -and $statusCode -lt 600) { $script:lastAgentHealthReason = 'health_http_error' }
    else { $script:lastAgentHealthReason = 'health_transport_error' }
    return $false
  }
}

function Test-TunnelChatGPTReadiness {
  try {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health?details=true' -TimeoutSec 2
    $reasonCode = ''
    $ready = Test-NodarisTunnelReadiness $health ([ref]$reasonCode)
    $script:lastTunnelReadiness = $reasonCode
    return $ready
  } catch {
    $script:lastTunnelReadiness = 'client_not_live'
    return $false
  }
}

function Wait-ServiceHealth([string]$Name, [scriptblock]$Condition, [int]$TimeoutSeconds) {
  $healthTimer = [Diagnostics.Stopwatch]::StartNew()
  Write-Diagnostic $Name 'health' 'started' 'none' $activeAttempt 0 $TimeoutSeconds
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  $healthy = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    $process = $children[$Name]
    if ($null -ne $process -and $process.HasExited) {
      $script:lastAgentHealthReason = 'process_exited'
      break
    }
    if (& $Condition) {
      $healthy = $true
      break
    }
    if (Test-Path -LiteralPath $stopFile) {
      $script:lastAgentHealthReason = 'stop_requested'
      break
    }
    Start-Sleep -Seconds 2
  }
  $timedOut = -not $healthy -and [DateTime]::UtcNow -ge $deadline
  $healthTimer.Stop()
  $healthReason = if ($healthy) { 'health_passed' } else { $lastAgentHealthReason }
  $healthStatus = if ($healthy) { 'healthy' } elseif ($timedOut) { 'timeout' } else { 'failed' }
  Write-Diagnostic $Name 'health' $healthStatus $healthReason $activeAttempt $healthTimer.ElapsedMilliseconds $TimeoutSeconds
  return $healthy
}

function Start-Child([string]$Name, [string]$Executable, [string[]]$Arguments, [int]$Port) {
  if (Test-Port $Port) { throw 'NODARIS_PORT_IN_USE' }
  $argumentLine = ($Arguments | ForEach-Object {
      if ($_ -match '\s') { '"' + ($_ -replace '"', '\\"') + '"' } else { $_ }
    }) -join ' '
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process -FilePath $Executable -ArgumentList $argumentLine -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru
  $timer.Stop()
  $children[$Name] = $process
  $statuses[$Name] = 'starting'
  Write-Diagnostic $Name 'process' 'started' 'process_started' $activeAttempt $timer.ElapsedMilliseconds $activeTimeout
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
    gateway = { Test-GatewayHealth }
    tunnel = { Test-TunnelLocalHealth }
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
      $script:activeAttempt = $attempt + 1
      $script:activeTimeout = $timeouts[$name]
      $attemptTimer = [Diagnostics.Stopwatch]::StartNew()
      Write-Diagnostic $name 'attempt' 'started' 'none' $activeAttempt 0 $activeTimeout
      $failureReason = 'process_start_failed'
      try {
        & $startActions[$name]
        $healthy = Wait-ServiceHealth $name $healthChecks[$name] $timeouts[$name]
        if (-not $healthy) { $failureReason = $lastAgentHealthReason; throw 'NODARIS_HEALTH_TIMEOUT' }
        $started = $true
        $statuses[$name] = if ($name -eq 'tunnel') { 'healthy local; readiness ChatGPT monitorada' } else { 'healthy' }
        $attemptTimer.Stop()
        Write-Diagnostic $name 'attempt' 'healthy' 'health_passed' $activeAttempt $attemptTimer.ElapsedMilliseconds $activeTimeout
        Write-State 'running'
        break
      } catch {
        if ($_.Exception.Message -eq 'NODARIS_PORT_IN_USE') { $failureReason = 'port_in_use' }
        elseif ($_.Exception.Message -eq 'NODARIS_HEALTH_TIMEOUT') { $failureReason = $lastAgentHealthReason }
        elseif ($_.Exception.Message -ne 'NODARIS_HEALTH_TIMEOUT') { $failureReason = 'process_start_failed' }
        $attemptTimer.Stop()
        Write-Diagnostic $name 'attempt' 'failed' $failureReason $activeAttempt $attemptTimer.ElapsedMilliseconds $activeTimeout
        if ($null -ne $children[$name]) { Write-Diagnostic $name 'process' 'stopped' $failureReason $activeAttempt }
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
          Write-Diagnostic $name 'attempt' 'failed' 'circuit_open' $activeAttempt $attemptTimer.ElapsedMilliseconds $activeTimeout
          Write-State 'degraded'
          throw
        }
        $restartCounts[$name]++
        $delay = Get-NodarisBackoffSeconds $attempt
        $statuses[$name] = "startup_backoff_${delay}s"
        Write-Diagnostic $name 'backoff' 'scheduled' 'retry_scheduled' $activeAttempt 0 $activeTimeout $delay
        Write-State 'recovering'
        $backoffTimer = [Diagnostics.Stopwatch]::StartNew()
        Start-Sleep -Seconds $delay
        $backoffTimer.Stop()
        Write-Diagnostic $name 'backoff' 'completed' 'retry_delay_elapsed' $activeAttempt $backoffTimer.ElapsedMilliseconds $activeTimeout $delay
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
    Write-Diagnostic $Name 'recovery' 'failed' 'circuit_open' $restartCounts[$Name]
    Write-State 'degraded'
    return
  }
  $delay = Get-NodarisBackoffSeconds ($restartCounts[$Name] - 1)
  $statuses[$Name] = "backoff_${delay}s"
  $script:activeAttempt = $restartCounts[$Name]
  $recoveryTimeouts = @{ agent = 45; gateway = 30; tunnel = 45 }
  $script:activeTimeout = $recoveryTimeouts[$Name]
  Write-Diagnostic $Name 'recovery' 'started' 'process_exited' $activeAttempt 0 $activeTimeout $delay
  Write-Diagnostic $Name 'backoff' 'scheduled' 'retry_scheduled' $activeAttempt 0 $activeTimeout $delay
  Write-State 'running'
  $backoffTimer = [Diagnostics.Stopwatch]::StartNew()
  Start-Sleep -Seconds $delay
  $backoffTimer.Stop()
  Write-Diagnostic $Name 'backoff' 'completed' 'retry_delay_elapsed' $activeAttempt $backoffTimer.ElapsedMilliseconds $activeTimeout $delay
  switch ($Name) {
    'agent' {
      Start-Child 'agent' $nodeExe @($tsxCli, (Join-Path $repoRoot 'apps\agent\src\index.ts')) 3334
      if (-not (Wait-ServiceHealth 'agent' { Test-AgentHealth } 45)) { throw 'NODARIS_HEALTH_TIMEOUT' }
      $statuses.agent = 'healthy'
      Write-Diagnostic 'agent' 'recovery' 'healthy' 'health_passed' $activeAttempt 0 $activeTimeout
    }
    'gateway' {
      Start-Child 'gateway' $nodeExe @($tsxCli, (Join-Path $repoRoot 'apps\gateway\src\index.ts')) 3333
      if (-not (Wait-ServiceHealth 'gateway' { Test-GatewayHealth } 30)) { throw 'NODARIS_HEALTH_TIMEOUT' }
      $statuses.gateway = 'healthy'
      Write-Diagnostic 'gateway' 'recovery' 'healthy' 'health_passed' $activeAttempt 0 $activeTimeout
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
      if (-not (Wait-ServiceHealth 'tunnel' { Test-TunnelLocalHealth } 45)) {
        throw 'NODARIS_HEALTH_TIMEOUT'
      }
      $statuses.tunnel = 'healthy local; cliente tentará reconexão do plano de controle'
      Write-Diagnostic 'tunnel' 'recovery' 'healthy' 'health_passed' $activeAttempt 0 $activeTimeout
    }
  }
}

try {
  if (-not $mutex.WaitOne(0)) {
    try {
      New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
      Set-NodarisPrivateDirectoryAcl $stateRoot
      Write-Diagnostic 'supervisor' 'lifecycle' 'skipped' 'duplicate_instance' 1
    } catch { }
    exit 0
  }
  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  Set-NodarisPrivateDirectoryAcl $stateRoot
  Write-Diagnostic 'supervisor' 'lifecycle' 'started' 'mutex_acquired' 1
  $startupPhase = 'configuration'
  $configurationTimer = [Diagnostics.Stopwatch]::StartNew()
  Write-Diagnostic 'configuration' 'configuration' 'started' 'none' 1
  $nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
  foreach ($required in @($tokenFile, $profileFile, $tunnelExe, $tsxCli)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw 'Falta um arquivo local necessário; consulte o status sem divulgar segredos.' }
  }
  $env:NODARIS_TOKEN = [IO.File]::ReadAllText($tokenFile).Trim()
  if ($env:NODARIS_TOKEN.Length -lt 32) { throw 'O arquivo Bearer local está vazio ou inválido.' }
  $configurationTimer.Stop()
  Write-Diagnostic 'configuration' 'configuration' 'healthy' 'configuration_valid' 1 $configurationTimer.ElapsedMilliseconds
  $startupPhase = 'services'
  $env:NODARIS_ALLOWED_ROOTS = $approvedRoot
  $env:GATEWAY_HOST = '127.0.0.1'
  $env:GATEWAY_PORT = '3333'
  $env:AGENT_HOST = '127.0.0.1'
  $env:AGENT_PORT = '3334'
  Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
  Write-State 'starting'
  Start-Stack
  Write-Diagnostic 'supervisor' 'lifecycle' 'healthy' 'health_passed' 1 $startupTimer.ElapsedMilliseconds

  while (-not $circuitOpen -and -not (Test-Path -LiteralPath $stopFile)) {
    $readinessTimer = [Diagnostics.Stopwatch]::StartNew()
    $chatGptReady = Test-TunnelChatGPTReadiness
    $readinessTimer.Stop()
    $readinessKey = '{0}:{1}' -f $chatGptReady,$lastTunnelReadiness
    if ($readinessKey -ne $lastTunnelReadinessLogged) {
      $readinessStatus = if ($chatGptReady) { 'ready' } else { 'failed' }
      Write-Diagnostic 'tunnel' 'readiness' $readinessStatus $lastTunnelReadiness $restartCounts.tunnel $readinessTimer.ElapsedMilliseconds -1
      $lastTunnelReadinessLogged = $readinessKey
    }
    foreach ($name in @('agent', 'gateway', 'tunnel')) {
      $process = $children[$name]
      if ($null -ne $process -and $process.HasExited) {
        $statuses[$name] = "exited_$($process.ExitCode)"
        Write-Diagnostic $name 'recovery' 'failed' 'process_exited' ($restartCounts[$name] + 1)
        Write-State 'recovering'
        try { Restart-Child $name } catch {
          $statuses[$name] = 'circuit_open; reinício falhou; intervenção manual necessária'
          $circuitOpen = $true
          $recoveryFailure = if ($_.Exception.Message -eq 'NODARIS_HEALTH_TIMEOUT') { $lastAgentHealthReason } elseif ($_.Exception.Message -eq 'NODARIS_PORT_IN_USE') { 'port_in_use' } else { 'process_start_failed' }
          Write-Diagnostic $name 'recovery' 'failed' $recoveryFailure $restartCounts[$name]
          Write-Diagnostic $name 'recovery' 'failed' 'circuit_open' $restartCounts[$name]
          Write-State 'degraded'
        }
      }
    }
    Start-Sleep -Seconds 3
  }
  $shutdownOrder = @('tunnel', 'gateway', 'agent')
  foreach ($name in $shutdownOrder) {
    Write-Diagnostic $name 'lifecycle' 'stopped' 'stop_requested' $restartCounts[$name]
    Stop-Child $name
  }
  Write-State $(if ($circuitOpen) { 'degraded' } else { 'stopped' })
} catch {
  $reason = if ($startupPhase -eq 'configuration') { 'configuration_invalid' } else { 'startup_failed' }
  $startupTimer.Stop()
  $failureDuration = $startupTimer.ElapsedMilliseconds
  if ($startupPhase -eq 'configuration' -and $null -ne $configurationTimer) {
    $configurationTimer.Stop()
    $failureDuration = $configurationTimer.ElapsedMilliseconds
  }
  Write-Diagnostic $(if ($startupPhase -eq 'configuration') { 'configuration' } else { 'supervisor' }) 'lifecycle' 'failed' $reason 1 $failureDuration
  foreach ($name in @('tunnel', 'gateway', 'agent')) { Stop-Child $name }
  $statuses.agent = 'error; consulte procedimento local'
  Write-State $(if ($circuitOpen) { 'degraded' } else { 'error' })
} finally {
  try { $mutex.ReleaseMutex() } catch { }
  $mutex.Dispose()
}
