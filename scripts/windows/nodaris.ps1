<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('install', 'repair', 'uninstall', 'start', 'stop', 'restart', 'status', 'enable', 'disable')]
  [string]$Command
)

$ErrorActionPreference = 'Stop'
$taskName = 'Nodaris User Session'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$supervisor = Join-Path $PSScriptRoot 'supervisor.ps1'
$launcher = Join-Path $PSScriptRoot 'launcher.vbs'
$diagnosticsScript = Join-Path $PSScriptRoot 'diagnostics.ps1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'Nodaris\supervisor'
$stateFile = Join-Path $stateRoot 'state.json'
$stopFile = Join-Path $stateRoot 'stop.request'
. $diagnosticsScript

function Get-NodarisTask {
  Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
}

function Get-SupervisorState {
  if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
  try { return Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { return $null }
}

function Get-LocalPortState([int]$Port) {
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $pending = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if (-not $pending.AsyncWaitHandle.WaitOne(500)) { return $false }
    $client.EndConnect($pending)
    return $true
  } catch { return $false } finally { $client.Dispose() }
}

function Show-Status {
  $task = Get-NodarisTask
  $state = Get-SupervisorState
  if ($null -eq $task) { 'AUTO_START=NOT_CONFIGURED' } else { "AUTO_START=$($task.State); enabled=$($task.Settings.Enabled)" }
  if ($null -ne $state) {
    "SUPERVISOR=$($state.status); updated=$($state.updatedAt)"
    foreach ($service in @('agent', 'gateway', 'tunnel')) {
      $entry = $state.services.$service
      if ($null -ne $entry) { '{0}={1}; pid={2}; restarts={3}' -f $service,$entry.status,$entry.pid,$entry.restartCount }
    }
  } else { 'SUPERVISOR=NO_STATE_RECORDED' }
  'agent_port_3334=' + $(if (Get-LocalPortState 3334) { 'LISTENING' } else { 'CLOSED' })
  'gateway_port_3333=' + $(if (Get-LocalPortState 3333) { 'LISTENING' } else { 'CLOSED' })
  'tunnel_health_8080=' + $(if (Get-LocalPortState 8080) { 'LISTENING' } else { 'CLOSED' })
  try {
    $ready = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/readyz' -TimeoutSec 2 -UseBasicParsing
    'tunnel_ready=' + $ready.StatusCode
  } catch { 'tunnel_ready=NOT_READY_OR_UNAVAILABLE' }
  try {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health?details=true' -TimeoutSec 2
    $controlPlane = $health.components.'control-plane'
    if ($null -eq $controlPlane) {
      'tunnel_control_plane=NOT_REPORTED'
      'tunnel_chatgpt_readiness=WAITING'
    } else {
      'tunnel_control_plane={0}/{1}' -f $controlPlane.status,$controlPlane.state
      $reasonCode = ''
      $tunnelReady = Test-NodarisTunnelReadiness $health ([ref]$reasonCode)
      'tunnel_chatgpt_readiness=' + $(if ($tunnelReady) { 'READY' } else { 'WAITING_FOR_RECENT_POLL' })
      'tunnel_readiness_reason=' + $reasonCode
    }
  } catch {
    'tunnel_control_plane=UNAVAILABLE'
    'tunnel_chatgpt_readiness=WAITING'
  }
}

function Start-Nodaris {
  if (-not (Get-NodarisTask)) { throw 'A tarefa ainda não está instalada. Execute install.' }
  $state = Get-SupervisorState
  if ($null -ne $state -and $state.status -eq 'running' -and (Get-Process -Id ([int]$state.supervisorPid) -ErrorAction SilentlyContinue)) {
    'Supervisor Nodaris já está em execução.'
    return
  }
  Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
  $task = Get-NodarisTask
  if ($task.Settings.Enabled) {
    Start-ScheduledTask -TaskName $taskName
  } else {
    $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
    Start-Process -FilePath $wscript -ArgumentList ('"{0}"' -f $launcher) -WindowStyle Hidden
  }
  'Solicitada inicialização Nodaris. Consulte status para verificar saúde.'
}

function Request-NodarisStop([int]$TimeoutSeconds = 30) {
  if (-not (Get-NodarisTask)) { return $false }
  $state = Get-SupervisorState
  if ($null -ne $state -and $state.status -in @('stopped', 'degraded', 'error')) {
    $supervisorAlive = $state.supervisorPid -and (Get-Process -Id ([int]$state.supervisorPid) -ErrorAction SilentlyContinue)
    if (-not $supervisorAlive) {
      return (-not (Get-LocalPortState 3333) -and -not (Get-LocalPortState 3334) -and -not (Get-LocalPortState 8080))
    }
  }
  if ($null -eq $state -and -not (Get-LocalPortState 3333) -and -not (Get-LocalPortState 3334) -and -not (Get-LocalPortState 8080)) {
    return $true
  }

  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  [IO.File]::WriteAllText($stopFile, [DateTime]::UtcNow.ToString('o'), [Text.UTF8Encoding]::new($false))
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 500
    $state = Get-SupervisorState
    if ($null -ne $state -and $state.status -in @('stopped', 'degraded', 'error')) {
      $supervisorAlive = $state.supervisorPid -and (Get-Process -Id ([int]$state.supervisorPid) -ErrorAction SilentlyContinue)
      if (-not $supervisorAlive) {
        return (-not (Get-LocalPortState 3333) -and -not (Get-LocalPortState 3334) -and -not (Get-LocalPortState 8080))
      }
    }
    if ($null -ne $state -and $state.supervisorPid -and -not (Get-Process -Id ([int]$state.supervisorPid) -ErrorAction SilentlyContinue)) {
      return (-not (Get-LocalPortState 3333) -and -not (Get-LocalPortState 3334) -and -not (Get-LocalPortState 8080))
    }
  } while ([DateTime]::UtcNow -lt $deadline)
  return $false
}

switch ($Command) {
  'install' {
    if (Get-NodarisTask) { throw "A tarefa '$taskName' já existe; não será substituída automaticamente." }
    if (-not (Test-Path -LiteralPath $supervisor)) { throw 'Arquivo do supervisor não encontrado.' }
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($currentSid), 'FullControl', $inherit, 'None', 'Allow'))
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($systemSid, 'FullControl', $inherit, 'None', 'Allow'))
    Set-Acl -LiteralPath $stateRoot -AclObject $acl

    $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
    $action = New-ScheduledTaskAction -Execute $wscript -Argument ('"{0}"' -f $launcher) -WorkingDirectory $repoRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Inicia e supervisiona o Nodaris na sessão do usuário atual, em loopback.' | Out-Null
    'Tarefa instalada para o próximo logon do usuário atual. Nenhum serviço foi iniciado ou interrompido nesta operação.'
  }
  'repair' {
    $task = Get-NodarisTask
    if ($null -eq $task) { throw "A tarefa '$taskName' não existe; execute install." }
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Launcher sem console não encontrado.' }
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    $backupFile = Join-Path $stateRoot 'task-before-invisible-launcher.xml'
    $previousXml = Export-ScheduledTask -TaskName $taskName
    [IO.File]::WriteAllText($backupFile, $previousXml, [Text.UTF8Encoding]::new($false))
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $fileAcl = [Security.AccessControl.FileSecurity]::new()
    $fileAcl.SetAccessRuleProtection($true, $false)
    $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($currentSid), 'FullControl', 'Allow'))
    $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($systemSid, 'FullControl', 'Allow'))
    Set-Acl -LiteralPath $backupFile -AclObject $fileAcl

    $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
    $action = New-ScheduledTaskAction -Execute $wscript -Argument ('"{0}"' -f $launcher) -WorkingDirectory $repoRoot
    Set-ScheduledTask -TaskName $taskName -Action $action | Out-Null
    $updated = Get-NodarisTask
    if ($updated.Actions[0].Execute -ne $wscript) { throw 'A tarefa não confirmou o launcher atualizado; use o XML de recuperação local.' }
    'Ação futura atualizada para wscript.exe. A sessão em execução não foi reiniciada; exportação de recuperação protegida foi preservada localmente.'
  }
  'uninstall' {
    if (Get-NodarisTask) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    'Tarefa removida. Estado e logs locais, se existentes, foram preservados.'
  }
  'start' { Start-Nodaris }
  'stop' {
    if (Request-NodarisStop) { 'Parada supervisionada confirmada. Serviços iniciados externamente não são encerrados.' }
    else { throw 'Parada supervisionada não foi confirmada dentro do prazo; não inicie outro supervisor.' }
  }
  'restart' {
    if (-not (Request-NodarisStop)) { throw 'Parada supervisionada não foi confirmada; reinício cancelado para evitar duplicatas.' }
    Start-Nodaris
  }
  'status' { Show-Status }
  'enable' {
    if (-not (Get-NodarisTask)) { throw 'A tarefa ainda não está instalada.' }
    Enable-ScheduledTask -TaskName $taskName | Out-Null
    'Inicialização automática habilitada; ela ocorrerá no próximo logon.'
  }
  'disable' {
    if (Get-NodarisTask) { Disable-ScheduledTask -TaskName $taskName | Out-Null }
    'Inicialização automática desabilitada sem desinstalar o Nodaris.'
  }
}
