param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$TestRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $repoRoot 'scripts\windows\diagnostics.ps1')
. (Join-Path $repoRoot 'scripts\windows\lifecycle.ps1')
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
Set-NodarisPrivateDirectoryAcl $TestRoot

$expectedBackoff = @(5, 15, 30, 60, 120)
for ($index = 0; $index -lt $expectedBackoff.Count; $index++) {
  if ((Get-NodarisBackoffSeconds $index) -ne $expectedBackoff[$index]) { throw 'Backoff fixture divergiu da política.' }
}
$backoffRejected = $false
try { Get-NodarisBackoffSeconds 5 | Out-Null } catch { $backoffRejected = $true }
if (-not $backoffRejected) { throw 'Backoff aceitou tentativa além do limite.' }

$stopOrder = [System.Collections.Generic.List[string]]::new()
$stopped = Stop-NodarisChildrenInOrder -Names @('tunnel', 'gateway', 'agent') -StopAction {
  param($name)
  $stopOrder.Add($name) | Out-Null
}
if (($stopped -join ',') -ne 'tunnel,gateway,agent' -or ($stopOrder -join ',') -ne 'tunnel,gateway,agent') {
  throw 'Parada supervisionada não respeitou a ordem dos componentes.'
}
$partialStopOrder = [System.Collections.Generic.List[string]]::new()
$partialStopFailed = $false
try {
  Stop-NodarisChildrenInOrder -Names @('tunnel', 'gateway', 'agent') -StopAction {
    param($name)
    $partialStopOrder.Add($name) | Out-Null
    if ($name -eq 'gateway') { throw 'fixture stop failure' }
  } | Out-Null
} catch { $partialStopFailed = $true }
if (-not $partialStopFailed -or ($partialStopOrder -join ',') -ne 'tunnel,gateway,agent') {
  throw 'Parada parcial impediu tentativa de encerrar os componentes restantes.'
}

$startupEvents = [System.Collections.Generic.List[string]]::new()
$startupStarts = 0
$startupDelays = [System.Collections.Generic.List[int]]::new()
$startup = Invoke-NodarisStartupPolicy -Name agent -MaxRetries 5 `
  -StopAction { } `
  -StartAction { $script:startupStarts++; if ($script:startupStarts -eq 1) { throw 'NODARIS_PORT_IN_USE' } } `
  -HealthAction { return $true } `
  -BackoffAction { param($seconds) $startupDelays.Add([int]$seconds) | Out-Null } `
  -EventAction { param($stage,$status,$reason,$attempt,$delay) $startupEvents.Add("$stage/$status/$reason/$attempt/$delay") | Out-Null } `
  -FailureReasonAction { 'health_transport_error' } `
  -StopRequestedAction { $false }
if ($startup.status -ne 'healthy' -or $startup.retryCount -ne 1 -or $startupStarts -ne 2 -or $startupDelays[0] -ne 5) {
  throw 'Falha durante inicialização não foi recuperada após o backoff esperado.'
}

$startupDelays.Clear()
$startupFailures = Invoke-NodarisStartupPolicy -Name gateway -MaxRetries 5 `
  -StopAction { } `
  -StartAction { throw 'NODARIS_PORT_IN_USE' } `
  -HealthAction { $true } `
  -BackoffAction { param($seconds) $startupDelays.Add([int]$seconds) | Out-Null } `
  -EventAction { } -FailureReasonAction { 'health_transport_error' } -StopRequestedAction { $false }
if ($startupFailures.status -ne 'circuit_open' -or $startupFailures.retryCount -ne 5 -or ($startupDelays -join ',') -ne '5,15,30,60,120') {
  throw 'Circuit breaker da inicialização não respeitou o limite de retries.'
}

$cancelStarts = 0
$cancelledStartup = Invoke-NodarisStartupPolicy -Name agent -MaxRetries 5 `
  -StopAction { } `
  -StartAction { $script:cancelStarts++; throw 'NODARIS_PORT_IN_USE' } `
  -HealthAction { $true } `
  -BackoffAction { return $false } `
  -EventAction { } -FailureReasonAction { 'health_transport_error' } -StopRequestedAction { $false }
if ($cancelledStartup.status -ne 'stopped' -or $cancelStarts -ne 1) {
  throw 'Backoff cancelado não respeitou pedido de parada.'
}

$retryEvents = [System.Collections.Generic.List[string]]::new()
$startCalls = 0
$healthCalls = 0
$delays = [System.Collections.Generic.List[int]]::new()
$recovery = Invoke-NodarisRecoveryPolicy -Name agent -ExistingRetries 0 -MaxRetries 5 `
  -StopAction { } `
  -StartAction { $script:startCalls++; if ($script:startCalls -eq 1) { throw 'NODARIS_PORT_IN_USE' } } `
  -HealthAction { $script:healthCalls++; return $true } `
  -BackoffAction { param($seconds) $delays.Add([int]$seconds) | Out-Null } `
  -EventAction { param($stage,$status,$reason,$attempt,$delay) $retryEvents.Add("$stage/$status/$reason/$attempt/$delay") | Out-Null } `
  -FailureReasonAction { 'health_transport_error' } `
  -StopRequestedAction { $false }
if ($recovery.status -ne 'healthy' -or $recovery.retryCount -ne 2 -or $startCalls -ne 2 -or $healthCalls -ne 1 -or $delays[0] -ne 5) {
  throw 'Recuperação não repetiu após falha transitória com backoff.'
}
$firstStartIndex = $retryEvents.IndexOf('recovery/started/process_exited/1/5')
$firstSuccessIndex = $retryEvents.IndexOf('recovery/healthy/health_passed/2/15')
if ($firstStartIndex -lt 0 -or $firstSuccessIndex -le $firstStartIndex) { throw 'Reinício não respeitou a sequência de parada, backoff e health.' }

$initEvents = [System.Collections.Generic.List[string]]::new()
$initStarts = 0
$initHealth = 0
$initRecovery = Invoke-NodarisRecoveryPolicy -Name tunnel -ExistingRetries 0 -MaxRetries 5 `
  -StopAction { } `
  -StartAction { $script:initStarts++ } `
  -HealthAction { $script:initHealth++; if ($script:initHealth -eq 1) { return $false }; return $true } `
  -BackoffAction { } `
  -EventAction { param($stage,$status,$reason,$attempt,$delay) $initEvents.Add("$stage/$status/$reason") | Out-Null } `
  -FailureReasonAction { 'health_transport_error' } `
  -StopRequestedAction { $false }
if ($initRecovery.status -ne 'healthy' -or $initRecovery.retryCount -ne 2 -or $initStarts -ne 2 -or $initHealth -ne 2) {
  throw 'Falha de inicialização não foi classificada e recuperada de forma limitada.'
}
if ($initEvents -notcontains 'recovery/failed/health_transport_error') { throw 'Falha de health não recebeu motivo sanitizado.' }

$delays.Clear()
$failureEvents = [System.Collections.Generic.List[string]]::new()
$failureStarts = 0
$failureRecovery = Invoke-NodarisRecoveryPolicy -Name gateway -ExistingRetries 0 -MaxRetries 5 `
  -StopAction { } `
  -StartAction { $script:failureStarts++ } `
  -HealthAction { return $false } `
  -BackoffAction { param($seconds) $delays.Add([int]$seconds) | Out-Null } `
  -EventAction { param($stage,$status,$reason,$attempt,$delay) $failureEvents.Add("$stage/$status/$reason") | Out-Null } `
  -FailureReasonAction { 'health_transport_error' } `
  -StopRequestedAction { $false }
if ($failureRecovery.status -ne 'circuit_open' -or $failureRecovery.retryCount -ne 5 -or $failureStarts -ne 5) {
  throw 'Circuit breaker não abriu após o limite configurado.'
}
if (($delays -join ',') -ne '5,15,30,60,120' -or $failureEvents[-1] -ne 'recovery/failed/circuit_open') {
  throw 'Backoff ou evento de abertura do circuit breaker divergiu.'
}

$mutexName = 'LocalNodaris-M01-Test-' + [Guid]::NewGuid().ToString('N')
$firstMutex = [Threading.Mutex]::new($false, $mutexName)
try {
  if (-not $firstMutex.WaitOne(0)) { throw 'Fixture não conseguiu adquirir o mutex inicial.' }
  $escapedMutexName = $mutexName.Replace("'", "''")
  $mutexProbe = "`$mutex = [Threading.Mutex]::OpenExisting('$escapedMutexName'); if (`$mutex.WaitOne(0)) { `$mutex.ReleaseMutex(); exit 1 } else { exit 0 }"
  $probe = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', $mutexProbe) -WindowStyle Hidden -Wait -PassThru
  if ($probe.ExitCode -ne 0) { throw 'Proteção contra supervisor duplicado falhou.' }
} finally {
  try { $firstMutex.ReleaseMutex() } catch { }
  $firstMutex.Dispose()
}

$scopeRejected = $false
try {
  Invoke-NodarisRecoveryPolicy -Name shell -ExistingRetries 0 -MaxRetries 5 -StopAction { } -StartAction { } `
    -HealthAction { $true } -BackoffAction { } -EventAction { } -FailureReasonAction { 'none' } -StopRequestedAction { $false } | Out-Null
} catch { $scopeRejected = $true }
if (-not $scopeRejected) { throw 'Política de ciclo de vida aceitou componente fora do escopo.' }

$readyFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tunnel-health-ready.json') -Raw | ConvertFrom-Json
$readyFixture.components.'control-plane'.details.last_success = [DateTimeOffset]::UtcNow.ToString('o')
$reasonCode = ''
if (-not (Test-NodarisTunnelReadiness $readyFixture ([ref]$reasonCode)) -or $reasonCode -ne 'poll_current') {
  throw 'Fixture de túnel pronto foi classificada incorretamente.'
}

$readyFixture.components.'control-plane'.details.last_success = [DateTimeOffset]::UtcNow.AddHours(-2).ToString('o')
if ((Test-NodarisTunnelReadiness $readyFixture ([ref]$reasonCode)) -or $reasonCode -ne 'poll_stale') {
  throw 'Polling antigo foi classificado como pronto.'
}

$pendingFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tunnel-health-pending.json') -Raw | ConvertFrom-Json
if ((Test-NodarisTunnelReadiness $pendingFixture ([ref]$reasonCode)) -or $reasonCode -ne 'control_plane_not_polling') {
  throw 'Fixture pendente foi classificada como pronta.'
}

$logPath = Join-Path $TestRoot 'startup-events.jsonl'
Write-NodarisDiagnosticEvent -Path $logPath -Component agent -Stage health -Status timeout -ReasonCode health_timeout -Attempt 1 -DurationMs 45000 -TimeoutSeconds 45 -BackoffSeconds 5
Write-NodarisDiagnosticEvent -Path $logPath -Component agent -Stage attempt -Status failed -ReasonCode process_start_failed -Attempt 1 -DurationMs 120 -TimeoutSeconds 45
Write-NodarisDiagnosticEvent -Path $logPath -Component agent -Stage backoff -Status scheduled -ReasonCode retry_scheduled -Attempt 1 -TimeoutSeconds 45 -BackoffSeconds 5
$rejectedReason = $false
try {
  Write-NodarisDiagnosticEvent -Path $logPath -Component agent -Stage health -Status failed -ReasonCode 'Bearer fixture-value' -Attempt 1
} catch { $rejectedReason = $true }
if (-not $rejectedReason) { throw 'Diagnóstico aceitou motivo de falha não sanitizado.' }

for ($index = 0; $index -lt 1500; $index++) {
  Write-NodarisDiagnosticEvent -Path $logPath -Component agent -Stage backoff -Status completed -ReasonCode retry_delay_elapsed -Attempt 1 -DurationMs 5000 -TimeoutSeconds 45 -BackoffSeconds 5
}

$event = Get-Content -LiteralPath $logPath -TotalCount 1 | ConvertFrom-Json
$expectedProperties = @('schemaVersion', 'timestampUtc', 'durationMs', 'component', 'stage', 'attempt', 'timeoutSeconds', 'backoffSeconds', 'status', 'reasonCode')
if (($event.PSObject.Properties.Name -join ',') -ne ($expectedProperties -join ',')) { throw 'Schema do evento de diagnóstico divergiu.' }
$allLogs = (Get-ChildItem -LiteralPath $TestRoot -Filter 'startup-events.jsonl*' | Get-Content -Raw) -join "`n"
if ($allLogs -match '(?i)Bearer|fixture-value|authorization|runtime.?key|api.?key') { throw 'Diagnóstico contém marcador sensível de fixture.' }
if ($allLogs -notmatch 'process_start_failed|retry_scheduled|health_timeout') { throw 'Cenário de falha/retry não ficou registrado.' }
if ((Get-ChildItem -LiteralPath $TestRoot -Filter 'startup-events.jsonl*').Count -gt 4) { throw 'Rotação excedeu quatro arquivos.' }
if (-not (Test-Path -LiteralPath "$logPath.1")) { throw 'Rotação não preservou o arquivo anterior.' }

$acl = [IO.File]::GetAccessControl($logPath)
$allowedSids = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18')
$actualSids = @($acl.Access | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique)
if (($actualSids -join ',') -ne (($allowedSids | Sort-Object -Unique) -join ',')) { throw 'ACL do log não está restrita à conta atual e SYSTEM.' }
if (-not $acl.AreAccessRulesProtected) { throw 'ACL do log não está protegida contra herança.' }
$directoryAcl = [IO.Directory]::GetAccessControl($TestRoot)
$directorySids = @($directoryAcl.Access | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique)
if (($directorySids -join ',') -ne (($allowedSids | Sort-Object -Unique) -join ',')) { throw 'ACL do diretório não está restrita à conta atual e SYSTEM.' }
if (-not $directoryAcl.AreAccessRulesProtected) { throw 'ACL do diretório não está protegida contra herança.' }

'lifecycle-diagnostics-fixtures=PASS'
