param([Parameter(Mandatory = $true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $repoRoot 'scripts\windows\diagnostics.ps1')
. (Join-Path $repoRoot 'scripts\windows\lifecycle.ps1')

function Assert-Fixture([bool]$Condition, [string]$Name) {
  if (-not $Condition) { throw "Fixture failed: $Name" }
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw 'Fixture output directory is missing.' }
Set-NodarisPrivateDirectoryAcl $OutputDirectory
if (-not (Test-NodarisPrivateDirectoryAcl $OutputDirectory)) { throw 'Fixture directory ACL is not private.' }
$script:fixtureNames = @('tunnel', 'gateway', 'agent')
$script:stopFailures = @()
$script:unconfirmedNames = @()
$script:diagnosticFails = $false
$script:persistFails = $false
$script:timeline = [Collections.Generic.List[string]]::new()
$script:attemptedStops = [Collections.Generic.List[string]]::new()
$script:events = [Collections.Generic.List[string]]::new()
$script:failureStatuses = @{}
$script:releaseCount = 0
$script:persistedStatus = $null
$script:statePath = Join-Path $OutputDirectory 'fixture-state.json'
$script:eventPath = Join-Path $OutputDirectory 'fixture-events.jsonl'
$script:diagnosticsFile = $script:eventPath
$script:rawSentinel = 'C:\private\fixture; Bearer fixture-secret; S-1-5-21-111-222-333-1001; commandline-secret'

$stopAction = {
  param($name)
  $script:attemptedStops.Add([string]$name) | Out-Null
  $script:timeline.Add("stop:$name") | Out-Null
  if ($script:stopFailures -contains $name) { throw $script:rawSentinel }
}
$isStoppedAction = {
  param($name)
  return [bool]($script:unconfirmedNames -notcontains $name)
}
$failureAction = {
  param($name, $reasonCode)
  $prior = [string]$script:failureStatuses[$name]
  if ($prior -ne 'identity_unconfirmed_manual_intervention') {
    $script:failureStatuses[$name] = 'cleanup_failed_manual_intervention'
  }
}
$persistAction = {
  param($status)
  $script:timeline.Add('persist') | Out-Null
  if ($script:persistFails) { throw $script:rawSentinel }
  $script:persistedStatus = $status
  [IO.File]::WriteAllText($script:statePath, (ConvertTo-Json -InputObject @{ status = $status; services = $script:failureStatuses } -Depth 5))
}
$diagnosticAction = {
  param($component, $reasonCode)
  if ($script:diagnosticFails) { throw $script:rawSentinel }
  Write-NodarisDiagnosticEvent -Path $script:eventPath -Component $component -Stage finalization `
    -Status failed -ReasonCode $reasonCode -Attempt 0
  $line = [IO.File]::ReadAllText($script:eventPath)
  $script:events.Add($line) | Out-Null
}
$releaseAction = {
  $script:timeline.Add('release') | Out-Null
  $script:releaseCount++
}

function Reset-Scenario {
  $script:stopFailures = @()
  $script:unconfirmedNames = @()
  $script:diagnosticFails = $false
  $script:persistFails = $false
  $script:timeline.Clear()
  $script:attemptedStops.Clear()
  $script:events.Clear()
  $script:failureStatuses = @{}
  $script:releaseCount = 0
  $script:persistedStatus = $null
  Remove-Item -LiteralPath $script:statePath,$script:eventPath -Force -ErrorAction SilentlyContinue
}

function Invoke-Scenario([string]$RequestedStatus = 'stopped') {
  return Invoke-NodarisFinalization -Names $script:fixtureNames -RequestedStatus $RequestedStatus `
    -StopAction $stopAction -IsStoppedAction $isStoppedAction -FailureAction $failureAction `
    -PersistAction $persistAction -DiagnosticAction $diagnosticAction -ReleaseAction $releaseAction
}

# Encerramento completo e ordem: cleanup de todos, persistência, mutex.
Reset-Scenario
$normalPipeline = @(Invoke-Scenario)
Assert-Fixture ($normalPipeline.Count -eq 1 -and $normalPipeline[0].status -eq 'stopped') 'normal shutdown returns one result'
$normalState = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
Assert-Fixture ($normalPipeline[0].persisted -and $normalPipeline[0].mutexReleased -and $normalState.status -eq 'stopped') 'normal shutdown persisted'
Assert-Fixture (($script:attemptedStops -join ',') -eq 'tunnel,gateway,agent') 'normal cleanup order'
Assert-Fixture (($script:timeline[-2..-1] -join ',') -eq 'persist,release') 'persist follows cleanup and precedes release'

Reset-Scenario
$startupError = Invoke-Scenario error
$errorState = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
Assert-Fixture ($startupError.status -eq 'error' -and $errorState.status -eq 'error') 'startup failure remains error after complete cleanup'
Reset-Scenario
$script:unconfirmedNames = @('agent')
$partialStartupError = Invoke-Scenario error
Assert-Fixture ($partialStartupError.status -eq 'degraded') 'startup error with unconfirmed child is degraded'

# O motivo terminal circuit breaker prevalece mesmo após cleanup completo.
Reset-Scenario
$breakerComplete = Invoke-Scenario degraded
$breakerCompleteState = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
Assert-Fixture ($breakerComplete.status -eq 'degraded' -and $breakerCompleteState.status -eq 'degraded') `
  'circuit breaker remains degraded after complete cleanup'

Reset-Scenario
$script:stopFailures = @('gateway')
$script:unconfirmedNames = @('gateway')
$breakerPartial = Invoke-Scenario degraded
Assert-Fixture ($breakerPartial.status -eq 'degraded' -and $breakerPartial.persisted -and $breakerPartial.cleanupFailureCount -eq 1) `
  'circuit breaker remains degraded after partial cleanup'

Reset-Scenario
$startupBreaker = Invoke-Scenario degraded
$startupBreakerState = Get-Content -LiteralPath $script:statePath -Raw | ConvertFrom-Json
Assert-Fixture ($startupBreaker.status -eq 'degraded' -and $startupBreakerState.status -eq 'degraded') `
  'startup failure with circuit breaker remains degraded'

# Falhas no primeiro, segundo e em múltiplos filhos não interrompem os demais.
foreach ($failureSet in @(@('tunnel'), @('gateway'), @('tunnel','agent'))) {
  Reset-Scenario
  $script:stopFailures = $failureSet
  $script:unconfirmedNames = $failureSet
  $result = Invoke-Scenario
  Assert-Fixture ($result.status -eq 'degraded' -and $result.persisted -and $result.cleanupFailureCount -eq $failureSet.Count) `
    ("partial cleanup; state={0}; persisted={1}; failures={2}; expected={3}" -f $result.status,$result.persisted,$result.cleanupFailureCount,$failureSet.Count)
  Assert-Fixture (($script:attemptedStops -join ',') -eq 'tunnel,gateway,agent') 'cleanup continues after failures'
  Assert-Fixture ($script:releaseCount -eq 1) 'mutex release after cleanup failure'
}

# Estado manual por identidade inconclusiva nunca vira stopped por solicitação.
Reset-Scenario
$script:failureStatuses.tunnel = 'identity_unconfirmed_manual_intervention'
$script:unconfirmedNames = @('tunnel')
$manual = Invoke-Scenario
Assert-Fixture ($manual.status -eq 'degraded' -and $manual.unconfirmedCount -eq 1) 'unconfirmed identity remains degraded'
Assert-Fixture ($script:failureStatuses.tunnel -eq 'identity_unconfirmed_manual_intervention') 'manual intervention status preserved'

# PID reutilizado é bloqueado pela mesma proteção de identidade antes do stop.
$stopInvoked = 0
$identityExpected = @{ processId=41001; startTimeUtcTicks=638000000000000000L; executablePathHash=('a'.PadRight(64,'a')); commandLineHash=('b'.PadRight(64,'b')); userSidHash=('c'.PadRight(64,'c')); sessionId=1; parentProcessId=41000 }
$identityReused = @{} + $identityExpected
$identityReused.startTimeUtcTicks++
$pidReuseBlocked = $false
try {
  Stop-NodarisVerifiedProcess -Process ([pscustomobject]@{ Id=41001 }) -ExpectedIdentity $identityExpected `
    -IdentityReader { param($id) $identityReused } -StopAction { $script:stopInvoked++ }
} catch { $pidReuseBlocked = $_.Exception.Message -eq 'NODARIS_PROCESS_IDENTITY_MISMATCH' }
Assert-Fixture ($pidReuseBlocked -and $stopInvoked -eq 0) 'PID reuse never invokes stop action'
Assert-Fixture (Test-NodarisComponentStopped -ProcessStatus absent -PortStatus clear) 'absent process and clear port are stopped'
Assert-Fixture (Test-NodarisComponentStopped -ProcessStatus exited -PortStatus clear) 'exited process and clear port are stopped'
Assert-Fixture (-not (Test-NodarisComponentStopped -ProcessStatus running -PortStatus clear)) 'running process is not stopped'
Assert-Fixture (-not (Test-NodarisComponentStopped -ProcessStatus inconclusive -PortStatus clear)) 'inconclusive process is not stopped'
Assert-Fixture (-not (Test-NodarisComponentStopped -ProcessStatus exited -PortStatus inconclusive)) 'inconclusive listener is not stopped'
Assert-Fixture (-not (Test-NodarisComponentStopped -ProcessStatus absent -PortStatus busy)) 'busy listener is not stopped'
Assert-Fixture (-not (Test-NodarisComponentStopped -ProcessStatus exited -PortStatus clear -ManualInterventionRequired $true)) 'manual intervention is never cleared implicitly'

# Falha de diagnóstico não suprime persistência; exceção de cleanup vem antes da gravação.
Reset-Scenario
$script:stopFailures = @('gateway')
$script:unconfirmedNames = @('gateway')
$script:diagnosticFails = $true
$script:failureStatuses.gateway = 'identity_unconfirmed_manual_intervention'
$diagnosticFailure = Invoke-Scenario
Assert-Fixture ($diagnosticFailure.persisted -and $diagnosticFailure.diagnosticFailureCount -gt 0) 'diagnostic failure does not block state persistence'
Assert-Fixture ($script:timeline.IndexOf('persist') -gt $script:timeline.FindIndex({ param($item) $item -eq 'stop:gateway' })) 'state persistence follows cleanup exception'
Assert-Fixture ($script:failureStatuses.gateway -eq 'identity_unconfirmed_manual_intervention') 'manual status survives cleanup exception'

# A snapshot real compartilhado preserva PID, identidade, contador e status manual.
$identityEvidence = [pscustomobject]@{ processId=41002; startTimeUtcTicks=638000000000000000L; executablePathHash=('d'.PadRight(64,'d')); commandLineHash=('e'.PadRight(64,'e')); userSidHash=('f'.PadRight(64,'f')); sessionId=1; parentProcessId=41000 }
$snapshot = Get-NodarisServiceSnapshot -Names @('agent','gateway','tunnel') `
  -Children @{ agent=$null; gateway=$null; tunnel=$null } -Identities @{} `
  -FinalizationEvidence @{ agent=@{ processId=41002; identity=$identityEvidence } } `
  -Statuses @{ agent='identity_unconfirmed_manual_intervention'; gateway='stopped'; tunnel='stopped' } `
  -RestartCounts @{ agent=2; gateway=1; tunnel=0 }
Assert-Fixture ($snapshot.agent.pid -eq 41002 -and $snapshot.agent.identity.commandLineHash -eq ('e'.PadRight(64,'e'))) 'final snapshot keeps observed PID and confirmed identity'
Assert-Fixture ($snapshot.agent.status -eq 'identity_unconfirmed_manual_intervention' -and $snapshot.agent.restartCount -eq 2) 'final snapshot keeps manual status and retry count'
$manualManagerState = [pscustomobject]@{
  supervisorPid = 41000
  services = [pscustomobject]@{
    agent = [pscustomobject]@{ status = 'identity_unconfirmed_manual_intervention' }
    gateway = [pscustomobject]@{ status = 'stopped' }
    tunnel = [pscustomobject]@{ status = 'stopped' }
  }
}
$manualDisposition = Get-NodarisSupervisorDisposition -State $manualManagerState -StateReadStatus valid `
  -ObservedIdentity $null -IdentityQueryStatus absent -MutexStatus free -PortsStatus clear `
  -IdentityMatches $false -SupervisorCandidate $false
Assert-Fixture ($manualDisposition -eq 'identity_inconclusive') 'manager blocks start while child identity requires intervention'
$failedCleanupState = [pscustomobject]@{
  supervisorPid = 41000
  services = [pscustomobject]@{ agent = [pscustomobject]@{ status = 'cleanup_failed_manual_intervention' } }
}
$failedCleanupDisposition = Get-NodarisSupervisorDisposition -State $failedCleanupState -StateReadStatus valid `
  -ObservedIdentity $null -IdentityQueryStatus absent -MutexStatus free -PortsStatus clear `
  -IdentityMatches $false -SupervisorCandidate $false
Assert-Fixture ($failedCleanupDisposition -eq 'identity_inconclusive') 'manager blocks start after partial cleanup'

# Falha de state.json registra evento sanitizado apenas via callback autorizado e libera mutex real.
Reset-Scenario
$script:persistFails = $true
$realMutexName = 'LocalNodaris-Fixture-' + [guid]::NewGuid().ToString('N')
$realMutex = [Threading.Mutex]::new($false, $realMutexName)
Assert-Fixture ($realMutex.WaitOne(0)) 'fixture mutex acquired'
$realRelease = { try { $realMutex.ReleaseMutex() } finally { $realMutex.Dispose() } }
$persistFailure = Invoke-NodarisFinalization -Names $script:fixtureNames -RequestedStatus stopped `
  -StopAction $stopAction -IsStoppedAction $isStoppedAction -FailureAction $failureAction `
  -PersistAction $persistAction -DiagnosticAction $diagnosticAction -ReleaseAction $realRelease
Assert-Fixture (-not $persistFailure.persisted -and $persistFailure.mutexReleased) 'persistence failure is reported and releases mutex'
Assert-Fixture ($persistFailure.diagnosticFailureCount -eq 0) 'state write failure diagnostic was accepted'
$eventRecords = @(Get-Content -LiteralPath $script:eventPath | ForEach-Object { ConvertFrom-Json -InputObject $_ })
$stateWriteEvents = @($eventRecords | Where-Object { $_.reasonCode -eq 'state_write_failed' })
Assert-Fixture ($stateWriteEvents.Count -eq 1) 'state write failure event is classified'
Assert-Fixture (Test-NodarisPrivateFileAcl $script:eventPath) 'fallback event retains private ACL'
$probeMutex = [Threading.Mutex]::new($false, $realMutexName)
try { Assert-Fixture ($probeMutex.WaitOne(0)) 'real fixture mutex is released'; $probeMutex.ReleaseMutex() } finally { $probeMutex.Dispose() }

# Falha simultânea de cleanup e persistência também libera mutex e não vaza exceções.
Reset-Scenario
$script:stopFailures = @('tunnel')
$script:unconfirmedNames = @('tunnel')
$script:persistFails = $true
$combinedMutexName = 'LocalNodaris-Fixture-' + [guid]::NewGuid().ToString('N')
$combinedMutex = [Threading.Mutex]::new($false, $combinedMutexName)
Assert-Fixture ($combinedMutex.WaitOne(0)) 'combined failure fixture mutex acquired'
$combinedRelease = { try { $combinedMutex.ReleaseMutex() } finally { $combinedMutex.Dispose() } }
$combined = Invoke-NodarisFinalization -Names $script:fixtureNames -RequestedStatus stopped `
  -StopAction $stopAction -IsStoppedAction $isStoppedAction -FailureAction $failureAction `
  -PersistAction $persistAction -DiagnosticAction $diagnosticAction -ReleaseAction $combinedRelease
Assert-Fixture ($combined.status -eq 'degraded' -and -not $combined.persisted -and $combined.mutexReleased) 'cleanup and persistence failures remain explicit'
$combinedProbe = [Threading.Mutex]::new($false, $combinedMutexName)
try { Assert-Fixture ($combinedProbe.WaitOne(0)) 'mutex is released after simultaneous failures'; $combinedProbe.ReleaseMutex() } finally { $combinedProbe.Dispose() }

$allArtifacts = @()
foreach ($path in @($script:statePath, $script:eventPath)) {
  if (Test-Path -LiteralPath $path) { $allArtifacts += [IO.File]::ReadAllText($path) }
}
$serializedResults = ConvertTo-Json -InputObject @($normalPipeline,$manual,$diagnosticFailure,$persistFailure,$combined) -Depth 6 -Compress
$observedText = ($allArtifacts -join "`n") + $serializedResults + ($script:events -join "`n")
Assert-Fixture (-not $observedText.Contains($script:rawSentinel) -and -not $observedText.Contains('Bearer') -and -not $observedText.Contains('S-1-5-21') -and -not $observedText.Contains('commandline-secret')) 'diagnostic outputs are sanitized'

'finalization-fixtures=PASS'
'cleanup-cases=normal,first-child,second-child,multiple,identity-unconfirmed,pid-reuse'
'persistence-cases=after-cleanup,diagnostic-failure,state-write-failure,combined-failure'
'terminal-state-cases=breaker-complete:degraded,breaker-partial:degraded,normal-complete:stopped,startup-error-complete:error,startup-error-breaker:degraded'
'invariants=manual-state-preserved,no-false-stopped,identity-snapshot-retained,manager-blocked,mutex-released,sanitized'
