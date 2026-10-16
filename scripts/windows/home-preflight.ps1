<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('inspect', 'plan', 'validate')]
  [string]$Mode = 'inspect',
  [string]$TargetPath
)

$ErrorActionPreference = 'Stop'

function New-HomeCheck {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][ValidateSet('PASS', 'BLOCKED', 'INCONCLUSIVE', 'NOT_CHECKED')][string]$Status,
    [Parameter(Mandatory = $true)][string]$Code,
    [object]$Value = $null
  )
  $check = [ordered]@{ name = $Name; status = $Status; code = $Code }
  if ($null -ne $Value) { $check.value = $Value }
  return [pscustomobject]$check
}

function Get-HomeOverallStatus {
  param([object[]]$Checks)
  if (@($Checks | Where-Object status -eq 'BLOCKED').Count -gt 0) { return 'BLOCKED' }
  if (@($Checks | Where-Object status -ne 'PASS').Count -gt 0) { return 'INCONCLUSIVE' }
  return 'PASS'
}

function Get-HomePlan {
  param([Parameter(Mandatory = $true)]$Report)
  $allowed = $Report.overallStatus -eq 'PASS'
  return [pscustomobject]@{
    installationAllowed = $false
    readiness = if ($allowed) { 'READY_FOR_SEPARATE_APPROVAL' } else { 'BLOCKED_OR_INCOMPLETE' }
    executionPerformed = $false
    steps = @(
      'Obter checkout versionado e verificar integridade/lockfile',
      'Instalar dependências fixadas em escopo do usuário após aprovação separada',
      'Criar identidade, Bearer e configuração privada novos no computador de destino',
      'Solicitar aprovação explícita de uma única raiz de projeto',
      'Provisionar túnel e runtime key independentes pelo fluxo oficial',
      'Validar listeners loopback, health autenticado e readiness',
      'Validar chamadas ChatGPT e rollback em janela autorizada'
    )
    rollback = @(
      'Parar a validação se identidade, processo ou proprietário de porta forem inconclusivos',
      'Não remover tarefa, credenciais, vault ou estado preexistentes',
      'Remover somente artefatos que um futuro piloto comprovar ter criado',
      'Exigir autorização separada antes de desabilitar tarefa ou encerrar processo'
    )
    note = 'Este plano não instala, provisiona credenciais, cria tarefas nem altera serviços.'
  }
}

function New-HomeReport {
  param([Parameter(Mandatory = $true)][object[]]$Checks)
  $overall = Get-HomeOverallStatus $Checks
  return [pscustomobject]@{
    schemaVersion = 1
    overallStatus = $overall
    checks = @($Checks)
    effectsPerformed = $false
    privateFileContentsRead = $false
  }
}

function Test-PathFeatures {
  param([Parameter(Mandatory = $true)][string]$Path)
  $absolute = $false
  $spaces = $false
  $unicode = $false
  $nonDefault = $false
  try {
    $absolute = [IO.Path]::IsPathRooted($Path)
    $spaces = $Path.Contains(' ')
    $unicode = $Path -match '[^\x00-\x7F]'
    $defaultRoot = Join-Path $env:LOCALAPPDATA 'Nodaris'
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $default = [IO.Path]::GetFullPath($defaultRoot).TrimEnd('\')
    $nonDefault = -not $full.Equals($default, [StringComparison]::OrdinalIgnoreCase)
  } catch { }
  return [pscustomobject]@{ absolute = $absolute; containsSpaces = $spaces; containsUnicode = $unicode; nonDefault = $nonDefault }
}

function Get-HomePathPresence {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return [pscustomobject]@{ status = 'present'; item = $item }
  } catch [System.Management.Automation.ItemNotFoundException] {
    return [pscustomobject]@{ status = 'absent'; item = $null }
  } catch [System.IO.FileNotFoundException] {
    return [pscustomobject]@{ status = 'absent'; item = $null }
  } catch [System.IO.DirectoryNotFoundException] {
    return [pscustomobject]@{ status = 'absent'; item = $null }
  } catch {
    return [pscustomobject]@{ status = 'inconclusive'; item = $null }
  }
}

function Get-ProcessClassification {
  param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$CanonicalTarget,
    [int]$Depth = 0
  )
  try {
    $record = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
    if ($null -eq $record) { return [pscustomobject]@{ kind = 'inconclusive'; identity = 'inconclusive'; id = $ProcessId } }
    $owner = Invoke-CimMethod -InputObject $record -MethodName GetOwnerSid -ErrorAction Stop
    if ($null -eq $owner -or [int]$owner.ReturnValue -ne 0 -or [string]::IsNullOrWhiteSpace([string]$owner.Sid) -or
      [string]::IsNullOrWhiteSpace([string]$record.ExecutablePath) -or $null -eq $record.CreationDate) {
      return [pscustomobject]@{ kind = 'inconclusive'; identity = 'inconclusive'; id = $ProcessId }
    }
    $commandLine = [string]$record.CommandLine
    $image = [string]$record.ExecutablePath
    $processName = [string]$record.Name
    $nodaris = $false
    if ($processName -ieq 'tunnel-client.exe' -and $image -match '(?i)\\Nodaris\\tunnel-client\\') { $nodaris = $true }
    if ($processName -ieq 'powershell.exe' -and $commandLine -match '(?i)supervisor\.ps1') { $nodaris = $true }
    if ($processName -ieq 'node.exe' -and $commandLine -match '(?i)apps[\\/]((agent)|(gateway))[\\/]src[\\/]index\.ts') { $nodaris = $true }
    if (-not $nodaris) { return [pscustomobject]@{ kind = 'other_process'; identity = 'confirmed'; id = $ProcessId } }
    $same = $false
    if (-not [string]::IsNullOrWhiteSpace($CanonicalTarget)) {
      $same = $commandLine.IndexOf($CanonicalTarget, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $image.StartsWith($CanonicalTarget.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
    }
    if (-not $same -and $nodaris -and $processName -ieq 'tunnel-client.exe' -and $Depth -lt 4 -and
      [int]$record.ParentProcessId -gt 0) {
      $parent = Get-ProcessClassification -ProcessId ([int]$record.ParentProcessId) `
        -CanonicalTarget $CanonicalTarget -Depth ($Depth + 1)
      $same = $parent.kind -eq 'nodaris_selected_install'
    }
    return [pscustomobject]@{
      kind = if ($same) { 'nodaris_selected_install' } else { 'nodaris_other_install' }
      identity = 'confirmed'
      id = $ProcessId
    }
  } catch {
    return [pscustomobject]@{ kind = 'inconclusive'; identity = 'inconclusive'; id = $ProcessId }
  }
}

function Get-LocalHomeChecks {
  param([string]$SelectedPath)
  $checks = [Collections.Generic.List[object]]::new()

  $osVersion = [Environment]::OSVersion.Version
  $osSupported = $env:OS -eq 'Windows_NT' -and $osVersion.Major -ge 10 -and [Environment]::Is64BitOperatingSystem
  $checks.Add((New-HomeCheck 'windows' $(if ($osSupported) { 'PASS' } else { 'BLOCKED' }) `
    $(if ($osSupported) { 'WINDOWS_SUPPORTED' } else { 'WINDOWS_UNSUPPORTED' }) `
    ([pscustomobject]@{ version = $osVersion.ToString(); architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' } })))

  foreach ($tool in @(@{ name = 'node'; pattern = '^v?(\d+)\.'; minimum = 22; maximum = 25 }, @{ name = 'pnpm'; pattern = '^(\d+)\.'; minimum = 12; maximum = 13 })) {
    try {
      $command = Get-Command $tool.name -CommandType Application -ErrorAction Stop | Select-Object -First 1
      $versionOutput = @(& $command.Source --version 2>$null)
      $version = ([string]$versionOutput[0]).Trim()
      $match = [regex]::Match($version, $tool.pattern)
      if (-not $match.Success) {
        $checks.Add((New-HomeCheck $tool.name 'INCONCLUSIVE' ($tool.name.ToUpperInvariant() + '_VERSION_UNREADABLE')))
        continue
      }
      $major = [int]$match.Groups[1].Value
      $supported = $major -ge $tool.minimum -and $major -lt $tool.maximum
      $checks.Add((New-HomeCheck $tool.name $(if ($supported) { 'PASS' } else { 'BLOCKED' }) `
        $(if ($supported) { $tool.name.ToUpperInvariant() + '_SUPPORTED' } else { $tool.name.ToUpperInvariant() + '_UNSUPPORTED' }) $version))
    } catch {
      $checks.Add((New-HomeCheck $tool.name 'BLOCKED' ($tool.name.ToUpperInvariant() + '_MISSING')))
    }
  }

  $canonicalTarget = ''
  $targetExists = $false
  $targetReadable = $false
  $isCheckout = $false
  $gitOkay = $false
  $dirtyCount = $null
  $features = [pscustomobject]@{ absolute = $false; containsSpaces = $false; containsUnicode = $false; nonDefault = $false }
  if ([string]::IsNullOrWhiteSpace($SelectedPath)) {
    $checks.Add((New-HomeCheck 'selected_directory' 'NOT_CHECKED' 'TARGET_PATH_NOT_SUPPLIED'))
  } else {
    $features = Test-PathFeatures $SelectedPath
    try {
      if ($features.absolute) { $canonicalTarget = [IO.Path]::GetFullPath($SelectedPath) }
      $targetExists = $features.absolute -and (Test-Path -LiteralPath $canonicalTarget -PathType Container)
      if ($targetExists) {
        $null = Get-ChildItem -LiteralPath $canonicalTarget -Force -ErrorAction Stop | Select-Object -First 1
        $targetReadable = $true
      }
    } catch { $targetReadable = $false }
    $checks.Add((New-HomeCheck 'selected_directory' $(if (-not $features.absolute -or -not $targetExists) { 'BLOCKED' } elseif ($targetReadable) { 'PASS' } else { 'INCONCLUSIVE' }) `
      $(if (-not $features.absolute) { 'TARGET_PATH_NOT_ABSOLUTE' } elseif (-not $targetExists) { 'TARGET_DIRECTORY_MISSING' } elseif ($targetReadable) { 'TARGET_DIRECTORY_READABLE' } else { 'TARGET_READ_ACCESS_UNCONFIRMED' }) $features))
    if ($targetExists -and $targetReadable) {
      $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($null -ne $gitCommand) {
        $oldOptionalLocks = $env:GIT_OPTIONAL_LOCKS
        try {
          $env:GIT_OPTIONAL_LOCKS = '0'
          $repoResult = @(& $gitCommand.Source -C $canonicalTarget rev-parse --is-inside-work-tree 2>$null)
          $gitOkay = $LASTEXITCODE -eq 0 -and [string]$repoResult[0] -eq 'true' -and
            (Test-Path -LiteralPath (Join-Path $canonicalTarget 'package.json') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $canonicalTarget 'pnpm-lock.yaml') -PathType Leaf)
          if ($gitOkay) {
            $branchOutput = @(& $gitCommand.Source -C $canonicalTarget branch --show-current 2>$null)
            $branchOkay = $LASTEXITCODE -eq 0 -and [string]$branchOutput[0] -eq 'main'
            $statusOutput = @(& $gitCommand.Source -C $canonicalTarget status --porcelain --untracked-files=normal 2>$null)
            if ($LASTEXITCODE -eq 0) { $dirtyCount = @($statusOutput | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count }
            if (-not $branchOkay -or $null -eq $dirtyCount -or $dirtyCount -gt 0) { $gitOkay = $false }
          }
        } catch { $gitOkay = $false } finally {
          if ($null -eq $oldOptionalLocks) { Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue }
          else { $env:GIT_OPTIONAL_LOCKS = $oldOptionalLocks }
        }
      }
      $isCheckout = $gitOkay
      $checks.Add((New-HomeCheck 'repository' $(if (-not $gitOkay) { 'BLOCKED' } else { 'PASS' }) `
        $(if ($gitOkay) { 'GIT_MAIN_CLEAN_LOCKED_CHECKOUT' } else { 'GIT_CHECKOUT_INVALID_DIRTY_OR_UNAVAILABLE' }) `
        ([pscustomobject]@{ dirtyEntryCount = $dirtyCount })))
    } else {
      $checks.Add((New-HomeCheck 'repository' 'INCONCLUSIVE' 'REPOSITORY_NOT_INSPECTED'))
    }
  }

  $freeMiB = $null
  try {
    if ($targetExists) {
      $driveRoot = [IO.Path]::GetPathRoot($canonicalTarget)
      $drive = [IO.DriveInfo]::new($driveRoot)
      $freeMiB = [long][Math]::Floor($drive.AvailableFreeSpace / 1MB)
      $checks.Add((New-HomeCheck 'disk_space' $(if ($freeMiB -ge 2048) { 'PASS' } else { 'BLOCKED' }) `
        $(if ($freeMiB -ge 2048) { 'DISK_SPACE_SUFFICIENT' } else { 'DISK_SPACE_LOW' }) $freeMiB))
    } else { $checks.Add((New-HomeCheck 'disk_space' 'NOT_CHECKED' 'TARGET_DRIVE_UNKNOWN')) }
  } catch { $checks.Add((New-HomeCheck 'disk_space' 'INCONCLUSIVE' 'DISK_SPACE_UNAVAILABLE')) }

  $isAdmin = $null
  try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { }
  $checks.Add((New-HomeCheck 'non_admin_context' $(if ($null -eq $isAdmin) { 'INCONCLUSIVE' } elseif ($isAdmin) { 'BLOCKED' } else { 'PASS' }) `
    $(if ($null -eq $isAdmin) { 'ADMIN_STATUS_UNAVAILABLE' } elseif ($isAdmin) { 'ADMIN_CONTEXT_NOT_REQUIRED' } else { 'STANDARD_USER_CONTEXT' })))
  $checks.Add((New-HomeCheck 'user_scope_write_access' 'NOT_CHECKED' 'NO_WRITE_PROBE_PERFORMED'))

  $taskDisposition = 'absent'
  try {
    $nodarisTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -match '(?i)nodaris' })
    if ($nodarisTasks.Count -gt 0) {
      $exactTask = @($nodarisTasks | Where-Object { $_.TaskName -eq 'Nodaris User Session' })
      if ($exactTask.Count -eq 0) { $taskDisposition = 'other' }
      else {
        $actions = @($exactTask[0].Actions | ForEach-Object { [string]$_.Execute + ' ' + [string]$_.Arguments }) -join ' '
        if ($canonicalTarget -and $actions.IndexOf($canonicalTarget, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $taskDisposition = 'same' }
        else { $taskDisposition = 'other' }
      }
    }
    $checks.Add((New-HomeCheck 'scheduled_tasks' $(if ($taskDisposition -eq 'absent') { 'PASS' } else { 'BLOCKED' }) `
      $(switch ($taskDisposition) { absent { 'NO_NODARIS_TASK' } same { 'TASK_FOR_SELECTED_INSTALLATION_EXISTS' } other { 'NODARIS_TASK_CONFLICT' } })))
  } catch { $checks.Add((New-HomeCheck 'scheduled_tasks' 'INCONCLUSIVE' 'TASK_QUERY_UNAVAILABLE')) }

  $mutexState = 'absent'
  try {
    $mutex = [Threading.Mutex]::OpenExisting('LocalNodaris-M01-Supervisor')
    $mutex.Dispose()
    $mutexState = 'busy'
  } catch [Threading.WaitHandleCannotBeOpenedException] { $mutexState = 'absent' }
  catch { $mutexState = 'inconclusive' }
  $checks.Add((New-HomeCheck 'supervisor_mutex' $(if ($mutexState -eq 'absent') { 'PASS' } elseif ($mutexState -eq 'busy') { 'BLOCKED' } else { 'INCONCLUSIVE' }) `
    $(switch ($mutexState) { absent { 'MUTEX_NOT_PRESENT' } busy { 'MUTEX_PRESENT_OWNER_UNCONFIRMED' } inconclusive { 'MUTEX_QUERY_UNAVAILABLE' } })))

  $processMatches = [Collections.Generic.List[object]]::new()
  $processScanStatus = 'PASS'
  try {
    $candidates = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='node.exe' OR Name='powershell.exe' OR Name='tunnel-client.exe'" -ErrorAction Stop)
    foreach ($candidate in $candidates) {
      $classification = Get-ProcessClassification -ProcessId ([int]$candidate.ProcessId) -CanonicalTarget $canonicalTarget
      if ($classification.kind -ne 'other_process') { $processMatches.Add($classification) }
    }
    if (@($processMatches | Where-Object identity -eq 'inconclusive').Count -gt 0) { $processScanStatus = 'INCONCLUSIVE' }
    elseif ($processMatches.Count -gt 0) { $processScanStatus = 'BLOCKED' }
  } catch { $processScanStatus = 'INCONCLUSIVE' }
  $processCode = 'NO_NODARIS_PROCESSES'
  if ($processScanStatus -eq 'BLOCKED') {
    if (@($processMatches | Where-Object kind -eq 'nodaris_selected_install').Count -gt 0) { $processCode = 'PROCESS_FOR_SELECTED_INSTALLATION_EXISTS' }
    else { $processCode = 'NODARIS_PROCESS_OTHER_INSTALLATION' }
  } elseif ($processScanStatus -eq 'INCONCLUSIVE') { $processCode = 'PROCESS_IDENTITY_UNCONFIRMED' }
  $checks.Add((New-HomeCheck 'process_identity' $processScanStatus $processCode ([pscustomobject]@{ identifiedNodarisProcessCount = $processMatches.Count })))

  foreach ($port in @(3333, 3334, 8080)) {
    try {
      $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction Stop)
      if ($listeners.Count -eq 0) {
        $checks.Add((New-HomeCheck ('port_' + $port) 'PASS' 'PORT_FREE' ([pscustomobject]@{ binding = 'none' })))
      } else {
        $owners = [Collections.Generic.List[object]]::new()
        $nonLoopback = $false
        $bindingUnknown = $false
        foreach ($listener in $listeners) {
          $owners.Add((Get-ProcessClassification -ProcessId ([int]$listener.OwningProcess) -CanonicalTarget $canonicalTarget))
          $address = [string]$listener.LocalAddress
          if ($address -match '^(?i:127\.)' -or $address -eq '::1' -or $address -like '::ffff:127.*') { }
          elseif ([string]::IsNullOrWhiteSpace($address)) { $bindingUnknown = $true }
          else { $nonLoopback = $true }
        }
        $unknown = @($owners | Where-Object identity -eq 'inconclusive').Count -gt 0
        $binding = if ($bindingUnknown) { 'unconfirmed' } elseif ($nonLoopback) { 'non_loopback' } else { 'loopback' }
        $bindingValue = [pscustomobject]@{ binding = $binding }
        if ($unknown -or $bindingUnknown) { $checks.Add((New-HomeCheck ('port_' + $port) 'INCONCLUSIVE' 'PORT_OWNER_OR_BIND_IDENTITY_UNCONFIRMED' $bindingValue)) }
        else {
          $same = @($owners | Where-Object kind -eq 'nodaris_selected_install').Count -gt 0
          $otherNodaris = @($owners | Where-Object kind -eq 'nodaris_other_install').Count -gt 0
          if ($nonLoopback) { $checks.Add((New-HomeCheck ('port_' + $port) 'BLOCKED' 'PORT_LISTENER_NON_LOOPBACK_IDENTIFIED' $bindingValue)) }
          elseif ($same) { $checks.Add((New-HomeCheck ('port_' + $port) 'BLOCKED' 'PORT_OWNED_BY_SELECTED_INSTALLATION' $bindingValue)) }
          elseif ($otherNodaris) { $checks.Add((New-HomeCheck ('port_' + $port) 'BLOCKED' 'PORT_OWNED_BY_OTHER_NODARIS_INSTALLATION' $bindingValue)) }
          else { $checks.Add((New-HomeCheck ('port_' + $port) 'BLOCKED' 'PORT_OWNED_BY_IDENTIFIED_OTHER_PROCESS' $bindingValue)) }
        }
      }
    } catch { $checks.Add((New-HomeCheck ('port_' + $port) 'INCONCLUSIVE' 'PORT_OWNER_QUERY_UNAVAILABLE')) }
  }

  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $checks.Add((New-HomeCheck 'local_application_data' 'INCONCLUSIVE' 'LOCALAPPDATA_UNAVAILABLE'))
    $localRoot = $null
  } else { $localRoot = Join-Path $env:LOCALAPPDATA 'Nodaris' }
  $tunnelExe = if ($null -eq $localRoot) { $null } else { Join-Path $localRoot 'tunnel-client\v0.0.15\tunnel-client.exe' }
  $tunnelProfile = if ($null -eq $localRoot) { $null } else { Join-Path $localRoot 'tunnel-client\profiles\nodaris-local.yaml' }
  $exePresence = if ($null -eq $tunnelExe) { [pscustomobject]@{ status = 'inconclusive'; item = $null } } else { Get-HomePathPresence $tunnelExe }
  $tunnelCommand = Get-Command tunnel-client.exe -CommandType Application -ErrorAction SilentlyContinue
  if ($exePresence.status -eq 'absent' -and $null -ne $tunnelCommand) { $exePresence.status = 'present' }
  $checks.Add((New-HomeCheck 'tunnel_client_executable' $(switch ($exePresence.status) { present { 'PASS' } absent { 'BLOCKED' } default { 'INCONCLUSIVE' } }) `
    $(switch ($exePresence.status) { present { 'TUNNEL_CLIENT_AVAILABLE' } absent { 'TUNNEL_CLIENT_MISSING' } default { 'TUNNEL_CLIENT_PRESENCE_UNCONFIRMED' } })))
  $profilePresence = if ($null -eq $tunnelProfile) { [pscustomobject]@{ status = 'inconclusive'; item = $null } } else { Get-HomePathPresence $tunnelProfile }
  $checks.Add((New-HomeCheck 'tunnel_profile' $(switch ($profilePresence.status) { absent { 'PASS' } default { 'INCONCLUSIVE' } }) `
    $(switch ($profilePresence.status) { absent { 'PROFILE_ABSENT' } present { 'PROFILE_EXISTS_REQUIRES_INDEPENDENT_REVIEW' } default { 'PROFILE_PRESENCE_UNCONFIRMED' } })))
  $checks.Add((New-HomeCheck 'remote_control_plane_readiness' 'NOT_CHECKED' 'NO_TUNNEL_OR_NETWORK_PROBE_PERFORMED'))

  $rootsFile = if ($null -eq $localRoot) { $null } else { Join-Path $localRoot 'config\allowed-roots.json' }
  $rootsPresence = if ($null -eq $rootsFile) { [pscustomobject]@{ status = 'inconclusive'; item = $null } } else { Get-HomePathPresence $rootsFile }
  $checks.Add((New-HomeCheck 'local_roots_configuration' $(switch ($rootsPresence.status) { absent { 'PASS' } present { 'BLOCKED' } default { 'INCONCLUSIVE' } }) `
    $(switch ($rootsPresence.status) { absent { 'ROOT_CONFIGURATION_ABSENT_ALLOWLIST_EMPTY' } present { 'ROOT_CONFIGURATION_PRESENT_CONTENT_NOT_READ' } default { 'ROOT_CONFIGURATION_PRESENCE_UNCONFIRMED' } })))
  $privatePaths = if ($null -eq $localRoot) { $null } else { [ordered]@{
    bearer = Join-Path $localRoot 'gateway-token.txt'
    runtimeKey = Join-Path $localRoot 'secrets\control-plane-api-key.txt'
    tunnelProfile = $tunnelProfile
    supervisorState = Join-Path $localRoot 'supervisor\state.json'
    diagnostics = Join-Path $localRoot 'supervisor\startup-events.jsonl'
  } }
  $privatePresence = [ordered]@{}
  if ($null -eq $privatePaths) { foreach ($key in @('bearer', 'runtimeKey', 'tunnelProfile', 'supervisorState', 'diagnostics')) { $privatePresence[$key] = 'inconclusive' } }
  else { foreach ($key in $privatePaths.Keys) { $privatePresence[$key] = (Get-HomePathPresence $privatePaths[$key]).status } }
  $hasPrivateMaterial = @($privatePresence.Values | Where-Object { $_ -eq 'present' }).Count -gt 0
  $privateStatusUnknown = @($privatePresence.Values | Where-Object { $_ -eq 'inconclusive' }).Count -gt 0
  $checks.Add((New-HomeCheck 'private_file_presence' $(if ($hasPrivateMaterial) { 'BLOCKED' } elseif ($privateStatusUnknown) { 'INCONCLUSIVE' } else { 'PASS' }) `
    $(if ($hasPrivateMaterial) { 'LOCAL_PRIVATE_DATA_EXISTS_DO_NOT_COPY' } elseif ($privateStatusUnknown) { 'PRIVATE_FILE_PRESENCE_UNCONFIRMED' } else { 'NO_LOCAL_PRIVATE_DATA_FOUND' }) $privatePresence))

  try {
    $readyPort = @($checks | Where-Object name -eq 'port_8080' | Select-Object -First 1)
    $hasTunnelProcess = @($processMatches | Where-Object { $_.kind -like 'nodaris_*' }).Count -gt 0
    if ($hasTunnelProcess -and $readyPort.Count -gt 0 -and $readyPort[0].status -eq 'BLOCKED') {
      $ready = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/readyz' -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
      $checks.Add((New-HomeCheck 'tunnel_local_readiness' $(if ([int]$ready.StatusCode -eq 200) { 'PASS' } else { 'BLOCKED' }) `
        $(if ([int]$ready.StatusCode -eq 200) { 'LOCAL_READYZ_OK_CONTROL_PLANE_NOT_PROVEN' } else { 'LOCAL_READYZ_FAILED' })))
    } else { $checks.Add((New-HomeCheck 'tunnel_local_readiness' 'NOT_CHECKED' 'NO_IDENTIFIED_LOCAL_TUNNEL')) }
  } catch { $checks.Add((New-HomeCheck 'tunnel_local_readiness' 'INCONCLUSIVE' 'LOCAL_READYZ_UNAVAILABLE')) }

  return $checks.ToArray()
}

function Invoke-NodarisHomePreflight {
  param(
    [string]$SelectedPath,
    [scriptblock]$Collector = { param($path) Get-LocalHomeChecks -SelectedPath $path }
  )
  try { $checks = @(& $Collector $SelectedPath) }
  catch { $checks = @((New-HomeCheck 'host_probe' 'INCONCLUSIVE' 'HOST_PROBE_FAILED')) }
  $report = New-HomeReport -Checks $checks
  return $report
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $report = Invoke-NodarisHomePreflight -SelectedPath $TargetPath
    if ($Mode -eq 'plan') {
      [pscustomobject]@{ report = $report; plan = (Get-HomePlan $report) } | ConvertTo-Json -Depth 8
    } elseif ($Mode -eq 'validate') {
      [pscustomobject]@{ status = $report.overallStatus; report = $report; effectsPerformed = $false } | ConvertTo-Json -Depth 8
      if ($report.overallStatus -ne 'PASS') { exit 2 }
    } else { $report | ConvertTo-Json -Depth 8 }
  } catch {
    [pscustomobject]@{
      schemaVersion = 1
      overallStatus = 'INCONCLUSIVE'
      checks = @((New-HomeCheck 'host_probe' 'INCONCLUSIVE' 'HOST_PROBE_FAILED'))
      effectsPerformed = $false
      privateFileContentsRead = $false
    } | ConvertTo-Json -Depth 8
    exit 2
  }
}
