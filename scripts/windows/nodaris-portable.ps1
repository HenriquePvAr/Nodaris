<#
  Per-user, loopback-only Agent/Gateway runtime. This entry point does not provision
  a tunnel, enroll a Registry project, create a vault, or enable any write capability.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('configure', 'doctor', 'task-install', 'task-enable', 'task-disable', 'task-remove', 'tunnel-prepare-install', 'tunnel-configure', 'tunnel-enable', 'tunnel-disable', 'start', 'stop', 'status', 'run')]
  [string]$Command,
  [string]$TunnelExecutable,
  [string]$TunnelId
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'nodaris-portable-config.psm1') -Force
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$taskName = 'Nodaris Portable User Session'
$scriptPath = [IO.Path]::GetFullPath($PSCommandPath)

function Get-PortableTask {
  return Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
}

function Test-PortableTaskIdentity($Task) {
  if ($null -eq $Task) { return $false }
  $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  try {
    $taskSid = if ([string]$Task.Principal.UserId -match '^S-1-') { [string]$Task.Principal.UserId } else { ([Security.Principal.NTAccount]::new([string]$Task.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value }
  } catch { return $false }
  $actions = @($Task.Actions)
  if ($taskSid -cne $currentSid -or $actions.Count -ne 1) { return $false }
  $expectedExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $expectedArgs = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' + $scriptPath + '" run'
  return ([IO.Path]::GetFullPath([string]$actions[0].Execute) -ieq [IO.Path]::GetFullPath($expectedExe) -and [string]$actions[0].Arguments -ceq $expectedArgs -and [string]$actions[0].WorkingDirectory -ieq $repoRoot -and [string]$Task.Settings.MultipleInstances -eq 'IgnoreNew')
}

function Read-PortableConfig {
  $loaded = Read-NodarisPortableConfig
  return $loaded
}

function Confirm-PortableAction([string]$Prompt, [string]$Expected) {
  if (-not [Environment]::UserInteractive) { throw 'PORTABLE_ACTION_REQUIRES_INTERACTIVE_USER' }
  Write-Output $Prompt
  if ((Read-Host ('Digite ' + $Expected + ' para confirmar')) -cne $Expected) { throw 'PORTABLE_LOCAL_APPROVAL_DENIED' }
}

function Get-PortableListenerOwner([int]$Port) {
  try {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop)
    if ($listeners.Count -gt 1) { return -2 }
    if ($listeners.Count -eq 1) {
      if ([string]$listeners[0].LocalAddress -cne '127.0.0.1') { return -3 }
      return [int]$listeners[0].OwningProcess
    }
  } catch {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    try { $listener.Start(); return 0 } catch { return -1 } finally { $listener.Stop() }
  }
  return 0
}

function Test-PortableAgentHealth($Loaded) {
  try {
    $headers = @{ Authorization = 'Bearer ' + $Loaded.token }
    $body = @{ operation = 'health' } | ConvertTo-Json -Compress
    $result = Invoke-RestMethod -Uri 'http://127.0.0.1:3334/rpc' -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 3
    return ($result.status -eq 'ok' -and $result.machineId -eq $Loaded.config.machineId)
  } catch { return $false }
}

function Invoke-PortableTunnelDoctor($Tunnel) {
  $environment = Get-PortableBaseEnvironment
  $environment['CONTROL_PLANE_API_KEY'] = $Tunnel.runtimeKey
  $runtime = Read-PortableConfig
  $environment['NODARIS_PORTABLE_MCP_BEARER'] = $runtime.token
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $Tunnel.executable
  $startInfo.Arguments = 'doctor --config "' + $Tunnel.profilePath + '"'
  $startInfo.WorkingDirectory = $runtime.dataRoot
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $variables = $startInfo.EnvironmentVariables
  $variables.Clear()
  foreach ($name in $environment.Keys) { $variables[[string]$name] = [string]$environment[$name] }
  $process = $null
  try {
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { return $false }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) { $process.Kill(); $process.WaitForExit(5000) | Out-Null; return $false }
    $process.WaitForExit()
    $null = $stdout.GetAwaiter().GetResult(); $null = $stderr.GetAwaiter().GetResult()
    return ($process.ExitCode -eq 0)
  } finally {
    foreach ($name in @('CONTROL_PLANE_API_KEY','NODARIS_PORTABLE_MCP_BEARER')) { [void]$variables.Remove($name); $environment[$name] = $null }
    if ($null -ne $process) { $process.Dispose() }
    $startInfo = $null
  }
}

function Get-PortableBaseEnvironment {
  $environment = @{}
  foreach ($name in @('SystemRoot','WINDIR','PATH','TEMP','TMP','LOCALAPPDATA','APPDATA','USERPROFILE','HOMEDRIVE','HOMEPATH','USERNAME','USERDOMAIN','PROGRAMDATA','COMSPEC')) {
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($value)) { $environment[$name] = $value }
  }
  return $environment
}

function Start-PortableChildProcess([string]$Executable, [string]$Arguments, [string]$WorkingDirectory, [hashtable]$Environment) {
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $Executable
  $startInfo.Arguments = $Arguments
  $startInfo.WorkingDirectory = $WorkingDirectory
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $variables = $startInfo.EnvironmentVariables
  $variables.Clear()
  foreach ($name in $Environment.Keys) { $variables[[string]$name] = [string]$Environment[$name] }
  try {
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { throw 'PORTABLE_CHILD_START_FAILED' }
    return $process
  } finally {
    foreach ($name in @('NODARIS_TOKEN','CONTROL_PLANE_API_KEY','NODARIS_PORTABLE_MCP_BEARER')) { [void]$variables.Remove($name) }
    $startInfo = $null
  }
}

function Get-PortableNodePath {
  $command = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command) { throw 'PORTABLE_NODE_NOT_FOUND' }
  $node = [IO.Path]::GetFullPath($command.Source)
  $version = (& $node --version 2>$null | Select-Object -First 1)
  if ($version -notmatch '^v(\d+)\.') { throw 'PORTABLE_NODE_VERSION_UNKNOWN' }
  $major = [int]$Matches[1]
  if ($major -lt 22 -or $major -ge 25) { throw 'PORTABLE_NODE_VERSION_UNSUPPORTED' }
  return $node
}

function Get-PortableOwnedProcess($ProcessRecord) {
  if ($null -eq $ProcessRecord -or [int]$ProcessRecord.pid -lt 1) { return $null }
  try {
    $process = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + [int]$ProcessRecord.pid) -ErrorAction Stop
    if ($null -eq $process -or [string]$process.ExecutablePath -ine [string]$ProcessRecord.executable -or [string]$process.CommandLine -cne [string]$ProcessRecord.commandLine) { return $null }
    $start = (Get-Process -Id ([int]$ProcessRecord.pid) -ErrorAction Stop).StartTime.ToUniversalTime().ToFileTimeUtc()
    if ($start -ne [long]$ProcessRecord.creationFileTime) { return $null }
    return (Get-Process -Id ([int]$ProcessRecord.pid) -ErrorAction Stop)
  } catch { return $null }
}

function Stop-PortableOwnedProcess($ProcessRecord) {
  $process = Get-PortableOwnedProcess $ProcessRecord
  if ($null -eq $process) {
    $stillPresent = Get-Process -Id ([int]$ProcessRecord.pid) -ErrorAction SilentlyContinue
    if ($stillPresent) { throw 'PORTABLE_PROCESS_IDENTITY_CHANGED; no process was stopped' }
    return
  }
  try {
    $process.Kill()
    if (-not $process.WaitForExit(10000)) { throw 'PORTABLE_OWNED_PROCESS_STOP_TIMEOUT' }
  } finally { $process.Dispose() }
}

function Get-PortableStartedProcessRecord($Process, [string]$ExpectedExecutable) {
  try {
    if ($null -eq $Process -or $Process.HasExited) { throw 'PORTABLE_CHILD_EXITED_DURING_STARTUP' }
    $cim = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + [int]$Process.Id) -ErrorAction Stop
    $startedAt = $Process.StartTime.ToUniversalTime().ToFileTimeUtc()
    if ($null -eq $cim -or [string]$cim.ExecutablePath -ine [IO.Path]::GetFullPath($ExpectedExecutable) -or [string]::IsNullOrWhiteSpace([string]$cim.CommandLine) -or $startedAt -lt 1) { throw 'PORTABLE_CHILD_IDENTITY_CAPTURE_FAILED' }
    return [pscustomobject]@{ pid=$Process.Id; executable=[IO.Path]::GetFullPath($ExpectedExecutable); commandLine=[string]$cim.CommandLine; creationFileTime=$startedAt }
  } catch {
    try { if ($null -ne $Process -and -not $Process.HasExited) { $Process.Kill(); $Process.WaitForExit(5000) | Out-Null } } catch { }
    throw 'PORTABLE_CHILD_IDENTITY_CAPTURE_FAILED'
  }
}

function Start-PortableRuntime {
  $loaded = Read-PortableConfig
  $tunnel = Read-NodarisPortableTunnelConfig
  if ($null -ne $tunnel -and -not $tunnel.config.enabled) { $tunnel.runtimeKey = $null }
  if ($null -ne $tunnel -and $tunnel.config.enabled -and -not (Invoke-PortableTunnelDoctor $tunnel)) { throw 'PORTABLE_TUNNEL_DOCTOR_FAILED' }
  $node = Get-PortableNodePath
  $tsx = Join-Path $repoRoot 'node_modules\tsx\dist\cli.mjs'
  if (-not (Test-Path -LiteralPath $tsx -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $repoRoot 'node_modules\@modelcontextprotocol\client') -PathType Container)) { throw 'PORTABLE_DEPENDENCIES_MISSING' }
  $ownerAgent = Get-PortableListenerOwner 3334
  $ownerGateway = Get-PortableListenerOwner 3333
  $ownerTunnel = if ($null -ne $tunnel -and $tunnel.config.enabled) { Get-PortableListenerOwner 3335 } else { 0 }
  if ($ownerAgent -ne 0 -or $ownerGateway -ne 0 -or $ownerTunnel -ne 0) { throw 'PORTABLE_PORT_CONFLICT' }

  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -replace '[^A-Za-z0-9_-]','_'
  $mutex = [Threading.Mutex]::new($false, ('Local\Nodaris-Portable-' + $sid))
  $ownsMutex = $false
  $started = @()
  $tunnelProcess = $null
  try {
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { throw 'PORTABLE_SUPERVISOR_ALREADY_RUNNING' }
    # Recheck ports after mutex acquisition; never take over a process of unknown ownership.
    if ((Get-PortableListenerOwner 3334) -ne 0 -or (Get-PortableListenerOwner 3333) -ne 0 -or ($tunnel -and $tunnel.config.enabled -and (Get-PortableListenerOwner 3335) -ne 0)) { throw 'PORTABLE_PORT_CONFLICT' }
    $agentEnvironment = Get-PortableBaseEnvironment
    $agentEnvironment['NODARIS_TOKEN'] = $loaded.token
    $agentEnvironment['NODARIS_ALLOWED_ROOTS'] = @($loaded.config.repositoryRoots) -join ';'
    $agentEnvironment['NODARIS_MACHINE_ID'] = [string]$loaded.config.machineId
    $agentEnvironment['AGENT_HOST'] = '127.0.0.1'; $agentEnvironment['AGENT_PORT'] = '3334'
    $agentEnvironment['GATEWAY_HOST'] = '127.0.0.1'; $agentEnvironment['GATEWAY_PORT'] = '3333'
    $agent = Start-PortableChildProcess -Executable $node -Arguments '--import tsx "apps/agent/src/index.ts"' -WorkingDirectory $repoRoot -Environment $agentEnvironment
    $started += (Get-PortableStartedProcessRecord -Process $agent -ExpectedExecutable $node)
    $gateway = Start-PortableChildProcess -Executable $node -Arguments '--import tsx "apps/gateway/src/index.ts"' -WorkingDirectory $repoRoot -Environment $agentEnvironment
    $started += (Get-PortableStartedProcessRecord -Process $gateway -ExpectedExecutable $node)
    $agentEnvironment['NODARIS_TOKEN'] = $null

    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    $ready = $false
    do {
      Start-Sleep -Milliseconds 500
      $agentOwner = Get-PortableListenerOwner 3334
      $gatewayOwner = Get-PortableListenerOwner 3333
      if (-not $agent.HasExited -and -not $gateway.HasExited -and $agentOwner -eq $agent.Id -and $gatewayOwner -eq $gateway.Id -and (Test-PortableAgentHealth $loaded)) {
        $checkEnvironment = Get-PortableBaseEnvironment
        $checkEnvironment['NODARIS_PORTABLE_MCP_PORT'] = '3333'
        $checkEnvironment['NODARIS_PORTABLE_MCP_TOKEN'] = $loaded.token
        $check = Start-PortableChildProcess -Executable $node -Arguments ('"' + (Join-Path $PSScriptRoot 'nodaris-portable-mcp-check.cjs') + '"') -WorkingDirectory $repoRoot -Environment $checkEnvironment
        $checkEnvironment['NODARIS_PORTABLE_MCP_TOKEN'] = $null
        if ($check.WaitForExit(15000) -and $check.ExitCode -eq 0) { $check.Dispose(); $ready = $true; break }
        if (-not $check.HasExited) { $check.Kill(); $check.WaitForExit(5000) | Out-Null }
        $check.Dispose()
      }
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'PORTABLE_RUNTIME_READINESS_FAILED' }
    if ($null -ne $tunnel -and $tunnel.config.enabled) {
      $tunnelEnvironment = Get-PortableBaseEnvironment
      $tunnelEnvironment['CONTROL_PLANE_API_KEY'] = $tunnel.runtimeKey
      $tunnelEnvironment['NODARIS_PORTABLE_MCP_BEARER'] = $loaded.token
      $tunnelProcess = Start-PortableChildProcess -Executable $tunnel.executable -Arguments ('run --config "' + $tunnel.profilePath + '"') -WorkingDirectory $loaded.dataRoot -Environment $tunnelEnvironment
      $tunnelEnvironment['CONTROL_PLANE_API_KEY'] = $null
      $tunnelEnvironment['NODARIS_PORTABLE_MCP_BEARER'] = $null
      $tunnel.runtimeKey = $null
      $started += (Get-PortableStartedProcessRecord -Process $tunnelProcess -ExpectedExecutable $tunnel.executable)
      $deadline = [DateTime]::UtcNow.AddSeconds(90)
      $tunnelReady = $false
      do {
        Start-Sleep -Milliseconds 500
        if ($tunnelProcess.HasExited) { throw 'PORTABLE_TUNNEL_PROCESS_EXITED' }
        if ((Get-PortableListenerOwner 3335) -eq $tunnelProcess.Id) {
          try {
            $null = Invoke-RestMethod -Uri 'http://127.0.0.1:3335/healthz' -TimeoutSec 2
            $null = Invoke-RestMethod -Uri 'http://127.0.0.1:3335/readyz' -TimeoutSec 2
            $tunnelReady = $true
          } catch { }
        }
      } while (-not $tunnelReady -and [DateTime]::UtcNow -lt $deadline)
      if (-not $tunnelReady) { throw 'PORTABLE_TUNNEL_READINESS_FAILED' }
    }
    $loaded.token = $null
    Write-Output ('PORTABLE_RUNTIME=READY MODE=READ_ONLY MCP=VERIFIED TUNNEL=' + $(if($null -ne $tunnel -and $tunnel.config.enabled){'HEALTHY'}else{'NOT_CONFIGURED'}))
    while (-not (Test-Path -LiteralPath (Join-Path $loaded.dataRoot 'stop.request'))) {
      if ($agent.HasExited -or $gateway.HasExited -or ($null -ne $tunnelProcess -and $tunnelProcess.HasExited)) { throw 'PORTABLE_OWNED_PROCESS_EXITED' }
      Start-Sleep -Seconds 2
    }
  } finally {
    $cleanupFailed = $false
    try {
      for ($index = $started.Count - 1; $index -ge 0; $index--) {
        try { Stop-PortableOwnedProcess $started[$index] }
        catch { $cleanupFailed = $true; Write-Warning ('PORTABLE_OWNED_PROCESS_CLEANUP_FAILED PID=' + [int]$started[$index].pid) }
      }
    } finally {
      if ($ownsMutex) { $mutex.ReleaseMutex() }
      $mutex.Dispose()
      if (Test-Path -LiteralPath (Join-Path $loaded.dataRoot 'stop.request')) { Remove-Item -LiteralPath (Join-Path $loaded.dataRoot 'stop.request') -Force -ErrorAction SilentlyContinue }
    }
    if ($cleanupFailed) { throw 'PORTABLE_RUNTIME_CLEANUP_INCOMPLETE; inspect only the listed Nodaris-owned process IDs before recovery' }
  }
}

switch ($Command) {
  configure {
    if (-not [Environment]::UserInteractive) { throw 'PORTABLE_CONFIGURATION_REQUIRES_INTERACTIVE_USER' }
    $roots = [Collections.Generic.List[string]]::new()
    while ($true) {
      $selected = Read-Host 'Caminho absoluto de um projeto que você autoriza para leitura (vazio encerra)'
      if ([string]::IsNullOrWhiteSpace($selected)) { break }
      $roots.Add((Test-NodarisPortableProjectRoot -Path $selected))
      if ((Read-Host 'Adicionar outro projeto? (s/N)') -notmatch '^(?i:s|sim)$') { break }
    }
    Write-Output ('ESCOPO: ' + $(if($roots.Count){$roots -join '; '}else{'nenhum projeto (allowlist vazia)'}))
    $confirmation = Read-Host 'Digite CONFIGURE NODARIS neste computador para gerar identidade e credencial locais'
    if ($confirmation -cne 'CONFIGURE NODARIS') { throw 'PORTABLE_LOCAL_APPROVAL_DENIED' }
    $result = New-NodarisPortableConfig -ApprovedRoots $roots.ToArray()
    $rootCount = @($result.config.repositoryRoots).Count
    Write-Output ('PORTABLE_CONFIG=CREATED MACHINE_ID=' + $result.machineId + ' ROOT_COUNT=' + $rootCount + ' WRITES=OFF')
  }
  doctor {
    $loaded = Read-PortableConfig
    $tunnel = Read-NodarisPortableTunnelConfig
    $node = Get-PortableNodePath
    $deps = Test-Path -LiteralPath (Join-Path $repoRoot 'node_modules\tsx\dist\cli.mjs') -PathType Leaf
    $ports = @(3333,3334 | ForEach-Object { [pscustomobject]@{ port=$_; owner=Get-PortableListenerOwner $_ } })
    [pscustomobject]@{ status=if($deps -and @($ports|Where-Object owner -ne 0).Count -eq 0){'READY'}else{'BLOCKED'}; machineId=$loaded.config.machineId; rootCount=@($loaded.config.repositoryRoots).Count; node=$node; dependencies=$deps; ports=$ports; tunnel=if($tunnel){if($tunnel.config.enabled){'CONFIGURED_ENABLED'}else{'CONFIGURED_DISABLED'}}else{'NOT_CONFIGURED'}; tunnelDoctor=if($tunnel -and $tunnel.config.enabled){Invoke-PortableTunnelDoctor $tunnel}else{$null}; memory='OFF'; memoryWrite='OFF'; projectWrite='OFF' } | ConvertTo-Json -Depth 4
  }
  task-install {
    $null = Read-PortableConfig
    if (Get-PortableTask) { throw 'PORTABLE_TASK_ALREADY_EXISTS; inspect it before taking action' }
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' + $scriptPath + '" run'
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Output ('TAREFA=' + $taskName + ' USUARIO=' + $identity + ' ACAO=' + $powershell + ' ' + $arguments + ' ESTADO_INICIAL=DISABLED NIVEL=LIMITED')
    Confirm-PortableAction 'A tarefa de logon será criada desabilitada para este usuário e este clone.' 'INSTALL NODARIS TASK'
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $repoRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
    $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(2))
    $task = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Nodaris per-user loopback read-only Agent/Gateway.' -ErrorAction Stop
    Disable-ScheduledTask -TaskName $taskName | Out-Null
    if (-not (Test-PortableTaskIdentity (Get-PortableTask))) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; throw 'PORTABLE_TASK_IDENTITY_VALIDATION_FAILED' }
    Write-Output 'PORTABLE_TASK=REGISTERED_DISABLED MULTIPLE_INSTANCES=IGNORE_NEW RUNLEVEL=LIMITED'
  }
  tunnel-prepare-install {
    $null = Read-PortableConfig
    $target = Join-Path $env:LOCALAPPDATA 'Nodaris\tunnel-client'
    Write-Output ('TUNNEL_INSTALL_ROOT=' + $target + ' ACL=PRIVATE OWNER_AND_SYSTEM ONLY')
    Confirm-PortableAction 'Será criado apenas o diretório privado do cliente oficial; nenhum download ou túnel será iniciado.' 'PREPARE NODARIS TUNNEL INSTALL'
    $root = Initialize-NodarisPortableTunnelInstallRoot
    Write-Output ('PORTABLE_TUNNEL_INSTALL_ROOT=READY PATH=' + $root)
  }
  tunnel-configure {
    if (-not [Environment]::UserInteractive) { throw 'PORTABLE_TUNNEL_CONFIGURATION_REQUIRES_INTERACTIVE_USER' }
    $null = Read-PortableConfig
    if ([string]::IsNullOrWhiteSpace($TunnelExecutable)) { $TunnelExecutable = Read-Host 'Caminho absoluto do tunnel-client.exe oficial já instalado e validado por checksum' }
    if ([string]::IsNullOrWhiteSpace($TunnelId)) { $TunnelId = Read-Host 'Tunnel ID criado na organização/workspace próprios do operador' }
    $secure = Read-Host 'Runtime API key (entrada protegida; chave administrativa não é aceita)' -AsSecureString
    $pointer = [IntPtr]::Zero
    $runtimeKey = $null
    try {
      $pointer = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secure)
      $runtimeKey = [Runtime.InteropServices.Marshal]::PtrToStringUni($pointer)
      $exe = [IO.Path]::GetFullPath($TunnelExecutable)
      Write-Output ('TUNNEL_ID=' + $TunnelId + ' EXECUTABLE=' + $exe + ' PROFILE=%LOCALAPPDATA%\Nodaris\portable\tunnel-client.yaml SECRET_STORAGE=DPAPI_CURRENT_USER MCP=127.0.0.1:3333 AUTH=LOCAL_BEARER')
      if ((Read-Host 'Digite CONFIGURE NODARIS TUNNEL para armazenar a chave DPAPI e o perfil restrito') -cne 'CONFIGURE NODARIS TUNNEL') { throw 'PORTABLE_LOCAL_APPROVAL_DENIED' }
      $result = New-NodarisPortableTunnelConfig -Executable $exe -TunnelId $TunnelId -RuntimeKey $runtimeKey
      if (-not (Test-NodarisPortablePrivateAcl -Path $result.profilePath)) { throw 'PORTABLE_TUNNEL_PROFILE_ACL_INVALID' }
      $loadedTunnel = Read-NodarisPortableTunnelConfig
      if (-not (Invoke-PortableTunnelDoctor $loadedTunnel)) { throw 'PORTABLE_TUNNEL_DOCTOR_FAILED' }
      Write-Output 'PORTABLE_TUNNEL=CONFIGURED_DISABLED DOCTOR=PASS SECRET=DPAPI WRITES=OFF'
    } finally {
      if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($pointer) }
      $secure.Dispose(); $runtimeKey = $null
    }
  }
  tunnel-enable {
    $tunnel = Read-NodarisPortableTunnelConfig
    if ($null -eq $tunnel -or -not (Invoke-PortableTunnelDoctor $tunnel)) { throw 'PORTABLE_TUNNEL_DOCTOR_FAILED' }
    Confirm-PortableAction ('O supervisor portátil iniciará o tunnel-client validado com tunnelId=' + $tunnel.tunnelId + ' e somente MCP http://127.0.0.1:3333/mcp.') 'ENABLE NODARIS TUNNEL'
    Set-NodarisPortableTunnelEnabled -Enabled $true
    Write-Output 'PORTABLE_TUNNEL=ENABLED; next approved runtime start will supervise tunnel-client'
  }
  tunnel-disable {
    $tunnel = Read-NodarisPortableTunnelConfig
    if ($null -eq $tunnel) { throw 'PORTABLE_TUNNEL_NOT_CONFIGURED' }
    Confirm-PortableAction ('O próximo início do supervisor não conectará o túnel. Perfil e chave DPAPI serão preservados. tunnelId=' + $tunnel.tunnelId) 'DISABLE NODARIS TUNNEL'
    Set-NodarisPortableTunnelEnabled -Enabled $false
    Write-Output 'PORTABLE_TUNNEL=DISABLED CONFIG_PRESERVED=YES'
  }
  task-enable {
    $task = Get-PortableTask
    if (-not (Test-PortableTaskIdentity $task)) { throw 'PORTABLE_TASK_IDENTITY_MISMATCH' }
    if ((Read-Host 'Digite ENABLE NODARIS TASK para habilitar esta tarefa local') -cne 'ENABLE NODARIS TASK') { throw 'PORTABLE_LOCAL_APPROVAL_DENIED' }
    Enable-ScheduledTask -TaskName $taskName | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Output 'PORTABLE_TASK=ENABLED START_REQUESTED'
  }
  task-disable {
    $task = Get-PortableTask
    if (-not (Test-PortableTaskIdentity $task)) { throw 'PORTABLE_TASK_IDENTITY_MISMATCH' }
    Confirm-PortableAction ('A tarefa de logon será desabilitada; a configuração local será preservada. Tarefa=' + $taskName) 'DISABLE NODARIS TASK'
    Disable-ScheduledTask -TaskName $taskName | Out-Null
    Write-Output 'PORTABLE_TASK=DISABLED'
  }
  task-remove {
    $task = Get-PortableTask
    if (-not (Test-PortableTaskIdentity $task)) { throw 'PORTABLE_TASK_IDENTITY_MISMATCH' }
    Confirm-PortableAction ('A tarefa será removida; configuração local e credencial permanecerão. Tarefa=' + $taskName) 'REMOVE NODARIS TASK'
    Disable-ScheduledTask -TaskName $taskName | Out-Null
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output 'PORTABLE_TASK=REMOVED LOCAL_CONFIG_PRESERVED=YES'
  }
  start {
    $loaded = Read-PortableConfig
    $tunnel = Read-NodarisPortableTunnelConfig
    Confirm-PortableAction ('Agent e Gateway de leitura serão iniciados em 127.0.0.1 nas portas 3334/3333. Túnel=' + $(if($tunnel -and $tunnel.config.enabled){'habilitado e supervisionado'}else{'desligado'}) + '. Raízes=' + (@($loaded.config.repositoryRoots) -join '; ')) 'START NODARIS READ RUNTIME'
    $stop = Join-Path $loaded.dataRoot 'stop.request'
    if (Test-Path -LiteralPath $stop) { Remove-Item -LiteralPath $stop -Force }
    $task = Get-PortableTask
    if ($task) {
      if ($task.State -eq 'Disabled') { throw 'PORTABLE_TASK_DISABLED; approve task-enable first' }
      if (-not (Test-PortableTaskIdentity $task)) { throw 'PORTABLE_TASK_IDENTITY_MISMATCH' }
      Start-ScheduledTask -TaskName $taskName
    } else {
      Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',('"' + $scriptPath + '"'),'run') -WorkingDirectory $repoRoot -WindowStyle Hidden
    }
    Write-Output 'PORTABLE_START=REQUESTED'
  }
  stop {
    $loaded = Read-PortableConfig
    Confirm-PortableAction ('Será solicitado ao supervisor Nodaris identificado pelo mutex local que encerre apenas seus próprios processos.') 'STOP NODARIS READ RUNTIME'
    [IO.File]::WriteAllText((Join-Path $loaded.dataRoot 'stop.request'), [DateTime]::UtcNow.ToString('o'), [Text.UTF8Encoding]::new($false))
    Write-Output 'PORTABLE_STOP=REQUESTED; only the owned supervisor observes this marker.'
  }
  status {
    $task = Get-PortableTask
    $loaded = if (Test-Path -LiteralPath (Join-Path (Get-NodarisPortableDataRoot) 'runtime.json')) { Read-PortableConfig } else { $null }
    $tunnel = if ($loaded) { Read-NodarisPortableTunnelConfig } else { $null }
    [pscustomobject]@{ configured=($null -ne $loaded); machineId=if($loaded){$loaded.config.machineId}else{$null}; task=if($task){[string]$task.State}else{'ABSENT'}; taskIdentityValid=if($task){Test-PortableTaskIdentity $task}else{$false}; ports=@(3333,3334,3335|ForEach-Object{[pscustomobject]@{port=$_;owner=Get-PortableListenerOwner $_}}); tunnel=if($tunnel){if($tunnel.config.enabled){'ENABLED'}else{'DISABLED'}}else{'NOT_CONFIGURED'}; writes='OFF' } | ConvertTo-Json -Depth 4
  }
  run { Start-PortableRuntime }
}
