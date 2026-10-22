# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

Set-StrictMode -Version Latest

function Get-NodarisPortableDataRoot {
  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or -not [IO.Path]::IsPathRooted($env:LOCALAPPDATA)) {
    throw 'PORTABLE_LOCALAPPDATA_UNAVAILABLE'
  }
  return [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Nodaris\portable'))
}

function Test-NodarisPortablePrivateAcl {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer -and -not $acl.AreAccessRulesProtected) { return $false }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $sid) { return $false }
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if ($rules.Count -ne 2) { return $false }
    $actual = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
    $expected = @($sid, 'S-1-5-18' | Sort-Object -Unique)
    if (($actual -join ',') -cne ($expected -join ',')) { return $false }
    foreach ($rule in $rules) {
      if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { return $false }
      if (($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne [Security.AccessControl.FileSystemRights]::FullControl) { return $false }
      if (-not $item.PSIsContainer -and -not $rule.IsInherited) { return $false }
    }
    return $true
  } catch { return $false }
}

function Set-NodarisPortablePrivateAcl {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-NodarisPortablePrivateAcl -Path $Path)) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner, 'FullControl', $inherit, 'None', 'Allow'))
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($system, 'FullControl', $inherit, 'None', 'Allow'))
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
  }
  if (-not (Test-NodarisPortablePrivateAcl -Path $Path)) { throw 'PORTABLE_PRIVATE_ACL_INVALID' }
}

function Initialize-NodarisPortableDataRoot {
  $root = Get-NodarisPortableDataRoot
  $parent = Split-Path -Parent $root
  $local = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
  if (-not [string]::Equals((Split-Path -Parent $parent).TrimEnd('\'), $local, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'PORTABLE_DATA_ROOT_OUTSIDE_LOCALAPPDATA'
  }
  if (-not (Test-Path -LiteralPath $local -PathType Container)) { throw 'PORTABLE_LOCALAPPDATA_MISSING' }
  $localDrive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($local))
  if ($localDrive.DriveFormat -ne 'NTFS') { throw 'PORTABLE_LOCALAPPDATA_NOT_NTFS' }
  $localCurrent = [IO.Path]::GetPathRoot($local)
  foreach ($segment in @($local.Substring($localCurrent.Length).Split('\') | Where-Object { $_ })) {
    $localCurrent = Join-Path $localCurrent $segment
    $localItem = Get-Item -LiteralPath $localCurrent -Force -ErrorAction Stop
    if (($localItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_LOCALAPPDATA_REPARSE_POINT' }
  }
  foreach ($path in @($parent, $root)) {
    if (Test-Path -LiteralPath $path) {
      $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
      if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_DATA_PATH_INVALID' }
    } else {
      [void][IO.Directory]::CreateDirectory($path)
      if ($path -eq $root) { Set-NodarisPortablePrivateAcl -Path $root }
    }
  }
  if (-not (Test-NodarisPortablePrivateAcl -Path $root)) { throw 'PORTABLE_PRIVATE_ACL_INVALID' }
  return $root
}

function Test-NodarisPortableProjectRoot {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not [IO.Path]::IsPathRooted($Path)) { throw 'PORTABLE_PROJECT_PATH_NOT_ABSOLUTE' }
  if ($Path.Contains(';')) { throw 'PORTABLE_PROJECT_PATH_SEPARATOR_UNSUPPORTED' }
  $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
  $driveRoot = [IO.Path]::GetPathRoot($full).TrimEnd('\')
  if ([string]::Equals($full, $driveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'PORTABLE_PROJECT_ROOT_TOO_BROAD' }
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw 'PORTABLE_PROJECT_PATH_MISSING' }
  $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))
  if ($drive.DriveFormat -ne 'NTFS') { throw 'PORTABLE_PROJECT_VOLUME_NOT_NTFS' }
  $current = [IO.Path]::GetPathRoot($full)
  foreach ($segment in @($full.Substring($current.Length).Split('\') | Where-Object { $_ })) {
    $current = Join-Path $current $segment
    $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_PROJECT_REPARSE_POINT' }
  }
  return $full
}

function Initialize-NodarisPortableTunnelInstallRoot {
  $local = [IO.Path]::GetFullPath($env:LOCALAPPDATA)
  $path = [IO.Path]::GetFullPath((Join-Path $local 'Nodaris\tunnel-client'))
  if (-not $path.StartsWith(($local.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'PORTABLE_TUNNEL_INSTALL_ROOT_INVALID' }
  $parent = Join-Path $local 'Nodaris'
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'PORTABLE_DATA_ROOT_NOT_INITIALIZED' }
  $parentItem = Get-Item -LiteralPath $parent -Force -ErrorAction Stop
  if (($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_TUNNEL_INSTALL_PARENT_REPARSE_POINT' }
  if (Test-Path -LiteralPath $path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_TUNNEL_INSTALL_ROOT_INVALID' }
    if (-not (Test-NodarisPortablePrivateAcl -Path $path)) { throw 'PORTABLE_TUNNEL_INSTALL_ROOT_NOT_PRIVATE' }
  } else {
    [void][IO.Directory]::CreateDirectory($path)
    Set-NodarisPortablePrivateAcl -Path $path
  }
  return $path
}

function New-NodarisPortableConfig {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ApprovedRoots)
  $roots = @($ApprovedRoots | ForEach-Object { Test-NodarisPortableProjectRoot -Path $_ } | Sort-Object -Unique)
  if ($roots.Count -ne $ApprovedRoots.Count) { throw 'PORTABLE_PROJECT_ALLOWLIST_DUPLICATE' }
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $raw = New-Object byte[] 48
  try {
    $rng.GetBytes($raw)
    $token = [Convert]::ToBase64String($raw)
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $entropy = [Text.Encoding]::UTF8.GetBytes('Nodaris.Portable.Runtime.v1')
    $protected = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($token), $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $root = Initialize-NodarisPortableDataRoot
    $configPath = Join-Path $root 'runtime.json'
    $tokenPath = Join-Path $root 'gateway-token.dpapi'
    if ((Test-Path -LiteralPath $configPath) -or (Test-Path -LiteralPath $tokenPath)) { throw 'PORTABLE_CONFIG_ALREADY_EXISTS' }
    $payload = [ordered]@{ schemaVersion = 1; machineId = ('machine-' + [guid]::NewGuid().ToString('N')); repositoryRoots = $roots; agentHost = '127.0.0.1'; agentPort = 3334; gatewayHost = '127.0.0.1'; gatewayPort = 3333; memoryReadEnabled = $false; memoryWriteEnabled = $false; projectWriteEnabled = $false; repositoryRegistryEnabled = $false; configuredAtUtc = [DateTime]::UtcNow.ToString('o') }
    $mac = New-NodarisPortableConfigMac -Payload (Get-NodarisPortableConfigPayload -Config $payload) -Token $token
    $config = [ordered]@{}; foreach ($key in $payload.Keys) { $config[$key] = $payload[$key] }; $config['configMac'] = $mac
    $json = $config | ConvertTo-Json -Depth 4
    $tmpJson = Join-Path $root ('runtime.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $tmpToken = Join-Path $root ('token.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $tokenMoved = $false
    $configMoved = $false
    try {
      [IO.File]::WriteAllText($tmpToken, [Convert]::ToBase64String($protected), [Text.UTF8Encoding]::new($false))
      [IO.File]::WriteAllText($tmpJson, $json, [Text.UTF8Encoding]::new($false))
      [IO.File]::Move($tmpToken, $tokenPath)
      $tokenMoved = $true
      [IO.File]::Move($tmpJson, $configPath)
      $configMoved = $true
      if (-not (Test-NodarisPortablePrivateAcl -Path $tokenPath) -or -not (Test-NodarisPortablePrivateAcl -Path $configPath)) { throw 'PORTABLE_CONFIG_FILE_ACL_INVALID' }
    } catch {
      Remove-Item -LiteralPath $tmpJson, $tmpToken -Force -ErrorAction SilentlyContinue
      if ($tokenMoved) { Remove-Item -LiteralPath $tokenPath -Force -ErrorAction SilentlyContinue }
      if ($configMoved) { Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue }
      throw
    }
    return [pscustomobject]@{ config = $config; configPath = $configPath; machineId = $config.machineId }
  } catch {
    throw
  } finally {
    $rng.Dispose()
    [Array]::Clear($raw, 0, $raw.Length)
    if ($null -ne $token) { $token = $null }
  }
}

function Read-NodarisPortableConfig {
  $root = Get-NodarisPortableDataRoot
  if (-not (Test-NodarisPortablePrivateAcl -Path $root)) { throw 'PORTABLE_PRIVATE_ACL_INVALID' }
  $configPath = Join-Path $root 'runtime.json'
  $tokenPath = Join-Path $root 'gateway-token.dpapi'
  foreach ($path in @($configPath, $tokenPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-NodarisPortablePrivateAcl -Path $path)) { throw 'PORTABLE_CONFIG_OR_TOKEN_INVALID' }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_CONFIG_REPARSE_POINT' }
  }
  $config = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  $expected = @('agentHost','agentPort','configMac','configuredAtUtc','gatewayHost','gatewayPort','machineId','memoryReadEnabled','memoryWriteEnabled','projectWriteEnabled','repositoryRegistryEnabled','repositoryRoots','schemaVersion') | Sort-Object
  $actual = @($config.PSObject.Properties.Name | Sort-Object)
  if ($config.schemaVersion -ne 1 -or ($actual -join ',') -cne ($expected -join ',') -or $config.agentHost -cne '127.0.0.1' -or $config.gatewayHost -cne '127.0.0.1' -or $config.agentPort -ne 3334 -or $config.gatewayPort -ne 3333 -or $config.memoryReadEnabled -ne $false -or $config.memoryWriteEnabled -ne $false -or $config.projectWriteEnabled -ne $false -or $config.repositoryRegistryEnabled -ne $false) { throw 'PORTABLE_CONFIG_SCHEMA_INVALID' }
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $entropy = [Text.Encoding]::UTF8.GetBytes('Nodaris.Portable.Runtime.v1')
  $protected = [Convert]::FromBase64String((Get-Content -LiteralPath $tokenPath -Raw -ErrorAction Stop).Trim())
  $clear = [Security.Cryptography.ProtectedData]::Unprotect($protected, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  try {
    $token = [Text.Encoding]::UTF8.GetString($clear)
    if ($token.Length -lt 32 -or $token -match '\s') { throw 'PORTABLE_TOKEN_INVALID' }
  if ($config.machineId -notmatch '^machine-[a-f0-9]{32}$') { throw 'PORTABLE_CONFIG_IDENTITY_INVALID' }
    $payload = Get-NodarisPortableConfigPayload -Config $config
    $expectedMac = New-NodarisPortableConfigMac -Payload $payload -Token $token
    if (-not (Test-NodarisPortableMac -Expected $expectedMac -Actual ([string]$config.configMac))) { throw 'PORTABLE_CONFIG_INTEGRITY_INVALID' }
    $resolvedRoots = @($config.repositoryRoots | ForEach-Object { Test-NodarisPortableProjectRoot -Path ([string]$_) })
    if (($resolvedRoots -join ';') -cne (@($config.repositoryRoots) -join ';')) { throw 'PORTABLE_CONFIG_ROOT_IDENTITY_MISMATCH' }
    return [pscustomobject]@{ config = $config; token = $token; dataRoot = $root }
  } finally { [Array]::Clear($clear, 0, $clear.Length); [Array]::Clear($protected, 0, $protected.Length) }
}

function New-NodarisPortableTunnelConfig {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$TunnelId,
    [Parameter(Mandatory = $true)][string]$RuntimeKey
  )
  if ($TunnelId -notmatch '^[A-Za-z0-9_-]{8,128}$') { throw 'PORTABLE_TUNNEL_ID_INVALID' }
  if ($RuntimeKey.Length -lt 20 -or $RuntimeKey -match '\s') { throw 'PORTABLE_TUNNEL_KEY_INVALID' }
  $exe = [IO.Path]::GetFullPath($Executable)
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'PORTABLE_TUNNEL_EXECUTABLE_MISSING' }
  $item = Get-Item -LiteralPath $exe -Force -ErrorAction Stop
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $exe.StartsWith('\\')) { throw 'PORTABLE_TUNNEL_EXECUTABLE_PATH_INVALID' }
  $installRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Nodaris\tunnel-client')).TrimEnd('\') + '\'
  if (-not $exe.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $installRoot -PathType Container) -or -not (Test-NodarisPortablePrivateAcl -Path $installRoot.TrimEnd('\')) -or -not (Test-NodarisPortablePrivateAcl -Path $exe)) { throw 'PORTABLE_TUNNEL_INSTALL_ROOT_NOT_PRIVATE' }
  $installCurrent = [IO.Path]::GetPathRoot($exe)
  foreach ($segment in @($exe.Substring($installCurrent.Length).Split('\') | Where-Object { $_ })) {
    $installCurrent = Join-Path $installCurrent $segment
    $entry = Get-Item -LiteralPath $installCurrent -Force -ErrorAction Stop
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_TUNNEL_INSTALL_REPARSE_POINT' }
  }
  $root = Initialize-NodarisPortableDataRoot
  $loaded = Read-NodarisPortableConfig
  $metadataPath = Join-Path $root 'tunnel.json'
  $profilePath = Join-Path $root 'tunnel-client.yaml'
  $secretPath = Join-Path $root 'tunnel-api-key.dpapi'
  if ((Test-Path -LiteralPath $metadataPath) -or (Test-Path -LiteralPath $profilePath) -or (Test-Path -LiteralPath $secretPath)) { throw 'PORTABLE_TUNNEL_CONFIG_ALREADY_EXISTS' }
  $exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
  $profile = @"
config_version: 1
control_plane:
  tunnel_id: $TunnelId
  api_key: env:CONTROL_PLANE_API_KEY
mcp:
  server_urls:
    - channel: main
      url: http://127.0.0.1:3333/mcp
  extra_headers:
    Authorization: env:NODARIS_PORTABLE_MCP_BEARER
health:
  listen_addr: 127.0.0.1:3335
admin_ui:
  open_browser: false
log:
  level: info
  format: json
"@
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $entropy = [Text.Encoding]::UTF8.GetBytes('Nodaris.Portable.Tunnel.v1')
  $clear = [Text.Encoding]::UTF8.GetBytes($RuntimeKey)
  $protected = $null
  $tmp = [Collections.Generic.List[string]]::new()
  $movedProfile = $false; $movedSecret = $false; $movedMetadata = $false
  try {
    $protected = [Security.Cryptography.ProtectedData]::Protect($clear, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $payload = [ordered]@{ schemaVersion = 1; enabled = $false; executable = $exe; executableSha256 = $exeHash; tunnelId = $TunnelId; profileSha256 = Get-NodarisPortableSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes($profile)) }
    $mac = New-NodarisPortableConfigMac -Payload $payload -Token $loaded.token
    $metadata = [ordered]@{}; foreach ($key in $payload.Keys) { $metadata[$key] = $payload[$key] }; $metadata['configMac'] = $mac
    $tmpProfile = Join-Path $root ('tunnel.' + [guid]::NewGuid().ToString('N') + '.yaml.tmp')
    $tmpSecret = Join-Path $root ('tunnel.' + [guid]::NewGuid().ToString('N') + '.secret.tmp')
    $tmpMetadata = Join-Path $root ('tunnel.' + [guid]::NewGuid().ToString('N') + '.json.tmp')
    foreach ($temporaryPath in @($tmpProfile, $tmpSecret, $tmpMetadata)) { $tmp.Add([string]$temporaryPath) }
    [IO.File]::WriteAllText($tmpProfile, $profile, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($tmpSecret, [Convert]::ToBase64String($protected), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($tmpMetadata, ($metadata | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmpProfile, $profilePath)
    $movedProfile = $true
    [IO.File]::Move($tmpSecret, $secretPath)
    $movedSecret = $true
    [IO.File]::Move($tmpMetadata, $metadataPath)
    $movedMetadata = $true
    foreach ($path in @($profilePath, $secretPath, $metadataPath)) { if (-not (Test-NodarisPortablePrivateAcl -Path $path)) { throw 'PORTABLE_TUNNEL_FILE_ACL_INVALID' } }
    return [pscustomobject]@{ tunnelId = $TunnelId; executable = $exe; executableSha256 = $exeHash; profilePath = $profilePath; enabled = $false }
  } catch {
    foreach ($path in @($tmp)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } }
    if ($movedProfile) { Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue }
    if ($movedSecret) { Remove-Item -LiteralPath $secretPath -Force -ErrorAction SilentlyContinue }
    if ($movedMetadata) { Remove-Item -LiteralPath $metadataPath -Force -ErrorAction SilentlyContinue }
    throw
  } finally {
    [Array]::Clear($clear, 0, $clear.Length)
    if ($null -ne $protected) { [Array]::Clear($protected, 0, $protected.Length) }
    [Array]::Clear($entropy, 0, $entropy.Length)
  }
}

function Read-NodarisPortableTunnelConfig {
  $root = Get-NodarisPortableDataRoot
  $metadataPath = Join-Path $root 'tunnel.json'
  $profilePath = Join-Path $root 'tunnel-client.yaml'
  $secretPath = Join-Path $root 'tunnel-api-key.dpapi'
  $present = @(@($metadataPath, $profilePath, $secretPath) | Where-Object { Test-Path -LiteralPath $_ })
  if ($present.Count -eq 0) { return $null }
  if ($present.Count -ne 3) { throw 'PORTABLE_TUNNEL_CONFIG_INCOMPLETE' }
  foreach ($path in @($metadataPath, $profilePath, $secretPath)) {
    if (-not (Test-NodarisPortablePrivateAcl -Path $path)) { throw 'PORTABLE_TUNNEL_FILE_ACL_INVALID' }
    $entry = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_TUNNEL_REPARSE_POINT' }
  }
  $metadata = Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  $expectedNames = @('configMac','enabled','executable','executableSha256','profileSha256','schemaVersion','tunnelId') | Sort-Object
  if ((@($metadata.PSObject.Properties.Name | Sort-Object) -join ',') -cne ($expectedNames -join ',') -or $metadata.schemaVersion -ne 1 -or $metadata.tunnelId -notmatch '^[A-Za-z0-9_-]{8,128}$' -or [string]$metadata.executable -match '^\\\\') { throw 'PORTABLE_TUNNEL_SCHEMA_INVALID' }
  $profile = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
  $profileHash = Get-NodarisPortableSha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes($profile))
  if ($profileHash -cne [string]$metadata.profileSha256) { throw 'PORTABLE_TUNNEL_PROFILE_INTEGRITY_INVALID' }
  if ($profile -notmatch '(?m)^  tunnel_id: ' + [regex]::Escape([string]$metadata.tunnelId) + '$' -or $profile -notmatch '(?m)^      url: http://127\.0\.0\.1:3333/mcp$' -or $profile -notmatch '(?m)^    Authorization: env:NODARIS_PORTABLE_MCP_BEARER$' -or $profile -notmatch '(?m)^  api_key: env:CONTROL_PLANE_API_KEY$' -or $profile -notmatch '(?m)^  listen_addr: 127\.0\.0\.1:3335$') { throw 'PORTABLE_TUNNEL_PROFILE_SCOPE_INVALID' }
  $loaded = Read-NodarisPortableConfig
  $payload = [ordered]@{ schemaVersion = [int]$metadata.schemaVersion; enabled = [bool]$metadata.enabled; executable = [string]$metadata.executable; executableSha256 = [string]$metadata.executableSha256; tunnelId = [string]$metadata.tunnelId; profileSha256 = [string]$metadata.profileSha256 }
  $expectedMac = New-NodarisPortableConfigMac -Payload $payload -Token $loaded.token
  if (-not (Test-NodarisPortableMac -Expected $expectedMac -Actual ([string]$metadata.configMac))) { throw 'PORTABLE_TUNNEL_CONFIG_INTEGRITY_INVALID' }
  if (-not (Test-Path -LiteralPath $metadata.executable -PathType Leaf)) { throw 'PORTABLE_TUNNEL_EXECUTABLE_MISSING' }
  $exe = Get-Item -LiteralPath $metadata.executable -Force -ErrorAction Stop
  $installRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Nodaris\tunnel-client')).TrimEnd('\') + '\'
  if (-not ([IO.Path]::GetFullPath([string]$metadata.executable)).StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-NodarisPortablePrivateAcl -Path $metadata.executable) -or ($exe.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Get-FileHash -LiteralPath $metadata.executable -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne [string]$metadata.executableSha256) { throw 'PORTABLE_TUNNEL_EXECUTABLE_IDENTITY_MISMATCH' }
  $pathCurrent = [IO.Path]::GetPathRoot([string]$metadata.executable)
  foreach ($segment in @(([string]$metadata.executable).Substring($pathCurrent.Length).Split('\') | Where-Object { $_ })) {
    $pathCurrent = Join-Path $pathCurrent $segment
    $pathItem = Get-Item -LiteralPath $pathCurrent -Force -ErrorAction Stop
    if (($pathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PORTABLE_TUNNEL_INSTALL_REPARSE_POINT' }
  }
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $protected = [Convert]::FromBase64String((Get-Content -LiteralPath $secretPath -Raw -ErrorAction Stop).Trim())
  $entropy = [Text.Encoding]::UTF8.GetBytes('Nodaris.Portable.Tunnel.v1')
  $clear = [Security.Cryptography.ProtectedData]::Unprotect($protected, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
  try {
    $runtimeKey = [Text.Encoding]::UTF8.GetString($clear)
    if ($runtimeKey.Length -lt 20 -or $runtimeKey -match '\s') { throw 'PORTABLE_TUNNEL_KEY_INVALID' }
    return [pscustomobject]@{ config = $metadata; executable = [string]$metadata.executable; profilePath = $profilePath; runtimeKey = $runtimeKey; tunnelId = [string]$metadata.tunnelId }
  } finally { [Array]::Clear($clear, 0, $clear.Length); [Array]::Clear($protected, 0, $protected.Length); [Array]::Clear($entropy, 0, $entropy.Length) }
}

function Set-NodarisPortableTunnelEnabled {
  param([Parameter(Mandatory = $true)][bool]$Enabled)
  $root = Get-NodarisPortableDataRoot
  $metadataPath = Join-Path $root 'tunnel.json'
  $loaded = Read-NodarisPortableTunnelConfig
  if ($null -eq $loaded) { throw 'PORTABLE_TUNNEL_NOT_CONFIGURED' }
  $loadedConfig = $loaded.config
  $payload = [ordered]@{ schemaVersion = [int]$loadedConfig.schemaVersion; enabled = $Enabled; executable = [string]$loadedConfig.executable; executableSha256 = [string]$loadedConfig.executableSha256; tunnelId = [string]$loadedConfig.tunnelId; profileSha256 = [string]$loadedConfig.profileSha256 }
  $runtime = Read-NodarisPortableConfig
  $metadata = [ordered]@{}; foreach ($key in $payload.Keys) { $metadata[$key] = $payload[$key] }; $metadata['configMac'] = New-NodarisPortableConfigMac -Payload $payload -Token $runtime.token
  $temporary = Join-Path $root ('tunnel.' + [guid]::NewGuid().ToString('N') + '.json.tmp')
  $backup = Join-Path $root ('tunnel.' + [guid]::NewGuid().ToString('N') + '.json.bak')
  $backupSafeToDelete = $false
  try {
    [IO.File]::WriteAllText($temporary, ($metadata | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    if (-not (Test-NodarisPortablePrivateAcl -Path $temporary)) { throw 'PORTABLE_TUNNEL_FILE_ACL_INVALID' }
    [IO.File]::Replace($temporary, $metadataPath, $backup)
    if (-not (Test-NodarisPortablePrivateAcl -Path $metadataPath)) {
      try { [IO.File]::Replace($backup, $metadataPath, $temporary); $backupSafeToDelete = $true }
      catch { throw 'PORTABLE_TUNNEL_METADATA_ROLLBACK_FAILED; preserve the .bak file for recovery' }
      throw 'PORTABLE_TUNNEL_METADATA_ACL_INVALID; previous metadata restored'
    }
    $backupSafeToDelete = $true
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    if ($backupSafeToDelete -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
  }
}

function Get-NodarisPortableConfigPayload($Config) {
  return [ordered]@{ schemaVersion = [int]$Config.schemaVersion; machineId = [string]$Config.machineId; repositoryRoots = @($Config.repositoryRoots | ForEach-Object { [string]$_ }); agentHost = [string]$Config.agentHost; agentPort = [int]$Config.agentPort; gatewayHost = [string]$Config.gatewayHost; gatewayPort = [int]$Config.gatewayPort; memoryReadEnabled = [bool]$Config.memoryReadEnabled; memoryWriteEnabled = [bool]$Config.memoryWriteEnabled; projectWriteEnabled = [bool]$Config.projectWriteEnabled; repositoryRegistryEnabled = [bool]$Config.repositoryRegistryEnabled }
}

function New-NodarisPortableConfigMac {
  param([Parameter(Mandatory = $true)]$Payload, [Parameter(Mandatory = $true)][string]$Token)
  $key = [Text.Encoding]::UTF8.GetBytes($Token)
  $bytes = [Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 4 -Compress))
  $hmac = [Security.Cryptography.HMACSHA256]::new($key)
  try { return ([BitConverter]::ToString($hmac.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant() }
  finally { $hmac.Dispose(); [Array]::Clear($key, 0, $key.Length); [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-NodarisPortableSha256Hex {
  param([Parameter(Mandatory = $true)][byte[]]$Bytes)
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant() }
  finally { $algorithm.Dispose(); [Array]::Clear($Bytes, 0, $Bytes.Length) }
}

function Test-NodarisPortableMac([string]$Expected, [string]$Actual) {
  if ($Expected -notmatch '^[a-f0-9]{64}$' -or $Actual -notmatch '^[a-f0-9]{64}$') { return $false }
  $difference = 0
  for ($index = 0; $index -lt 64; $index++) { $difference = $difference -bor ([int][char]$Expected[$index] -bxor [int][char]$Actual[$index]) }
  return $difference -eq 0
}

Export-ModuleMember -Function Get-NodarisPortableDataRoot, Test-NodarisPortablePrivateAcl, Set-NodarisPortablePrivateAcl, Initialize-NodarisPortableDataRoot, Test-NodarisPortableProjectRoot, Initialize-NodarisPortableTunnelInstallRoot, New-NodarisPortableConfig, Read-NodarisPortableConfig, New-NodarisPortableTunnelConfig, Read-NodarisPortableTunnelConfig, Set-NodarisPortableTunnelEnabled
