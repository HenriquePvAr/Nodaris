<# Synthetic, per-process configuration fixture; it never loads a user Nodaris profile. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$modulePath = Join-Path $sourceRoot 'scripts\windows\nodaris-portable-config.psm1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('Nodaris-Portable-Fixture-' + [guid]::NewGuid().ToString('N'))
$local = Join-Path $tempRoot 'LocalAppData'
$project = Join-Path $tempRoot 'Project-A'
$projectB = Join-Path $tempRoot 'Project-B'
$emptyLocal = Join-Path $tempRoot 'EmptyLocalAppData'
$oldLocalAppData = $env:LOCALAPPDATA
$created = $false

function Assert([bool]$Condition, [string]$Code) { if (-not $Condition) { throw $Code } }

try {
  if ($tempRoot -notlike (([IO.Path]::GetTempPath().TrimEnd('\')) + '\Nodaris-Portable-Fixture-*')) { throw 'FIXTURE_TEMP_SCOPE_INVALID' }
  [void][IO.Directory]::CreateDirectory($tempRoot)
  $created = $true
  [void][IO.Directory]::CreateDirectory($local)
  [void][IO.Directory]::CreateDirectory($project)
  [void][IO.Directory]::CreateDirectory($projectB)
  $env:LOCALAPPDATA = $local
  Import-Module $modulePath -Force

  $normalized = Test-NodarisPortableProjectRoot -Path $project
  Assert ($normalized -ceq [IO.Path]::GetFullPath($project).TrimEnd('\')) 'FIXTURE_ROOT_CANONICALIZATION_FAILED'
  $separatorRejected = $false
  $separatorPath = Join-Path $tempRoot 'Project;Injection'
  [void][IO.Directory]::CreateDirectory($separatorPath)
  try { $null = Test-NodarisPortableProjectRoot -Path $separatorPath } catch { $separatorRejected = $_.Exception.Message -match 'PORTABLE_PROJECT_PATH_SEPARATOR_UNSUPPORTED' }
  Assert $separatorRejected 'FIXTURE_ALLOWED_ROOT_SEPARATOR_ACCEPTED'
  $result = New-NodarisPortableConfig -ApprovedRoots @($project)
  Assert ($result.config.memoryReadEnabled -eq $false -and $result.config.memoryWriteEnabled -eq $false -and $result.config.projectWriteEnabled -eq $false) 'FIXTURE_WRITE_DEFAULT_NOT_DISABLED'
  Assert ($result.machineId -match '^machine-[a-f0-9]{32}$') 'FIXTURE_MACHINE_ID_INVALID'
  Assert (Test-NodarisPortablePrivateAcl -Path (Get-NodarisPortableDataRoot)) 'FIXTURE_DATA_ACL_INVALID'
  Assert (Test-NodarisPortablePrivateAcl -Path $result.configPath) 'FIXTURE_CONFIG_ACL_INVALID'

  $loaded = Read-NodarisPortableConfig
  Assert ($loaded.config.machineId -ceq $result.machineId) 'FIXTURE_IDENTITY_MISMATCH'
  Assert ($loaded.token.Length -ge 32) 'FIXTURE_TOKEN_DECRYPT_FAILED'
  Assert (-not ((Get-Content -LiteralPath $result.configPath -Raw) -match [regex]::Escape($loaded.token))) 'FIXTURE_TOKEN_PERSISTED_IN_PLAINTEXT'
  $secondAttempt = $false
  try { $null = New-NodarisPortableConfig -ApprovedRoots @($project) } catch { $secondAttempt = $_.Exception.Message -match 'PORTABLE_CONFIG_ALREADY_EXISTS' }
  Assert $secondAttempt 'FIXTURE_EXISTING_CONFIG_WAS_NOT_PRESERVED'

  $configPath = $result.configPath
  $original = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $original.repositoryRoots = @($projectB)
  [IO.File]::WriteAllText($configPath, ($original | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
  $tamperRejected = $false
  try { $null = Read-NodarisPortableConfig } catch { $tamperRejected = $_.Exception.Message -match 'PORTABLE_CONFIG_INTEGRITY_INVALID' }
  Assert $tamperRejected 'FIXTURE_TAMPERED_PROJECT_ROOT_ACCEPTED'

  [void][IO.Directory]::CreateDirectory($emptyLocal)
  $env:LOCALAPPDATA = $emptyLocal
  $empty = New-NodarisPortableConfig -ApprovedRoots @()
  $emptyLoaded = Read-NodarisPortableConfig
  Assert (@($emptyLoaded.config.repositoryRoots).Count -eq 0) 'FIXTURE_EMPTY_ALLOWLIST_NOT_PRESERVED'
  Assert ($emptyLoaded.config.memoryReadEnabled -eq $false -and $emptyLoaded.config.memoryWriteEnabled -eq $false -and $emptyLoaded.config.projectWriteEnabled -eq $false) 'FIXTURE_EMPTY_ALLOWLIST_WRITE_DEFAULT_NOT_DISABLED'
  Assert ($null -eq (Read-NodarisPortableTunnelConfig)) 'FIXTURE_TUNNEL_ENABLED_WITHOUT_CONFIGURATION'

  $installRoot = Initialize-NodarisPortableTunnelInstallRoot
  Assert (Test-NodarisPortablePrivateAcl -Path $installRoot) 'FIXTURE_TUNNEL_INSTALL_ACL_INVALID'
  $fakeClient = Join-Path $installRoot 'tunnel-client.exe'
  [IO.File]::WriteAllText($fakeClient, 'synthetic executable identity only', [Text.UTF8Encoding]::new($false))
  $tunnelKey = 'synthetic-runtime-key-0123456789'
  $invalidTunnelIdRejected = $false
  try { $null = New-NodarisPortableTunnelConfig -Executable $fakeClient -TunnelId "invalid`nheader" -RuntimeKey $tunnelKey } catch { $invalidTunnelIdRejected = $_.Exception.Message -match 'PORTABLE_TUNNEL_ID_INVALID' }
  Assert $invalidTunnelIdRejected 'FIXTURE_INVALID_TUNNEL_ID_ACCEPTED'
  $tunnel = New-NodarisPortableTunnelConfig -Executable $fakeClient -TunnelId 'tunnel_0123456789abcdef0123456789abcdef' -RuntimeKey $tunnelKey
  Assert (-not $tunnel.enabled) 'FIXTURE_TUNNEL_NOT_DISABLED_BY_DEFAULT'
  $loadedTunnel = Read-NodarisPortableTunnelConfig
  Assert ($loadedTunnel.runtimeKey -ceq $tunnelKey) 'FIXTURE_TUNNEL_KEY_DPAPI_ROUNDTRIP_FAILED'
  Assert ($loadedTunnel.config.enabled -eq $false) 'FIXTURE_TUNNEL_ENABLE_STATE_MISMATCH'
  $profileContents = Get-Content -LiteralPath $loadedTunnel.profilePath -Raw
  Assert ($profileContents -notmatch [regex]::Escape($tunnelKey) -and $profileContents -match '127\.0\.0\.1:3333/mcp' -and $profileContents -match '127\.0\.0\.1:3335') 'FIXTURE_TUNNEL_PROFILE_SECRET_OR_SCOPE_INVALID'
  Set-NodarisPortableTunnelEnabled -Enabled $true
  Assert ((Read-NodarisPortableTunnelConfig).config.enabled -eq $true) 'FIXTURE_TUNNEL_ENABLE_UPDATE_FAILED'
  Set-NodarisPortableTunnelEnabled -Enabled $false
  $originalProfile = $profileContents
  $metadataPath = Join-Path (Get-NodarisPortableDataRoot) 'tunnel.json'
  $originalMetadata = Get-Content -LiteralPath $metadataPath -Raw
  $tamperedMetadata = $originalMetadata | ConvertFrom-Json
  $tamperedMetadata.enabled = $true
  [IO.File]::WriteAllText($metadataPath, ($tamperedMetadata | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
  $metadataTamperRejected = $false
  try { $null = Read-NodarisPortableTunnelConfig } catch { $metadataTamperRejected = $_.Exception.Message -match 'PORTABLE_TUNNEL_CONFIG_INTEGRITY_INVALID' }
  Assert $metadataTamperRejected 'FIXTURE_TAMPERED_TUNNEL_METADATA_ACCEPTED'
  [IO.File]::WriteAllText($metadataPath, $originalMetadata, [Text.UTF8Encoding]::new($false))
  [IO.File]::AppendAllText($loadedTunnel.profilePath, "# tamper`n", [Text.UTF8Encoding]::new($false))
  $profileTamperRejected = $false
  try { $null = Read-NodarisPortableTunnelConfig } catch { $profileTamperRejected = $_.Exception.Message -match 'PORTABLE_TUNNEL_PROFILE_INTEGRITY_INVALID' }
  Assert $profileTamperRejected 'FIXTURE_TAMPERED_TUNNEL_PROFILE_ACCEPTED'
  [IO.File]::WriteAllText($loadedTunnel.profilePath, $originalProfile, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($fakeClient, 'modified synthetic executable identity', [Text.UTF8Encoding]::new($false))
  $executableTamperRejected = $false
  try { $null = Read-NodarisPortableTunnelConfig } catch { $executableTamperRejected = $_.Exception.Message -match 'PORTABLE_TUNNEL_EXECUTABLE_IDENTITY_MISMATCH' }
  Assert $executableTamperRejected 'FIXTURE_TAMPERED_TUNNEL_EXECUTABLE_ACCEPTED'
  Write-Output 'PORTABLE_CONFIG_FIXTURE=PASS TOKEN=DPAPI TUNNEL_KEY=DPAPI PROFILE=SCOPED DEFAULT_DISABLED=YES TAMPER=REJECTED'
} finally {
  Remove-Module nodaris-portable-config -ErrorAction SilentlyContinue
  if ($null -ne $oldLocalAppData) { $env:LOCALAPPDATA = $oldLocalAppData } else { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
  if ($created -and (Test-Path -LiteralPath $tempRoot)) {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $resolvedBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTemp.StartsWith($resolvedBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'FIXTURE_CLEANUP_SCOPE_INVALID' }
    Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
  }
}
