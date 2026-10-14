<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

function Get-NodarisBackoffSeconds([int]$RetryIndex) {
  $delays = @(5, 15, 30, 60, 120)
  if ($RetryIndex -lt 0 -or $RetryIndex -ge $delays.Count) { throw 'Índice de backoff fora da política.' }
  return $delays[$RetryIndex]
}

function Set-NodarisPrivateDirectoryAcl([string]$Path) {
  $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
  $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  $directoryAcl = [Security.AccessControl.DirectorySecurity]::new()
  $directoryAcl.SetAccessRuleProtection($true, $false)
  $directoryAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($currentSid, 'FullControl', $inherit, 'None', 'Allow'))
  $directoryAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($systemSid, 'FullControl', $inherit, 'None', 'Allow'))
  [IO.Directory]::SetAccessControl($Path, $directoryAcl)
}

function Test-NodarisPrivateDirectoryAcl([string]$Path) {
  try {
    $acl = [IO.Directory]::GetAccessControl($Path)
    if (-not $acl.AreAccessRulesProtected) { return $false }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $expected = @($currentSid, 'S-1-5-18') | Sort-Object
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if ($rules.Count -ne 2) { return $false }
    $actual = @()
    foreach ($rule in $rules) {
      if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { return $false }
      if (($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne [Security.AccessControl.FileSystemRights]::FullControl) { return $false }
      $actual += $rule.IdentityReference.Value
    }
    return (($actual | Sort-Object) -join ',') -eq ($expected -join ',')
  } catch { return $false }
}

function Test-NodarisPrivateFileAcl([string]$Path) {
  try {
    $acl = [IO.File]::GetAccessControl($Path)
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $expected = @($currentSid, 'S-1-5-18') | Sort-Object
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if ($rules.Count -ne 2) { return $false }
    $actual = @()
    foreach ($rule in $rules) {
      if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { return $false }
      if (($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne [Security.AccessControl.FileSystemRights]::FullControl) { return $false }
      $actual += $rule.IdentityReference.Value
    }
    return (($actual | Sort-Object) -join ',') -eq ($expected -join ',')
  } catch { return $false }
}

function Test-NodarisTunnelReadiness($Health, [ref]$ReasonCode) {
  $ReasonCode.Value = 'control_plane_unreported'
  if ($null -eq $Health -or $Health.live -ne $true) {
    $ReasonCode.Value = 'client_not_live'
    return $false
  }
  if ($Health.ready -ne $true) {
    $ReasonCode.Value = 'client_not_ready'
    return $false
  }
  $controlPlane = $Health.components.'control-plane'
  if ($null -eq $controlPlane) { return $false }
  if ($controlPlane.status -ne 'ok' -or $controlPlane.state -ne 'polling') {
    $ReasonCode.Value = 'control_plane_not_polling'
    return $false
  }
  if ($null -eq $controlPlane.details.last_success) {
    $ReasonCode.Value = 'poll_not_yet_succeeded'
    return $false
  }
  try {
    $lastSuccessValue = $controlPlane.details.last_success
    if ($lastSuccessValue -is [DateTimeOffset]) {
      $lastSuccess = $lastSuccessValue.ToUniversalTime()
    } elseif ($lastSuccessValue -is [DateTime]) {
      $lastSuccess = [DateTimeOffset]::new($lastSuccessValue.ToUniversalTime())
    } else {
      $lastSuccess = [DateTimeOffset]::Parse([string]$lastSuccessValue, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    }
    $pollWindow = [int]$controlPlane.details.effective_wait_seconds + [int]$controlPlane.details.deadline_seconds
    if ($pollWindow -le 0) {
      $ReasonCode.Value = 'poll_window_invalid'
      return $false
    }
    $ageSeconds = [Math]::Max(0, ([DateTimeOffset]::UtcNow - $lastSuccess).TotalSeconds)
    if ($ageSeconds -gt $pollWindow) {
      $ReasonCode.Value = 'poll_stale'
      return $false
    }
    $ReasonCode.Value = 'poll_current'
    return $true
  } catch {
    $ReasonCode.Value = 'poll_timestamp_invalid'
    return $false
  }
}

function Write-NodarisDiagnosticEvent {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][ValidateSet('supervisor', 'configuration', 'agent', 'gateway', 'tunnel')][string]$Component,
    [Parameter(Mandatory = $true)][ValidateSet('lifecycle', 'configuration', 'attempt', 'process', 'health', 'backoff', 'readiness', 'recovery', 'bootstrap', 'mutex', 'directory', 'telemetry')][string]$Stage,
    [Parameter(Mandatory = $true)][ValidateSet('started', 'healthy', 'ready', 'failed', 'timeout', 'scheduled', 'completed', 'skipped', 'stopped')][string]$Status,
    [Parameter(Mandatory = $true)][ValidateSet('none', 'mutex_acquired', 'duplicate_instance', 'configuration_valid', 'configuration_invalid', 'process_started', 'port_in_use', 'process_start_failed', 'health_passed', 'health_timeout', 'health_request_failed', 'health_unhealthy', 'health_http_unauthorized', 'health_http_error', 'health_transport_error', 'local_listener_unavailable', 'control_plane_not_polling', 'poll_not_yet_succeeded', 'poll_stale', 'poll_current', 'poll_timestamp_invalid', 'poll_window_invalid', 'control_plane_unreported', 'client_not_live', 'client_not_ready', 'retry_scheduled', 'retry_delay_elapsed', 'circuit_open', 'process_exited', 'stop_requested', 'startup_failed', 'launcher_entry', 'launch_call_started', 'launch_call_returned', 'process_created', 'process_creation_observed', 'script_entry', 'project_path_resolve_started', 'project_path_resolve_completed', 'diagnostics_load_started', 'diagnostics_load_completed', 'lifecycle_load_started', 'lifecycle_load_completed', 'mutex_wait_started', 'state_directory_create_started', 'state_directory_created', 'directory_acl_started', 'directory_acl_protected', 'early_trace_unavailable', 'first_write_succeeded', 'trace_timestamp_invalid', 'trace_spool_invalid')][string]$ReasonCode,
    [Parameter(Mandatory = $true)][int]$Attempt,
    [long]$DurationMs = 0,
    [int]$TimeoutSeconds = -1,
    [int]$BackoffSeconds = -1,
    [string]$TimestampUtc = ''
  )

  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw 'Diretório local de diagnóstico indisponível.' }
  $maxFileBytes = 262144
  $maxRotations = 3
  if (-not (Test-NodarisPrivateDirectoryAcl $directory)) { throw 'ACL do diretório de diagnóstico não está restrita.' }
  if ((Test-Path -LiteralPath $Path -PathType Leaf) -and -not (Test-NodarisPrivateFileAcl $Path)) { throw 'ACL do arquivo de diagnóstico não está restrita.' }
  $eventTime = [DateTime]::UtcNow
  if (-not [string]::IsNullOrWhiteSpace($TimestampUtc)) {
    if ($TimestampUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?Z$') { throw 'Timestamp de diagnóstico inválido.' }
    $eventTime = [DateTime]::Parse($TimestampUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
  }
  $entry = [ordered]@{
    schemaVersion = 1
    timestampUtc = $eventTime.ToString('o')
    durationMs = [Math]::Max(0, $DurationMs)
    component = $Component
    stage = $Stage
    attempt = [Math]::Max(0, $Attempt)
    timeoutSeconds = $(if ($TimeoutSeconds -ge 0) { $TimeoutSeconds } else { $null })
    backoffSeconds = $(if ($BackoffSeconds -ge 0) { $BackoffSeconds } else { $null })
    status = $Status
    reasonCode = $ReasonCode
  }
  $line = ($entry | ConvertTo-Json -Compress) + [Environment]::NewLine
  $encoding = [Text.UTF8Encoding]::new($false)
  $lineBytes = $encoding.GetByteCount($line)
  $protectFile = -not (Test-Path -LiteralPath $Path -PathType Leaf)
  if (-not $protectFile -and ((Get-Item -LiteralPath $Path).Length + $lineBytes -gt $maxFileBytes)) {
    $oldest = "$Path.$maxRotations"
    Remove-Item -LiteralPath $oldest -Force -ErrorAction SilentlyContinue
    for ($index = $maxRotations - 1; $index -ge 1; $index--) {
      $source = "$Path.$index"
      if (Test-Path -LiteralPath $source) { Move-Item -LiteralPath $source -Destination "$Path.$($index + 1)" -Force }
    }
    Move-Item -LiteralPath $Path -Destination "$Path.1" -Force
    $protectFile = $true
  }
  [IO.File]::AppendAllText($Path, $line, $encoding)

  if ($protectFile) {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $fileAcl = [Security.AccessControl.FileSecurity]::new()
    $fileAcl.SetAccessRuleProtection($true, $false)
    $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($currentSid, 'FullControl', 'Allow'))
    $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($systemSid, 'FullControl', 'Allow'))
    [IO.File]::SetAccessControl($Path, $fileAcl)
  }
}

function Write-Diagnostic([string]$Component, [string]$Stage, [string]$Status, [string]$ReasonCode, [int]$Attempt = 0, [long]$DurationMs = 0, [int]$TimeoutSeconds = -1, [int]$BackoffSeconds = -1) {
  try {
    Write-NodarisDiagnosticEvent -Path $script:diagnosticsFile -Component $Component -Stage $Stage -Status $Status -ReasonCode $ReasonCode -Attempt $Attempt -DurationMs $DurationMs -TimeoutSeconds $TimeoutSeconds -BackoffSeconds $BackoffSeconds | Out-Null
  } catch { }
}
