param([Parameter(Mandatory = $true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $repoRoot 'scripts\windows\diagnostics.ps1')
. (Join-Path $repoRoot 'scripts\windows\lifecycle.ps1')

function Assert-Fixture([bool]$Condition, [string]$Name) {
  if (-not $Condition) { throw "Fixture failed: $Name" }
}

$fakeHash = 'a'.PadRight(64, 'a')
$fakeScriptHash = 'b'.PadRight(64, 'b')
$fakeSidHash = 'c'.PadRight(64, 'c')
$expected = @{
  processId = 41001; startTimeUtcTicks = 638000000000000000L; executablePathHash = $fakeHash
  commandLineHash = $fakeScriptHash; userSidHash = $fakeSidHash; sessionId = 2; parentProcessId = 40001
  scriptPathHash = $fakeScriptHash; expectedScriptMatches = $true; expectedExecutableMatches = $true
}
$observed = @{} + $expected
$current = @{ userSidHash = $fakeSidHash; sessionId = 2 }
$executable = Join-Path $PSHOME 'powershell.exe'
$scriptPath = Join-Path $repoRoot 'scripts\windows\supervisor.ps1'

$mockCommandLine = 'powershell.exe -File "' + $PSCommandPath + '"'
$successfulQuery = { param($id) [pscustomobject]@{ CommandLine = $mockCommandLine; ParentProcessId = 40001 } }.GetNewClosure()
$successfulOwner = { param($processRecord) [pscustomobject]@{ ReturnValue = 0; Sid = 'S-1-5-21-111-222-333-1001' } }
$currentProcess = [Diagnostics.Process]::GetProcessById($PID)
try { $currentStartTicks = [long]$currentProcess.StartTime.ToUniversalTime().Ticks } finally { $currentProcess.Dispose() }
$queriedIdentity = Get-NodarisProcessIdentity -ProcessId $PID -ExpectedExecutablePath (Join-Path $PSHOME 'powershell.exe') `
  -ExpectedScriptPath $PSCommandPath -ExpectedStartTimeUtcTicks $currentStartTicks -ProcessQuery $successfulQuery -OwnerQuery $successfulOwner
Assert-Fixture ($queriedIdentity.expectedExecutableMatches -eq $true -and $queriedIdentity.expectedScriptMatches -eq $true) 'mocked CIM success'
$queriedJson = ConvertTo-Json -InputObject $queriedIdentity -Compress
Assert-Fixture (-not $queriedJson.Contains($PSCommandPath) -and -not $queriedJson.Contains('S-1-5-21-111-222-333-1001') -and -not $queriedJson.Contains($mockCommandLine)) 'CIM identity metadata sanitized'
$startMismatch = $false
try {
  Get-NodarisProcessIdentity -ProcessId $PID -ExpectedStartTimeUtcTicks ($currentStartTicks + 1) -ProcessQuery $successfulQuery -OwnerQuery $successfulOwner
} catch { $startMismatch = $_.Exception.Message -eq 'NODARIS_IDENTITY_UNCONFIRMED' }
Assert-Fixture $startMismatch 'spawn handle creation time rejects reused PID'
$missingIdentity = Get-NodarisProcessIdentity -ProcessId 999999 -ProcessQuery { param($id) $null } -OwnerQuery $successfulOwner
Assert-Fixture ($null -eq $missingIdentity) 'nonexistent process'
$denied = $false
try {
  Get-NodarisProcessIdentity -ProcessId $PID -ProcessQuery { param($id) throw [UnauthorizedAccessException]::new('fixture') } -OwnerQuery $successfulOwner
} catch { $denied = $_.Exception -is [UnauthorizedAccessException] }
Assert-Fixture $denied 'CIM access denied propagation'
$ownerDenied = $false
try {
  Get-NodarisProcessIdentity -ProcessId $PID -ProcessQuery $successfulQuery -OwnerQuery { param($record) throw [UnauthorizedAccessException]::new('fixture') }
} catch { $ownerDenied = $_.Exception -is [UnauthorizedAccessException] }
Assert-Fixture $ownerDenied 'GetOwnerSid access denied propagation'

Assert-Fixture (Test-NodarisProcessIdentity $expected $observed) 'identity exact match'
$contextExpected = @{} + $expected
$contextExpected.executablePathHash = Get-NodarisSha256 ([IO.Path]::GetFullPath($executable).ToLowerInvariant())
$contextExpected.scriptPathHash = Get-NodarisSha256 ([IO.Path]::GetFullPath($scriptPath).ToLowerInvariant())
$contextObserved = @{} + $contextExpected
$contextObserved.expectedExecutableMatches = $true
$contextObserved.expectedScriptMatches = $true
Assert-Fixture (Test-NodarisSupervisorContext -Expected $contextExpected -Observed $contextObserved -CurrentIdentity $current `
  -ExpectedExecutablePath $executable -ExpectedScriptPath $scriptPath -TaskUserSidHash $fakeSidHash) 'task user/session/install context'
$wrongExecutable = @{} + $contextObserved
$wrongExecutable.executablePathHash = $fakeHash
Assert-Fixture (-not (Test-NodarisSupervisorContext -Expected $contextExpected -Observed $wrongExecutable -CurrentIdentity $current `
  -ExpectedExecutablePath $executable -ExpectedScriptPath $scriptPath -TaskUserSidHash $fakeSidHash)) 'unexpected executable rejected'
$wrongUser = @{} + $current
$wrongUser.userSidHash = $fakeHash
Assert-Fixture (-not (Test-NodarisSupervisorContext -Expected $contextExpected -Observed $contextObserved -CurrentIdentity $wrongUser `
  -ExpectedExecutablePath $executable -ExpectedScriptPath $scriptPath -TaskUserSidHash $fakeSidHash)) 'different user rejected'
$wrongSession = @{} + $current
$wrongSession.sessionId = 9
Assert-Fixture (-not (Test-NodarisSupervisorContext -Expected $contextExpected -Observed $contextObserved -CurrentIdentity $wrongSession `
  -ExpectedExecutablePath $executable -ExpectedScriptPath $scriptPath -TaskUserSidHash $fakeSidHash)) 'different session rejected'

$legacy = [pscustomobject]@{ status = 'running'; supervisorPid = 41001 }
$disposition = Get-NodarisSupervisorDisposition -State $legacy -StateReadStatus valid -ObservedIdentity $observed `
  -IdentityQueryStatus observed -MutexStatus busy -PortsStatus busy -IdentityMatches $true -SupervisorCandidate $true
Assert-Fixture ($disposition -eq 'identity_inconclusive') 'legacy state is not identity proof'

$state = [pscustomobject]@{ status = 'running'; supervisorPid = 41001; supervisorIdentity = [pscustomobject]$expected }
$disposition = Get-NodarisSupervisorDisposition -State $state -StateReadStatus valid -ObservedIdentity $observed `
  -IdentityQueryStatus observed -MutexStatus busy -PortsStatus busy -IdentityMatches $true -SupervisorCandidate $true
Assert-Fixture ($disposition -eq 'confirmed_active') 'confirmed active supervisor'

$reused = @{} + $expected
$reused.startTimeUtcTicks++
Assert-Fixture (-not (Test-NodarisProcessIdentity $expected $reused)) 'same executable with changed creation time'
$disposition = Get-NodarisSupervisorDisposition -State $state -StateReadStatus valid -ObservedIdentity $reused `
  -IdentityQueryStatus observed -MutexStatus free -PortsStatus clear -IdentityMatches $false -SupervisorCandidate $true
Assert-Fixture ($disposition -eq 'pid_reused_recoverable') 'reused PID recoverable when resources clear'

$disposition = Get-NodarisSupervisorDisposition -State $state -StateReadStatus valid -ObservedIdentity $reused `
  -IdentityQueryStatus observed -MutexStatus busy -PortsStatus clear -IdentityMatches $false -SupervisorCandidate $true
Assert-Fixture ($disposition -eq 'identity_inconclusive') 'reused PID with busy mutex fails closed'
$disposition = Get-NodarisSupervisorDisposition -State $null -StateReadStatus corrupt -ObservedIdentity $null `
  -IdentityQueryStatus absent -MutexStatus free -PortsStatus clear -IdentityMatches $false -SupervisorCandidate $false
Assert-Fixture ($disposition -eq 'stopped') 'corrupt state with clear independent resources'
$disposition = Get-NodarisSupervisorDisposition -State $null -StateReadStatus missing -ObservedIdentity $null `
  -IdentityQueryStatus absent -MutexStatus busy -PortsStatus clear -IdentityMatches $false -SupervisorCandidate $false
Assert-Fixture ($disposition -eq 'identity_inconclusive') 'missing state with busy mutex'
$disposition = Get-NodarisSupervisorDisposition -State $state -StateReadStatus valid -ObservedIdentity $null `
  -IdentityQueryStatus inconclusive -MutexStatus free -PortsStatus clear -IdentityMatches $false -SupervisorCandidate $false
Assert-Fixture ($disposition -eq 'identity_inconclusive') 'identity query failure'
$disposition = Get-NodarisSupervisorDisposition -State $state -StateReadStatus valid -ObservedIdentity $reused `
  -IdentityQueryStatus observed -MutexStatus free -PortsStatus busy -IdentityMatches $false -SupervisorCandidate $false
Assert-Fixture ($disposition -eq 'identity_inconclusive') 'unknown listener blocks recovery'

$stopCalls = 0
$fakeProcess = [pscustomobject]@{ Id = 41001 }
$stopReader = { param($id) $observed }.GetNewClosure()
$stopAction = { param($process) $script:stopCalls++ }
try {
  Stop-NodarisVerifiedProcess -Process $fakeProcess -ExpectedIdentity $expected -IdentityReader { param($id) $reused } -StopAction $stopAction
  throw 'Expected identity mismatch was not rejected.'
} catch {
  Assert-Fixture ($_.Exception.Message -eq 'NODARIS_PROCESS_IDENTITY_MISMATCH') 'stop rejects reused PID'
}
Assert-Fixture ($stopCalls -eq 0) 'reused PID stop action not invoked'
Stop-NodarisVerifiedProcess -Process $fakeProcess -ExpectedIdentity $expected -IdentityReader $stopReader -StopAction $stopAction
Assert-Fixture ($stopCalls -eq 1) 'verified stop action invoked once'
try {
  Stop-NodarisVerifiedProcess -Process $fakeProcess -ExpectedIdentity $expected -IdentityReader { throw 'sentinel' } -StopAction $stopAction
  throw 'Expected identity query failure was not rejected.'
} catch {
  Assert-Fixture ($_.Exception.Message -eq 'NODARIS_PROCESS_IDENTITY_UNCONFIRMED') 'identity query exception fails closed'
}
Assert-Fixture ($stopCalls -eq 1) 'unknown identity stop action not invoked'

$spawnCount = 0
$stopCount = 0
$backoffCount = 0
$registeredFakeChild = $null
$failureEventCodes = [Collections.Generic.List[string]]::new()
$policyEvent = { param($stage,$status,$reason,$attempt,$delay) $failureEventCodes.Add([string]$reason) }
$failedAfterSpawn = Invoke-NodarisStartupPolicy -Name agent -MaxRetries 3 -StopAction { $script:stopCount++ } `
  -StartAction { $script:spawnCount++; $script:registeredFakeChild = [pscustomobject]@{ Id = 41002 }; throw 'NODARIS_CHILD_IDENTITY_UNCONFIRMED' } `
  -HealthAction { $true } -BackoffAction { param($seconds) $script:backoffCount++; $true } -EventAction $policyEvent `
  -FailureReasonAction { 'health_timeout' } -StopRequestedAction { $false }
Assert-Fixture ($failedAfterSpawn.status -eq 'circuit_open' -and $spawnCount -eq 1 -and $null -ne $registeredFakeChild) 'post-spawn child retained as evidence'
Assert-Fixture ($stopCount -eq 0 -and $backoffCount -eq 0) 'post-spawn identity failure blocks stop and retries'
Assert-Fixture ($failureEventCodes -contains 'circuit_open') 'post-spawn failure circuit telemetry'

$preSpawnCalls = 0
$preSpawnBackoffs = 0
$recoveredBeforeSpawn = Invoke-NodarisStartupPolicy -Name gateway -MaxRetries 1 -StopAction { } `
  -StartAction { $script:preSpawnCalls++; if ($script:preSpawnCalls -eq 1) { throw 'NODARIS_PROCESS_START_FAILED' } } `
  -HealthAction { $true } -BackoffAction { param($seconds) $script:preSpawnBackoffs++; $true } -EventAction { } `
  -FailureReasonAction { 'health_timeout' } -StopRequestedAction { $false }
Assert-Fixture ($recoveredBeforeSpawn.status -eq 'healthy' -and $preSpawnCalls -eq 2 -and $preSpawnBackoffs -eq 1) 'pre-spawn failure remains retryable'

$recoverySpawns = 0
$recoveryBackoffs = 0
$recoveryFailure = Invoke-NodarisRecoveryPolicy -Name tunnel -ExistingRetries 0 -MaxRetries 3 -StopAction { } `
  -StartAction { $script:recoverySpawns++; throw 'NODARIS_CHILD_IDENTITY_UNCONFIRMED' } -HealthAction { $true } `
  -BackoffAction { param($seconds) $script:recoveryBackoffs++; $true } -EventAction { } `
  -FailureReasonAction { 'health_timeout' } -StopRequestedAction { $false }
Assert-Fixture ($recoveryFailure.status -eq 'circuit_open' -and $recoverySpawns -eq 1 -and $recoveryBackoffs -eq 1) 'recovery identity failure blocks retry accumulation'

$serialized = ConvertTo-Json -InputObject $expected -Compress
Assert-Fixture (-not $serialized.Contains($scriptPath) -and -not $serialized.Contains('S-1-5-21')) 'identity metadata contains only hashes'
Assert-Fixture ($null -eq $expected.PSObject.Properties['commandLine']) 'raw command line not persisted'

'process-identity-fixtures=PASS'
'provider-cases=success,access-denied,missing-process'
'identity-cases=active,reused,unexpected,session,legacy,missing,corrupt,mutex,ports,query-failure'
'safe-stop=mismatch-blocked,match-allowed,query-failure-blocked'
'post-spawn=single-launch,no-retry,no-unverified-stop'
'pre-spawn=retryable'
'metadata=sanitized'
