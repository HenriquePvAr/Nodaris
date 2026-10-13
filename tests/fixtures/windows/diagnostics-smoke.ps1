param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$TestRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $repoRoot 'scripts\windows\diagnostics.ps1')
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
Set-NodarisPrivateDirectoryAcl $TestRoot

$expectedBackoff = @(5, 15, 30, 60, 120)
for ($index = 0; $index -lt $expectedBackoff.Count; $index++) {
  if ((Get-NodarisBackoffSeconds $index) -ne $expectedBackoff[$index]) { throw 'Backoff fixture divergiu da política.' }
}
$backoffRejected = $false
try { Get-NodarisBackoffSeconds 5 | Out-Null } catch { $backoffRejected = $true }
if (-not $backoffRejected) { throw 'Backoff aceitou tentativa além do limite.' }

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

'diagnostics-fixtures=PASS'
