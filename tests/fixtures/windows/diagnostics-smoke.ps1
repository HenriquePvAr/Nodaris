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
if (-not (Test-NodarisPrivateDirectoryAcl $TestRoot)) {
  $debugAcl = [IO.Directory]::GetAccessControl($TestRoot)
  $debugRules = @($debugAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
  $debugRights = @($debugRules | ForEach-Object { [int]$_.FileSystemRights } | Sort-Object -Unique)
  Write-Output ('fixture-acl protected={0}; rules={1}; rights={2}' -f $debugAcl.AreAccessRulesProtected, $debugRules.Count, ($debugRights -join ','))
  throw 'Validação de ACL privada do diretório falhou.'
}

$missingDirectoryPath = Join-Path $TestRoot 'missing\events.jsonl'
$missingDirectoryRejected = $false
try {
  Write-NodarisDiagnosticEvent -Path $missingDirectoryPath -Component supervisor -Stage bootstrap -Status started -ReasonCode script_entry -Attempt 0
} catch { $missingDirectoryRejected = $true }
if (-not $missingDirectoryRejected) { throw 'Diagnóstico criou arquivo quando o diretório protegido não existia.' }

$unprotectedDirectory = Join-Path $TestRoot 'unprotected'
New-Item -ItemType Directory -Path $unprotectedDirectory | Out-Null
if (Test-NodarisPrivateDirectoryAcl $unprotectedDirectory) { throw 'Diretório com ACL herdada foi aceito como privado.' }
$unprotectedRejected = $false
try {
  Write-NodarisDiagnosticEvent -Path (Join-Path $unprotectedDirectory 'events.jsonl') -Component supervisor -Stage bootstrap -Status started -ReasonCode script_entry -Attempt 0
} catch { $unprotectedRejected = $true }
if (-not $unprotectedRejected -or (Test-Path -LiteralPath (Join-Path $unprotectedDirectory 'events.jsonl'))) {
  throw 'Falha de ACL não bloqueou a gravação de telemetria.'
}

$unsafeFile = Join-Path $TestRoot 'unsafe-events.jsonl'
Set-Content -LiteralPath $unsafeFile -Value 'fixture'
$unsafeAcl = [IO.File]::GetAccessControl($unsafeFile)
$everyoneSid = [Security.Principal.SecurityIdentifier]::new('S-1-1-0')
$unsafeAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($everyoneSid, 'Read', 'Allow'))
[IO.File]::SetAccessControl($unsafeFile, $unsafeAcl)
if (Test-NodarisPrivateFileAcl $unsafeFile) { throw 'Arquivo com ACL ampla foi aceito como privado.' }
$unsafeFileRejected = $false
try {
  Write-NodarisDiagnosticEvent -Path $unsafeFile -Component supervisor -Stage bootstrap -Status started -ReasonCode script_entry -Attempt 0
} catch { $unsafeFileRejected = $true }
if (-not $unsafeFileRejected) { throw 'Arquivo de telemetria com ACL ampla foi alterado.' }
Remove-Item -LiteralPath $unsafeFile -Force

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
$startupFailuresOutput = @(Invoke-NodarisStartupPolicy -Name gateway -MaxRetries 5 `
  -StopAction { } `
  -StartAction { throw 'NODARIS_PORT_IN_USE' } `
  -HealthAction { $true } `
  -BackoffAction { param($seconds) $startupDelays.Add([int]$seconds) | Out-Null } `
  -EventAction { $true } -FailureReasonAction { 'health_transport_error' } -StopRequestedAction { $false })
if ($startupFailuresOutput.Count -ne 1 -or $startupFailuresOutput[0].status -ne 'circuit_open' -or $startupFailuresOutput[0].retryCount -ne 5 -or ($startupDelays -join ',') -ne '5,15,30,60,120') {
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
$failureRecoveryOutput = @(Invoke-NodarisRecoveryPolicy -Name gateway -ExistingRetries 0 -MaxRetries 5 `
  -StopAction { } `
  -StartAction { $script:failureStarts++ } `
  -HealthAction { return $false } `
  -BackoffAction { param($seconds) $delays.Add([int]$seconds) | Out-Null } `
  -EventAction { param($stage,$status,$reason,$attempt,$delay) $failureEvents.Add("$stage/$status/$reason") | Out-Null; $true } `
  -FailureReasonAction { 'health_transport_error' } `
  -StopRequestedAction { $false })
if ($failureRecoveryOutput.Count -ne 1 -or $failureRecoveryOutput[0].status -ne 'circuit_open' -or $failureRecoveryOutput[0].retryCount -ne 5 -or $failureStarts -ne 5) {
  throw 'Circuit breaker não abriu após o limite configurado.'
}

# Carrega a implementação real de Wait-ServiceHealth sem executar o corpo do supervisor.
$supervisorPath = Join-Path $repoRoot 'scripts\windows\supervisor.ps1'
$parseTokens = $null
$parseErrors = $null
$supervisorAst = [Management.Automation.Language.Parser]::ParseFile($supervisorPath, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Supervisor inválido durante a extração isolada da função de health.' }
$waitFunction = $supervisorAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Wait-ServiceHealth' }, $true)
if ($null -eq $waitFunction) { throw 'Wait-ServiceHealth não foi encontrada para teste isolado.' }
Invoke-Expression $waitFunction.Extent.Text
$script:diagnosticsFile = Join-Path $TestRoot 'mock-diagnostics.jsonl'
$script:activeAttempt = 1
$script:children = @{ agent = $null }
$script:stopFile = Join-Path $TestRoot 'stop-not-requested'
$script:lastAgentHealthReason = 'health_transport_error'
$originalWriter = (Get-Command Write-NodarisDiagnosticEvent -CommandType Function).ScriptBlock
$script:mockWriterFails = $false
function Write-NodarisDiagnosticEvent {
  param([string]$Path, [string]$Component, [string]$Stage, [string]$Status, [string]$ReasonCode, [int]$Attempt, [long]$DurationMs, [int]$TimeoutSeconds, [int]$BackoffSeconds, [string]$TimestampUtc)
  if ($script:mockWriterFails) { throw 'fixture log failure' }
  return $true
}
function Start-Sleep { }
$diagnosticPipeline = @(Write-Diagnostic agent health started none 1)
if ($diagnosticPipeline.Count -ne 0) { throw 'Write-Diagnostic contaminou o pipeline com saída.' }
$falseHealthOutput = @(Wait-ServiceHealth -Name agent -Condition { $false } -TimeoutSeconds 1)
if ($falseHealthOutput.Count -ne 1 -or $falseHealthOutput[0] -isnot [bool] -or $falseHealthOutput[0] -ne $false) {
  throw 'Wait-ServiceHealth não retornou exatamente um booleano falso quando health falhou e o log teve sucesso.'
}
$script:mockWriterFails = $true
$failedLogHealthOutput = @(Wait-ServiceHealth -Name agent -Condition { $false } -TimeoutSeconds 1)
if ($failedLogHealthOutput.Count -ne 1 -or $failedLogHealthOutput[0] -isnot [bool] -or $failedLogHealthOutput[0] -ne $false) {
  throw 'Falha de gravação do log alterou o resultado falso do health.'
}
Set-Item Function:Write-NodarisDiagnosticEvent $originalWriter
$script:mockWriterFails = $false

$startupRetryStarts = 0
$startupRetryDelays = [System.Collections.Generic.List[int]]::new()
$startupRetryOutput = @(Invoke-NodarisStartupPolicy -Name agent -MaxRetries 2 `
  -StopAction { } `
  -StartAction { $script:startupRetryStarts++ } `
  -HealthAction { $script:startupRetryStarts -ge 3 } `
  -BackoffAction { param($seconds) $startupRetryDelays.Add([int]$seconds) | Out-Null } `
  -EventAction { $true } -FailureReasonAction { 'health_transport_error' } -StopRequestedAction { $false })
if ($startupRetryOutput.Count -ne 1 -or $startupRetryOutput[0].status -ne 'healthy' -or $startupRetryOutput[0].retryCount -ne 2 -or $startupRetryStarts -ne 3 -or ($startupRetryDelays -join ',') -ne '5,15') {
  throw 'Callback de evento alterou a saída ou os retries da política de startup.'
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
$invalidTimestampRejected = $false
try {
  Write-NodarisDiagnosticEvent -Path $logPath -Component supervisor -Stage bootstrap -Status started -ReasonCode script_entry -Attempt 0 -TimestampUtc 'timestamp-invalido'
} catch { $invalidTimestampRejected = $true }
if (-not $invalidTimestampRejected) { throw 'Diagnóstico aceitou timestamp fora do formato UTC.' }
$durationEvent = Get-Content -LiteralPath $logPath -TotalCount 1 | ConvertFrom-Json
if ($durationEvent.durationMs -ne 45000) { throw 'Duração medida não foi preservada no evento.' }

$orderedPath = Join-Path $TestRoot 'timestamp-order.jsonl'
Write-NodarisDiagnosticEvent -Path $orderedPath -Component supervisor -Stage bootstrap -Status started -ReasonCode script_entry -Attempt 0 -TimestampUtc '2026-10-14T12:00:02.000Z'
Write-NodarisDiagnosticEvent -Path $orderedPath -Component supervisor -Stage bootstrap -Status healthy -ReasonCode project_path_resolve_completed -Attempt 0 -TimestampUtc '2026-10-14T12:00:01.000Z'
$orderedEvents = @(Get-Content -LiteralPath $orderedPath | ForEach-Object { $_ | ConvertFrom-Json })
if ($orderedEvents.Count -ne 2 -or $orderedEvents[0].timestampUtc -notmatch '12:00:02' -or $orderedEvents[1].timestampUtc -notmatch '12:00:01') {
  throw 'Diagnóstico não preservou timestamps fora de ordem para correlação posterior.'
}

for ($index = 0; $index -lt 1500; $index++) {
  Write-NodarisDiagnosticEvent -Path $logPath -Component agent -Stage backoff -Status completed -ReasonCode retry_delay_elapsed -Attempt 1 -DurationMs 5000 -TimeoutSeconds 45 -BackoffSeconds 5
}

$event = Get-Content -LiteralPath $logPath -TotalCount 1 | ConvertFrom-Json
$expectedProperties = @('schemaVersion', 'timestampUtc', 'durationMs', 'component', 'stage', 'attempt', 'timeoutSeconds', 'backoffSeconds', 'status', 'reasonCode')
if (($event.PSObject.Properties.Name -join ',') -ne ($expectedProperties -join ',')) { throw 'Schema do evento de diagnóstico divergiu.' }
$allLogs = (Get-ChildItem -LiteralPath $TestRoot -Filter 'startup-events.jsonl*' | Get-Content -Raw) -join "`n"
if ($allLogs -match '(?i)Bearer|fixture-value|authorization|runtime.?key|api.?key') { throw 'Diagnóstico contém marcador sensível de fixture.' }
if ($allLogs -match [regex]::Escape($TestRoot) -or $allLogs -match [regex]::Escape($env:USERNAME)) { throw 'Diagnóstico contém caminho pessoal ou nome de usuário.' }
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
