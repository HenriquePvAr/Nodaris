<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

$ErrorActionPreference = 'Stop'
$script:startupTrace = [System.Collections.Generic.List[object]]::new()
$script:startupTimer = [Diagnostics.Stopwatch]::StartNew()
$script:scriptEntryUtc = [DateTime]::UtcNow
$script:scriptEntryWatch = [Diagnostics.Stopwatch]::StartNew()

function Add-StartupCheckpoint([string]$Stage, [string]$Status, [string]$ReasonCode, [DateTime]$TimestampUtc = [DateTime]::UtcNow, [long]$DurationMs = 0) {
  $script:startupTrace.Add([pscustomobject]@{
    component = 'supervisor'
    stage = $Stage
    status = $Status
    reasonCode = $ReasonCode
    timestampUtc = $TimestampUtc.ToUniversalTime().ToString('o')
    durationMs = [Math]::Max(0, $DurationMs)
  })
}

$processStartUtc = $null
try { $processStartUtc = [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime() } catch { }
if ($null -ne $processStartUtc) { Add-StartupCheckpoint 'process' 'started' 'process_created' $processStartUtc }
if ($null -ne $processStartUtc) {
  $processToEntryMs = [Math]::Max(0, [long]($script:scriptEntryUtc.Subtract($processStartUtc).TotalMilliseconds))
  Add-StartupCheckpoint 'bootstrap' 'started' 'script_entry' $script:scriptEntryUtc $processToEntryMs
} else {
  Add-StartupCheckpoint 'bootstrap' 'started' 'script_entry' $script:scriptEntryUtc
}
$launcherEnteredUtc = $env:NODARIS_LAUNCHER_ENTERED_UTC
$launchCallStartedUtc = $env:NODARIS_LAUNCH_CALL_STARTED_UTC
foreach ($trace in @(@{ value = $launcherEnteredUtc; reason = 'launcher_entry' }, @{ value = $launchCallStartedUtc; reason = 'launch_call_started' })) {
  if (-not [string]::IsNullOrWhiteSpace($trace.value) -and $trace.value -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$') {
    $traceDate = [DateTime]::Parse($trace.value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    $launcherDuration = 0
    if ($trace.reason -eq 'launcher_entry' -and -not [string]::IsNullOrWhiteSpace($launchCallStartedUtc) -and $launchCallStartedUtc -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$') {
      $callStartForDuration = [DateTime]::Parse($launchCallStartedUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
      $launcherDuration = [Math]::Max(0, [long]($callStartForDuration.Subtract($traceDate).TotalMilliseconds))
    }
    Add-StartupCheckpoint 'bootstrap' 'started' $trace.reason $traceDate $launcherDuration
  } elseif (-not [string]::IsNullOrWhiteSpace($trace.value)) {
    Add-StartupCheckpoint 'bootstrap' 'failed' 'trace_timestamp_invalid'
  }
}
if ([string]::IsNullOrWhiteSpace($launcherEnteredUtc) -or [string]::IsNullOrWhiteSpace($launchCallStartedUtc)) {
  Add-StartupCheckpoint 'bootstrap' 'failed' 'early_trace_unavailable'
}
if ($null -ne $processStartUtc -and -not [string]::IsNullOrWhiteSpace($launchCallStartedUtc) -and $launchCallStartedUtc -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$') {
  try {
    $launchStarted = [DateTime]::Parse($launchCallStartedUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    $launchElapsed = [Math]::Max(0, [long]($processStartUtc.Subtract($launchStarted).TotalMilliseconds))
    # O timestamp é o horário de criação do processo observado pelo PowerShell, não o retorno direto de WScript.Shell.Run.
    Add-StartupCheckpoint 'bootstrap' 'healthy' 'process_creation_observed' $processStartUtc $launchElapsed
  } catch { }
}
Remove-Item Env:NODARIS_LAUNCHER_ENTERED_UTC -ErrorAction SilentlyContinue
Remove-Item Env:NODARIS_LAUNCH_CALL_STARTED_UTC -ErrorAction SilentlyContinue
Remove-Item Env:NODARIS_ALLOWED_ROOTS -ErrorAction SilentlyContinue

$taskName = 'Nodaris User Session'
$resolveTimer = [Diagnostics.Stopwatch]::StartNew()
Add-StartupCheckpoint 'bootstrap' 'started' 'project_path_resolve_started'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resolveTimer.Stop()
Add-StartupCheckpoint 'bootstrap' 'healthy' 'project_path_resolve_completed' ([DateTime]::UtcNow) $resolveTimer.ElapsedMilliseconds
$localRoot = Join-Path $env:LOCALAPPDATA 'Nodaris'
$stateRoot = Join-Path $localRoot 'supervisor'
$stateFile = Join-Path $stateRoot 'state.json'
$diagnosticsFile = Join-Path $stateRoot 'startup-events.jsonl'
$diagnosticsScript = Join-Path $PSScriptRoot 'diagnostics.ps1'
$lifecycleScript = Join-Path $PSScriptRoot 'lifecycle.ps1'
$stopFile = Join-Path $stateRoot 'stop.request'
$tokenFile = Join-Path $localRoot 'gateway-token.txt'
$profileFile = Join-Path $localRoot 'tunnel-client\profiles\nodaris-local.yaml'
$tunnelExe = Join-Path $localRoot 'tunnel-client\v0.0.15\tunnel-client.exe'
$nodeExe = $null
$tsxModule = Join-Path $repoRoot 'node_modules\tsx'
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
$diagnosticsLoadTimer = [Diagnostics.Stopwatch]::StartNew()
Add-StartupCheckpoint 'bootstrap' 'started' 'diagnostics_load_started'
. $diagnosticsScript
$diagnosticsLoadTimer.Stop()
Add-StartupCheckpoint 'bootstrap' 'healthy' 'diagnostics_load_completed' ([DateTime]::UtcNow) $diagnosticsLoadTimer.ElapsedMilliseconds
$lifecycleLoadTimer = [Diagnostics.Stopwatch]::StartNew()
Add-StartupCheckpoint 'bootstrap' 'started' 'lifecycle_load_started'
. $lifecycleScript
$lifecycleLoadTimer.Stop()
Add-StartupCheckpoint 'bootstrap' 'healthy' 'lifecycle_load_completed' ([DateTime]::UtcNow) $lifecycleLoadTimer.ElapsedMilliseconds

function Flush-StartupTrace {
  $firstWrite = $false
  foreach ($trace in $script:startupTrace) {
    $ok = $false
    try {
      Write-NodarisDiagnosticEvent -Path $diagnosticsFile -Component $trace.component -Stage $trace.stage -Status $trace.status -ReasonCode $trace.reasonCode -Attempt 0 -DurationMs $trace.durationMs -TimestampUtc $trace.timestampUtc
      $ok = $true
    } catch { $ok = $false }
    if ($ok -and -not $firstWrite) {
      $firstWrite = $true
      Write-Diagnostic 'supervisor' 'telemetry' 'healthy' 'first_write_succeeded' 0 $script:scriptEntryWatch.ElapsedMilliseconds
    }
  }
  $script:startupTrace.Clear()
  return $firstWrite
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
    $process = $children[$Name]
    $trackedPid = $process.Id
    if (-not $process.HasExited) {
      $taskkill = Join-Path $env:WINDIR 'System32\taskkill.exe'
      $killer = Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$trackedPid, '/T', '/F') -WindowStyle Hidden -Wait -PassThru
      if ($killer.ExitCode -ne 0 -and -not $process.HasExited) { throw 'NODARIS_STOP_FAILED' }
    }
    $port = @{ agent = 3334; gateway = 3333; tunnel = 8080 }[$Name]
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
      $process.Refresh()
      if ($process.HasExited -and -not (Test-Port $port)) { break }
      Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    $process.Refresh()
    if (-not $process.HasExited) { throw 'NODARIS_STOP_TIMEOUT' }
    if (Test-Port $port) { throw 'NODARIS_PORT_STILL_LISTENING' }
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

function Wait-NodarisBackoff([int]$Seconds) {
  for ($elapsed = 0; $elapsed -lt $Seconds; $elapsed++) {
    if (Test-Path -LiteralPath $stopFile) { return $false }
    Start-Sleep -Seconds 1
  }
  return -not (Test-Path -LiteralPath $stopFile)
}

function Get-NodarisAllowedRootsValue($Configuration) {
  try {
    if ($null -eq $Configuration) { throw 'invalid' }
    $propertyNames = @($Configuration.PSObject.Properties.Name)
    if ($propertyNames.Count -ne 2 -or -not ($propertyNames -ccontains 'schemaVersion') -or -not ($propertyNames -ccontains 'allowedRoots')) { throw 'invalid' }
    if (($Configuration.schemaVersion -isnot [int] -and $Configuration.schemaVersion -isnot [long]) -or $Configuration.schemaVersion -ne 1) { throw 'invalid' }
    if ($Configuration.allowedRoots -isnot [Array] -or $Configuration.allowedRoots.Count -lt 1 -or $Configuration.allowedRoots.Count -gt 32) { throw 'invalid' }

    $validatedRoots = [Collections.Generic.List[string]]::new()
    foreach ($candidate in $Configuration.allowedRoots) {
      if ($candidate -isnot [string] -or [string]::IsNullOrWhiteSpace($candidate) -or $candidate.Contains(';')) { throw 'invalid' }
      if ($candidate -notmatch '^[A-Za-z]:\\' -or $candidate.Contains('/') -or $candidate.Substring(2).Contains(':')) { throw 'invalid' }
      $canonicalRoot = [IO.Path]::GetFullPath($candidate)
      if (-not $canonicalRoot.Equals($candidate, [StringComparison]::OrdinalIgnoreCase)) { throw 'invalid' }
      if (-not (Test-Path -LiteralPath $canonicalRoot -PathType Container) -or -not (Test-NodarisNoReparseComponents $canonicalRoot)) { throw 'invalid' }
      if (Test-NodarisRootWouldBroadenInstall $canonicalRoot) { throw 'invalid' }
      foreach ($existing in $validatedRoots) {
        $existingPrefix = $existing.TrimEnd('\') + '\'
        $candidatePrefix = $canonicalRoot.TrimEnd('\') + '\'
        if ($canonicalRoot.Equals($existing, [StringComparison]::OrdinalIgnoreCase) -or
            $canonicalRoot.StartsWith($existingPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $existing.StartsWith($candidatePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'invalid' }
      }
      $validatedRoots.Add($canonicalRoot)
    }
    return ($validatedRoots -join ';')
  } catch {
    throw 'NODARIS_ROOT_CONFIG_REJECTED'
  }
}

function Initialize-NodarisAllowedRoots([string]$ReaderScriptPath, [string]$ConfigPath) {
  $timer = [Diagnostics.Stopwatch]::StartNew()
  Remove-Item Env:NODARIS_ALLOWED_ROOTS -ErrorAction SilentlyContinue
  try {
    if ([string]::IsNullOrWhiteSpace($ReaderScriptPath) -or [string]::IsNullOrWhiteSpace($ConfigPath) -or
        -not (Test-Path -LiteralPath $ReaderScriptPath -PathType Leaf)) { throw 'NODARIS_ROOT_CONFIG_REJECTED' }
    . $ReaderScriptPath
    $readerResults = @(Read-NodarisLocalRoots -Path $ConfigPath)
    if ($readerResults.Count -ne 1) { throw 'NODARIS_ROOT_CONFIG_REJECTED' }
    $allowedRootsValue = Get-NodarisAllowedRootsValue $readerResults[0]
    $env:NODARIS_ALLOWED_ROOTS = $allowedRootsValue
    $timer.Stop()
    Write-Diagnostic 'configuration' 'configuration' 'healthy' 'configuration_valid' 1 $timer.ElapsedMilliseconds
  } catch {
    Remove-Item Env:NODARIS_ALLOWED_ROOTS -ErrorAction SilentlyContinue
    $timer.Stop()
    Write-Diagnostic 'configuration' 'configuration' 'failed' 'configuration_invalid' 1 $timer.ElapsedMilliseconds
    throw 'NODARIS_ROOT_CONFIG_REJECTED'
  }
}

function Start-Stack {
  $startActions = @{
    agent = { Start-Child 'agent' $nodeExe @('--import', 'tsx', (Join-Path $repoRoot 'apps\agent\src\index.ts')) 3334 }
    gateway = { Start-Child 'gateway' $nodeExe @('--import', 'tsx', (Join-Path $repoRoot 'apps\gateway\src\index.ts')) 3333 }
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
    $script:activeAttempt = 1
    $script:activeTimeout = $timeouts[$name]
    $startEventAction = {
      param($Stage, $Status, $ReasonCode, $Attempt, $Delay)
      $script:activeAttempt = [int]$Attempt
      Write-Diagnostic $name $Stage $Status $ReasonCode $Attempt 0 $timeouts[$name] $Delay
      if ($Stage -eq 'attempt' -and $Status -eq 'healthy') {
        $statuses[$name] = if ($name -eq 'tunnel') { 'healthy local; readiness ChatGPT monitorada' } else { 'healthy' }
        Write-State 'running'
      } elseif ($Stage -eq 'backoff') {
        $statuses[$name] = "startup_backoff_${Delay}s"
        Write-State 'recovering'
      } elseif ($ReasonCode -eq 'circuit_open') {
        $statuses[$name] = 'circuit_open; intervenção manual necessária'
        $script:circuitOpen = $true
        Write-State 'recovering'
      }
    }.GetNewClosure()
    $startupResult = Invoke-NodarisStartupPolicy -Name $name -MaxRetries $maxRestarts `
      -StopAction { Stop-Child $name }.GetNewClosure() `
      -StartAction $startActions[$name] `
      -HealthAction { Wait-ServiceHealth $name $healthChecks[$name] $timeouts[$name] }.GetNewClosure() `
      -BackoffAction { param($seconds) Wait-NodarisBackoff $seconds }.GetNewClosure() `
      -EventAction $startEventAction -FailureReasonAction { $script:lastAgentHealthReason } `
      -StopRequestedAction { Test-Path -LiteralPath $stopFile }
    $restartCounts[$name] = $startupResult.retryCount
    if ($startupResult.status -eq 'stopped') {
      $statuses[$name] = 'stopped_on_request'
      Write-State 'stopping'
      return
    }
    if ($startupResult.status -eq 'circuit_open') { throw 'NODARIS_STARTUP_CIRCUIT_OPEN' }
  }
}

function Restart-Child([string]$Name) {
  $recoveryTimeouts = @{ agent = 45; gateway = 30; tunnel = 45 }
  $script:activeTimeout = $recoveryTimeouts[$Name]
  $stopAction = { Stop-Child $Name }.GetNewClosure()
  $startAction = {
    switch ($Name) {
      'agent' { Start-Child 'agent' $nodeExe @('--import', 'tsx', (Join-Path $repoRoot 'apps\agent\src\index.ts')) 3334 }
      'gateway' { Start-Child 'gateway' $nodeExe @('--import', 'tsx', (Join-Path $repoRoot 'apps\gateway\src\index.ts')) 3333 }
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
      }
    }
  }.GetNewClosure()
  $healthAction = {
    $healthy = switch ($Name) {
      'agent' { Wait-ServiceHealth 'agent' { Test-AgentHealth } 45 }
      'gateway' { Wait-ServiceHealth 'gateway' { Test-GatewayHealth } 30 }
      'tunnel' { Wait-ServiceHealth 'tunnel' { Test-TunnelLocalHealth } 45 }
    }
    if ($healthy) {
      $statuses[$Name] = if ($Name -eq 'tunnel') { 'healthy local; readiness ChatGPT monitorada' } else { 'healthy' }
      Write-State 'running'
    }
    return [bool]$healthy
  }.GetNewClosure()
  $eventAction = {
    param($Stage, $Status, $ReasonCode, $Attempt, $Delay)
    $script:activeAttempt = [int]$Attempt
    Write-Diagnostic $Name $Stage $Status $ReasonCode $Attempt 0 $script:activeTimeout $Delay
    if ($Stage -eq 'backoff') { $statuses[$Name] = "backoff_${Delay}s"; Write-State 'recovering' }
    if ($ReasonCode -eq 'circuit_open') { $statuses[$Name] = 'circuit_open; intervenção manual necessária'; $script:circuitOpen = $true; Write-State 'recovering' }
  }.GetNewClosure()
  $policyResult = Invoke-NodarisRecoveryPolicy -Name $Name -ExistingRetries $restartCounts[$Name] -MaxRetries $maxRestarts `
    -StopAction $stopAction -StartAction $startAction -HealthAction $healthAction `
      -BackoffAction { param($seconds) Wait-NodarisBackoff $seconds }.GetNewClosure() `
    -EventAction $eventAction -FailureReasonAction { $script:lastAgentHealthReason } `
    -StopRequestedAction { Test-Path -LiteralPath $stopFile }
  $restartCounts[$Name] = $policyResult.retryCount
  if ($policyResult.status -eq 'circuit_open') {
    $script:circuitOpen = $true
    $statuses[$Name] = 'circuit_open; intervenção manual necessária'
    Write-State 'recovering'
  } elseif ($policyResult.status -eq 'stopped') {
    $statuses[$Name] = 'stopped_on_request'
    Write-State 'stopping'
  } else {
    Write-State 'running'
  }
}

try {
  $mutexTimer = [Diagnostics.Stopwatch]::StartNew()
  Add-StartupCheckpoint 'mutex' 'started' 'mutex_wait_started'
  if (-not $mutex.WaitOne(0)) {
    $mutexTimer.Stop()
    Add-StartupCheckpoint 'mutex' 'skipped' 'duplicate_instance' ([DateTime]::UtcNow) $mutexTimer.ElapsedMilliseconds
    try {
      Add-StartupCheckpoint 'directory' 'started' 'state_directory_create_started'
      New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
      Add-StartupCheckpoint 'directory' 'healthy' 'state_directory_created'
      Add-StartupCheckpoint 'directory' 'started' 'directory_acl_started'
      Set-NodarisPrivateDirectoryAcl $stateRoot
      if (Test-NodarisPrivateDirectoryAcl $stateRoot) {
        Add-StartupCheckpoint 'directory' 'healthy' 'directory_acl_protected'
        Flush-StartupTrace | Out-Null
      }
      Write-Diagnostic 'supervisor' 'lifecycle' 'skipped' 'duplicate_instance' 1
    } catch { }
    exit 0
  }
  $mutexTimer.Stop()
  Add-StartupCheckpoint 'mutex' 'healthy' 'mutex_acquired' ([DateTime]::UtcNow) $mutexTimer.ElapsedMilliseconds
  $directoryTimer = [Diagnostics.Stopwatch]::StartNew()
  Add-StartupCheckpoint 'directory' 'started' 'state_directory_create_started'
  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  $directoryTimer.Stop()
  Add-StartupCheckpoint 'directory' 'healthy' 'state_directory_created' ([DateTime]::UtcNow) $directoryTimer.ElapsedMilliseconds
  $aclTimer = [Diagnostics.Stopwatch]::StartNew()
  Add-StartupCheckpoint 'directory' 'started' 'directory_acl_started'
  Set-NodarisPrivateDirectoryAcl $stateRoot
  if (-not (Test-NodarisPrivateDirectoryAcl $stateRoot)) { throw 'ACL local de telemetria não pôde ser validada.' }
  $aclTimer.Stop()
  Add-StartupCheckpoint 'directory' 'healthy' 'directory_acl_protected' ([DateTime]::UtcNow) $aclTimer.ElapsedMilliseconds
  Flush-StartupTrace | Out-Null
  Write-Diagnostic 'supervisor' 'lifecycle' 'started' 'mutex_acquired' 1 $mutexTimer.ElapsedMilliseconds
  $startupPhase = 'configuration'
  $configurationTimer = [Diagnostics.Stopwatch]::StartNew()
  Write-Diagnostic 'configuration' 'configuration' 'started' 'none' 1
  $nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
  foreach ($required in @($tokenFile, $profileFile, $tunnelExe)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw 'Falta um arquivo local necessário; consulte o status sem divulgar segredos.' }
  }
  if (-not (Test-Path -LiteralPath $tsxModule -PathType Container)) { throw 'Dependência local do agente indisponível; consulte o status sem divulgar segredos.' }
  $env:NODARIS_TOKEN = [IO.File]::ReadAllText($tokenFile).Trim()
  if ($env:NODARIS_TOKEN.Length -lt 32) { throw 'O arquivo Bearer local está vazio ou inválido.' }
  $rootsReaderScript = Join-Path $PSScriptRoot 'local-roots.ps1'
  $rootsConfigPath = Join-Path $env:LOCALAPPDATA 'Nodaris\config\allowed-roots.json'
  Initialize-NodarisAllowedRoots -ReaderScriptPath $rootsReaderScript -ConfigPath $rootsConfigPath
  $configurationTimer.Stop()
  Write-Diagnostic 'configuration' 'configuration' 'healthy' 'configuration_valid' 1 $configurationTimer.ElapsedMilliseconds
  $startupPhase = 'services'
  $env:GATEWAY_HOST = '127.0.0.1'
  $env:GATEWAY_PORT = '3333'
  $env:AGENT_HOST = '127.0.0.1'
  $env:AGENT_PORT = '3334'
  Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
  Write-State 'starting'
  Start-Stack
  if (-not $circuitOpen -and -not (Test-Path -LiteralPath $stopFile)) {
    Write-Diagnostic 'supervisor' 'lifecycle' 'healthy' 'health_passed' 1 $startupTimer.ElapsedMilliseconds
  }

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
          Write-State 'recovering'
        }
      }
    }
    Start-Sleep -Seconds 3
  }
  $shutdownOrder = @('tunnel', 'gateway', 'agent')
  Stop-NodarisChildrenInOrder -Names $shutdownOrder -StopAction {
    param($name)
    Stop-Child $name
    Write-Diagnostic $name 'lifecycle' 'stopped' 'stop_requested' $restartCounts[$name]
  } | Out-Null
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
  Stop-NodarisChildrenInOrder -Names @('tunnel', 'gateway', 'agent') -StopAction { param($name) Stop-Child $name } | Out-Null
  $statuses.agent = 'error; consulte procedimento local'
  Write-State $(if ($circuitOpen) { 'degraded' } else { 'error' })
} finally {
  try { $mutex.ReleaseMutex() } catch { }
  $mutex.Dispose()
}
