<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

function Get-NodarisSha256([string]$Value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
  } finally { $sha.Dispose() }
}

function Get-NodarisProcessIdentity {
  param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [string]$ExpectedExecutablePath,
    [string]$ExpectedScriptPath,
    [long]$ExpectedStartTimeUtcTicks = 0,
    [scriptblock]$ProcessQuery = { param($id) Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $id" -ErrorAction Stop },
    [scriptblock]$OwnerQuery = { param($processRecord) Invoke-CimMethod -InputObject $processRecord -MethodName GetOwnerSid -ErrorAction Stop }
  )

  $record = & $ProcessQuery $ProcessId
  if ($null -eq $record) { return $null }
  $owner = & $OwnerQuery $record
  if ($null -eq $owner -or [int]$owner.ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace($owner.Sid)) {
    throw 'NODARIS_IDENTITY_UNCONFIRMED'
  }

  $process = [Diagnostics.Process]::GetProcessById($ProcessId)
  try {
    $process.Refresh()
    $startTimeUtcTicks = [long]$process.StartTime.ToUniversalTime().Ticks
    if ($ExpectedStartTimeUtcTicks -gt 0 -and $startTimeUtcTicks -ne $ExpectedStartTimeUtcTicks) {
      throw 'NODARIS_IDENTITY_UNCONFIRMED'
    }
    $imagePath = [IO.Path]::GetFullPath($process.MainModule.FileName)
    $commandLine = [string]$record.CommandLine
    if ([string]::IsNullOrWhiteSpace($commandLine)) { throw 'NODARIS_IDENTITY_UNCONFIRMED' }
    $scriptMatches = $null
    $scriptPathHash = $null
    if (-not [string]::IsNullOrWhiteSpace($ExpectedScriptPath)) {
      $canonicalScript = [IO.Path]::GetFullPath($ExpectedScriptPath)
      $scriptMatches = $commandLine.IndexOf($canonicalScript, [StringComparison]::OrdinalIgnoreCase) -ge 0
      $scriptPathHash = Get-NodarisSha256 $canonicalScript.ToLowerInvariant()
    }
    $executableMatches = $null
    if (-not [string]::IsNullOrWhiteSpace($ExpectedExecutablePath)) {
      $canonicalExecutable = [IO.Path]::GetFullPath($ExpectedExecutablePath)
      $executableMatches = $imagePath.Equals($canonicalExecutable, [StringComparison]::OrdinalIgnoreCase)
    }

    return @{
      processId = [int]$process.Id
      startTimeUtcTicks = $startTimeUtcTicks
      executablePathHash = Get-NodarisSha256 $imagePath.ToLowerInvariant()
      commandLineHash = Get-NodarisSha256 $commandLine
      userSidHash = Get-NodarisSha256 ([string]$owner.Sid).ToUpperInvariant()
      sessionId = [int]$process.SessionId
      parentProcessId = [int]$record.ParentProcessId
      scriptPathHash = $scriptPathHash
      expectedScriptMatches = $scriptMatches
      expectedExecutableMatches = $executableMatches
    }
  } finally { $process.Dispose() }
}

function Test-NodarisProcessIdentity($Expected, $Observed) {
  if ($null -eq $Expected -or $null -eq $Observed) { return $false }
  $required = @('processId', 'startTimeUtcTicks', 'executablePathHash', 'commandLineHash', 'userSidHash', 'sessionId', 'parentProcessId')
  foreach ($name in $required) {
    if ($null -eq $Expected.$name -or $null -eq $Observed.$name) { return $false }
    if ([string]$Expected.$name -cne [string]$Observed.$name) { return $false }
  }
  $expectedScriptHash = $Expected.PSObject.Properties['scriptPathHash']
  if ($null -eq $expectedScriptHash -and $Expected -is [System.Collections.IDictionary] -and $Expected.Contains('scriptPathHash')) {
    $expectedScriptHash = $true
  }
  if ($null -ne $expectedScriptHash -and [string]$Expected.scriptPathHash -cne [string]$Observed.scriptPathHash) { return $false }
  return $true
}

function Test-NodarisSupervisorContext {
  param(
    $Expected,
    $Observed,
    $CurrentIdentity,
    [string]$ExpectedExecutablePath,
    [string]$ExpectedScriptPath,
    [string]$TaskUserSidHash
  )
  if (-not (Test-NodarisProcessIdentity $Expected $Observed)) { return $false }
  if ($Observed.expectedExecutableMatches -ne $true -or $Observed.expectedScriptMatches -ne $true) { return $false }
  if ($Expected.executablePathHash -cne (Get-NodarisSha256 ([IO.Path]::GetFullPath($ExpectedExecutablePath).ToLowerInvariant()))) { return $false }
  if ($Expected.scriptPathHash -cne (Get-NodarisSha256 ([IO.Path]::GetFullPath($ExpectedScriptPath).ToLowerInvariant()))) { return $false }
  if ($Expected.userSidHash -cne $CurrentIdentity.userSidHash -or $Expected.userSidHash -cne $TaskUserSidHash) { return $false }
  if ([int]$Expected.sessionId -ne [int]$CurrentIdentity.sessionId) { return $false }
  return $true
}

function Get-NodarisSupervisorDisposition {
  param(
    $State,
    [ValidateSet('valid', 'missing', 'corrupt')][string]$StateReadStatus,
    $ObservedIdentity,
    [ValidateSet('observed', 'absent', 'inconclusive')][string]$IdentityQueryStatus,
    [ValidateSet('busy', 'free', 'inconclusive')][string]$MutexStatus,
    [ValidateSet('busy', 'clear', 'inconclusive')][string]$PortsStatus,
    [bool]$IdentityMatches,
    [bool]$SupervisorCandidate
  )

  $ambiguousResources = $MutexStatus -ne 'free' -or $PortsStatus -ne 'clear'
  if ($StateReadStatus -ne 'valid' -or $null -eq $State -or $null -eq $State.supervisorPid) {
    if ($ambiguousResources) { return 'identity_inconclusive' }
    return 'stopped'
  }
  if ($IdentityQueryStatus -eq 'inconclusive') { return 'identity_inconclusive' }
  if ($IdentityQueryStatus -eq 'absent') {
    if ($ambiguousResources) { return 'identity_inconclusive' }
    return 'stopped'
  }
  if (-not $SupervisorCandidate) {
    if ($ambiguousResources) { return 'identity_inconclusive' }
    return 'pid_reused_recoverable'
  }
  $identity = $State.supervisorIdentity
  $hasIdentity = $null -ne $identity -and (Test-NodarisProcessIdentity $identity $identity)
  if (-not $hasIdentity) { return 'identity_inconclusive' }
  if ($IdentityMatches) {
    if ($MutexStatus -eq 'busy') { return 'confirmed_active' }
    return 'identity_inconclusive'
  }
  if ($ambiguousResources) { return 'identity_inconclusive' }
  return 'pid_reused_recoverable'
}

function Test-NodarisSupervisorMutex {
  $mutex = $null
  $ownsMutex = $false
  try {
    $mutex = [Threading.Mutex]::new($false, 'LocalNodaris-M01-Supervisor')
    $ownsMutex = $mutex.WaitOne(0)
    if ($ownsMutex) {
      $mutex.ReleaseMutex()
      $ownsMutex = $false
      return 'free'
    }
    return 'busy'
  } catch [Threading.AbandonedMutexException] {
    if ($null -ne $mutex) { try { $mutex.ReleaseMutex() } catch { } }
    return 'free'
  } catch {
    return 'inconclusive'
  } finally {
    if ($null -ne $mutex) { $mutex.Dispose() }
  }
}

function Stop-NodarisVerifiedProcess {
  param(
    [Parameter(Mandatory = $true)]$Process,
    [Parameter(Mandatory = $true)]$ExpectedIdentity,
    [scriptblock]$IdentityReader = { param($id) Get-NodarisProcessIdentity -ProcessId $id },
    [scriptblock]$StopAction
  )
  try { $observed = & $IdentityReader $Process.Id } catch { throw 'NODARIS_PROCESS_IDENTITY_UNCONFIRMED' }
  if (-not (Test-NodarisProcessIdentity $ExpectedIdentity $observed)) { throw 'NODARIS_PROCESS_IDENTITY_MISMATCH' }
  if ($null -ne $StopAction) { & $StopAction $Process } else { $Process.Kill() }
}

function Invoke-NodarisRecoveryPolicy {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('agent', 'gateway', 'tunnel')][string]$Name,
    [Parameter(Mandatory = $true)][int]$ExistingRetries,
    [Parameter(Mandatory = $true)][int]$MaxRetries,
    [Parameter(Mandatory = $true)][scriptblock]$StopAction,
    [Parameter(Mandatory = $true)][scriptblock]$StartAction,
    [Parameter(Mandatory = $true)][scriptblock]$HealthAction,
    [Parameter(Mandatory = $true)][scriptblock]$BackoffAction,
    [Parameter(Mandatory = $true)][scriptblock]$EventAction,
    [Parameter(Mandatory = $true)][scriptblock]$FailureReasonAction,
    [Parameter(Mandatory = $true)][scriptblock]$StopRequestedAction
  )

  $retryCount = $ExistingRetries
  & $StopAction
  if (& $StopRequestedAction) {
    return @{ status = 'stopped'; retryCount = $retryCount; reasonCode = 'stop_requested' }
  }
  while ($retryCount -lt $MaxRetries) {
    $retryCount++
    $attempt = $retryCount
    $delay = Get-NodarisBackoffSeconds ($attempt - 1)
    & $EventAction 'recovery' 'started' 'process_exited' $attempt $delay | Out-Null
    & $EventAction 'backoff' 'scheduled' 'retry_scheduled' $attempt $delay | Out-Null
    $backoffCompleted = & $BackoffAction $delay
    if ($backoffCompleted -is [bool] -and -not $backoffCompleted) {
      return @{ status = 'stopped'; retryCount = $retryCount; reasonCode = 'stop_requested' }
    }
    & $EventAction 'backoff' 'completed' 'retry_delay_elapsed' $attempt $delay | Out-Null

    if (& $StopRequestedAction) {
      return @{ status = 'stopped'; retryCount = $retryCount; reasonCode = 'stop_requested' }
    }

    try {
      & $StartAction
      if (-not (& $HealthAction)) { throw 'NODARIS_HEALTH_TIMEOUT' }
      & $EventAction 'recovery' 'healthy' 'health_passed' $attempt $delay | Out-Null
      return @{ status = 'healthy'; retryCount = $retryCount; reasonCode = 'health_passed' }
    } catch {
      if ($_.Exception.Message -eq 'NODARIS_CHILD_IDENTITY_UNCONFIRMED') {
        & $EventAction 'recovery' 'failed' 'process_start_failed' $attempt $delay | Out-Null
        & $EventAction 'recovery' 'failed' 'circuit_open' $attempt 0 | Out-Null
        return @{ status = 'circuit_open'; retryCount = $retryCount; reasonCode = 'circuit_open' }
      }
      $reasonCode = if ($_.Exception.Message -eq 'NODARIS_PORT_IN_USE') {
        'port_in_use'
      } elseif ($_.Exception.Message -eq 'NODARIS_HEALTH_TIMEOUT') {
        & $FailureReasonAction
      } else {
        'process_start_failed'
      }
      & $StopAction
      & $EventAction 'recovery' 'failed' $reasonCode $attempt $delay | Out-Null
    }
  }

  & $EventAction 'recovery' 'failed' 'circuit_open' $retryCount 0 | Out-Null
  return @{ status = 'circuit_open'; retryCount = $retryCount; reasonCode = 'circuit_open' }
}

function Invoke-NodarisStartupPolicy {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('agent', 'gateway', 'tunnel')][string]$Name,
    [Parameter(Mandatory = $true)][int]$MaxRetries,
    [Parameter(Mandatory = $true)][scriptblock]$StopAction,
    [Parameter(Mandatory = $true)][scriptblock]$StartAction,
    [Parameter(Mandatory = $true)][scriptblock]$HealthAction,
    [Parameter(Mandatory = $true)][scriptblock]$BackoffAction,
    [Parameter(Mandatory = $true)][scriptblock]$EventAction,
    [Parameter(Mandatory = $true)][scriptblock]$FailureReasonAction,
    [Parameter(Mandatory = $true)][scriptblock]$StopRequestedAction
  )

  $retryCount = 0
  for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
    if (& $StopRequestedAction) {
      return @{ status = 'stopped'; retryCount = $retryCount; reasonCode = 'stop_requested' }
    }
    if ($attempt -gt 1) {
      $delay = Get-NodarisBackoffSeconds ($attempt - 2)
      & $EventAction 'backoff' 'scheduled' 'retry_scheduled' $attempt $delay | Out-Null
      $backoffCompleted = & $BackoffAction $delay
      if ($backoffCompleted -is [bool] -and -not $backoffCompleted) {
        return @{ status = 'stopped'; retryCount = $retryCount; reasonCode = 'stop_requested' }
      }
      & $EventAction 'backoff' 'completed' 'retry_delay_elapsed' $attempt $delay | Out-Null
    } else { $delay = 0 }

    & $EventAction 'attempt' 'started' 'none' $attempt $delay | Out-Null
    try {
      & $StartAction
      if (-not (& $HealthAction)) { throw 'NODARIS_HEALTH_TIMEOUT' }
      & $EventAction 'attempt' 'healthy' 'health_passed' $attempt $delay | Out-Null
      return @{ status = 'healthy'; retryCount = $retryCount; reasonCode = 'health_passed' }
    } catch {
      if ($_.Exception.Message -eq 'NODARIS_CHILD_IDENTITY_UNCONFIRMED') {
        & $EventAction 'attempt' 'failed' 'process_start_failed' $attempt $delay | Out-Null
        & $EventAction 'attempt' 'failed' 'circuit_open' $attempt 0 | Out-Null
        return @{ status = 'circuit_open'; retryCount = $retryCount; reasonCode = 'circuit_open' }
      }
      $reasonCode = if ($_.Exception.Message -eq 'NODARIS_PORT_IN_USE') {
        'port_in_use'
      } elseif ($_.Exception.Message -eq 'NODARIS_HEALTH_TIMEOUT') {
        & $FailureReasonAction
      } else {
        'process_start_failed'
      }
      & $StopAction
      & $EventAction 'attempt' 'failed' $reasonCode $attempt $delay | Out-Null
      if (& $StopRequestedAction) {
        return @{ status = 'stopped'; retryCount = $retryCount; reasonCode = 'stop_requested' }
      }
      if ($attempt -gt $MaxRetries) {
        & $EventAction 'attempt' 'failed' 'circuit_open' $attempt 0 | Out-Null
        return @{ status = 'circuit_open'; retryCount = $retryCount; reasonCode = 'circuit_open' }
      }
      $retryCount++
    }
  }

  return @{ status = 'circuit_open'; retryCount = $retryCount; reasonCode = 'circuit_open' }
}

function Stop-NodarisChildrenInOrder {
  param(
    [Parameter(Mandatory = $true)][string[]]$Names,
    [Parameter(Mandatory = $true)][scriptblock]$StopAction
  )

  $stopped = [System.Collections.Generic.List[string]]::new()
  $failed = $false
  foreach ($name in $Names) {
    try {
      & $StopAction $name
      $stopped.Add($name)
    } catch {
      $failed = $true
    }
  }
  if ($failed) { throw 'NODARIS_STOP_FAILED' }
  return ,$stopped.ToArray()
}
