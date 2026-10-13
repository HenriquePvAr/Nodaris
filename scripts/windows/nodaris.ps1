<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('install', 'uninstall', 'start', 'stop', 'restart', 'status', 'enable', 'disable')]
  [string]$Command
)

$ErrorActionPreference = 'Stop'
$taskName = 'Nodaris User Session'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$supervisor = Join-Path $PSScriptRoot 'supervisor.ps1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'Nodaris\supervisor'
$stateFile = Join-Path $stateRoot 'state.json'
$stopFile = Join-Path $stateRoot 'stop.request'

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
    $powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $supervisor
    Start-Process -FilePath $powerShell -ArgumentList $arguments -WindowStyle Hidden
  }
  'Solicitada inicialização Nodaris. Consulte status para verificar saúde.'
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

    $powerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $supervisor
    $action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments -WorkingDirectory $repoRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Inicia e supervisiona o Nodaris na sessão do usuário atual, em loopback.' | Out-Null
    'Tarefa instalada para o próximo logon do usuário atual. Nenhum serviço foi iniciado ou interrompido nesta operação.'
  }
  'uninstall' {
    if (Get-NodarisTask) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    'Tarefa removida. Estado e logs locais, se existentes, foram preservados.'
  }
  'start' { Start-Nodaris }
  'stop' {
    if (Get-NodarisTask) {
      New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
      [IO.File]::WriteAllText($stopFile, [DateTime]::UtcNow.ToString('o'), [Text.UTF8Encoding]::new($false))
      $deadline = [DateTime]::UtcNow.AddSeconds(20)
      do {
        Start-Sleep -Milliseconds 500
        $state = Get-SupervisorState
      } while ([DateTime]::UtcNow -lt $deadline -and $null -ne $state -and $state.status -notin @('stopped', 'degraded', 'error'))
    }
    'Parada supervisionada solicitada. Serviços iniciados externamente não são encerrados; confira status.'
  }
  'restart' {
    & $PSCommandPath stop
    Start-Sleep -Seconds 2
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
