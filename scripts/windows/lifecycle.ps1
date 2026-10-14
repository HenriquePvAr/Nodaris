<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

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
