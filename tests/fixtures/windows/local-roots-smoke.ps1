param([Parameter(Mandatory = $true)][string]$TestRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\..\scripts\windows\local-roots.ps1')

function Set-FixtureDirectoryAcl([string]$Path) {
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().User
  $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  $acl = [Security.AccessControl.DirectorySecurity]::new()
  $acl.SetAccessRuleProtection($true, $false)
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($user, 'FullControl', $inherit, 'None', 'Allow'))
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($system, 'FullControl', $inherit, 'None', 'Allow'))
  [IO.Directory]::SetAccessControl($Path, $acl)
}
function Set-FixtureFileAcl([string]$Path) {
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().User
  $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $acl = [Security.AccessControl.FileSecurity]::new()
  $acl.SetAccessRuleProtection($true, $false)
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($user, 'FullControl', 'Allow'))
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($system, 'FullControl', 'Allow'))
  [IO.File]::SetAccessControl($Path, $acl)
}
function Write-FixtureConfig([string]$Json) {
  [IO.File]::WriteAllText($script:configPath, $Json, [Text.UTF8Encoding]::new($false))
  Set-FixtureFileAcl $script:configPath
}
function Assert-Rejected([string]$Json, [string]$ExpectedCode = 'NODARIS_ROOT_CONFIG_REJECTED') {
  Write-FixtureConfig $Json
  $rejected = $false
  try { Read-NodarisLocalRoots -Path $script:configPath | Out-Null } catch {
    $rejected = $_.Exception.Message -eq $ExpectedCode
    if ($_.Exception.Message -match [regex]::Escape($script:TestRoot)) { throw 'Erro expôs caminho de fixture.' }
  }
  if (-not $rejected) { throw 'Configuração inválida não foi rejeitada com erro sanitizado.' }
}

$script:TestRoot = [IO.Path]::GetFullPath($TestRoot)
$approved = Join-Path $script:TestRoot 'approved-project'
$configDir = Join-Path $script:TestRoot 'config'
[IO.Directory]::CreateDirectory($approved) | Out-Null
[IO.Directory]::CreateDirectory($configDir) | Out-Null
Set-FixtureDirectoryAcl $configDir
$script:configPath = Join-Path $configDir 'allowed-roots.json'
$canonicalRoot = [IO.Path]::GetFullPath($approved)
$escapedRoot = $canonicalRoot.Replace('\', '\\')
$semicolonRoot = Join-Path $script:TestRoot 'approved;semicolon'
[IO.Directory]::CreateDirectory($semicolonRoot) | Out-Null
$escapedSemicolonRoot = [IO.Path]::GetFullPath($semicolonRoot).Replace('\', '\\')

# Arquivo ausente: sem fallback implícito.
$absentRejected = $false
try { Read-NodarisLocalRoots -Path (Join-Path $configDir 'absent.json') | Out-Null } catch { $absentRejected = $_.Exception.Message -eq 'NODARIS_ROOT_CONFIG_REJECTED' }
if (-not $absentRejected) { throw 'Configuração ausente não falhou fechado.' }

Write-FixtureConfig ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"]}')
$validOutput = @(Read-NodarisLocalRoots -Path $script:configPath)
if ($validOutput.Count -ne 1 -or $validOutput[0].schemaVersion -ne 1 -or $validOutput[0].allowedRoots.Count -ne 1 -or $validOutput[0].allowedRoots[0] -ne $canonicalRoot) { throw 'Configuração válida não foi preservada ou contaminou o pipeline.' }

Assert-Rejected '{bad json'
Assert-Rejected ('{"schemaVersion":2,"allowedRoots":["' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":true,"allowedRoots":["' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":"1","allowedRoots":["' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":1.5,"allowedRoots":["' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":null,"allowedRoots":["' + $escapedRoot + '"]}')
Assert-Rejected '{"schemaVersion":1,"allowedRoots":[]}'
Assert-Rejected '{"schemaVersion":1,"allowedRoots":"C:\\fixture"}'
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["relative"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '\\missing"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '","' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '\\child","' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":1,"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"],"ALLOWEDROOTS":[]}')
Assert-Rejected ('{"schemaVersion":1,"SchemaVersion":2,"allowedRoots":["' + $escapedRoot + '"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"],"allowed\u0052oots":[]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"],"ALLOWED\u0052OOTS":[]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot.Replace('approved-project','..') + '"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $env:SystemDrive + '\\"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + ':stream"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '."]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '\\NUL"]}')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedSemicolonRoot + '"]}')

$exactInstallFixture = 'C:\fixture\nodaris'
$parentInstallFixture = 'C:\fixture'
if (Test-NodarisRootWouldBroadenInstall -Candidate $exactInstallFixture -InstallRoot $exactInstallFixture) { throw 'Raiz exatamente autorizada foi classificada como ampliação.' }
if (-not (Test-NodarisRootWouldBroadenInstall -Candidate $parentInstallFixture -InstallRoot $exactInstallFixture)) { throw 'Diretório pai sem consentimento não foi classificado como ampliação.' }

# Profundidade e orçamento são exercitados em processo PowerShell isolado pelo harness Vitest.
$nestedValue = '0'
for ($depth = 0; $depth -lt 12; $depth++) { $nestedValue = '{"n":' + $nestedValue + '}' }
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"],"extra":' + $nestedValue + '}')
$manyValues = ('0,' * 4200).TrimEnd(',')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":[' + $manyValues + ']}')

# O limite físico é conferido antes da leitura; fixture mantém ACL válida.
Write-FixtureConfig ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"],"padding":"' + ('x' * 33000) + '"}')
$oversizeRejected = $false
try { Read-NodarisLocalRoots -Path $script:configPath | Out-Null } catch { $oversizeRejected = $true }
if (-not $oversizeRejected) { throw 'Arquivo acima de 32 KiB foi aceito.' }

# Um diretório pai que abrangeria a instalação Nodaris é rejeitado antes de percorrer o filesystem.
$installRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installParent = Split-Path -Parent $installRoot
$escapedParent = $installParent.Replace('\', '\\')
Assert-Rejected ('{"schemaVersion":1,"allowedRoots":["' + $escapedParent + '"]}')

# DACL do diretório sem proteção contra herança deve falhar fechado.
$inheritedDirAcl = [IO.Directory]::GetAccessControl($configDir)
$inheritedDirAcl.SetAccessRuleProtection($false, $true)
[IO.Directory]::SetAccessControl($configDir, $inheritedDirAcl)
Write-FixtureConfig ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"]}')
$dirAclRejected = $false
try { Read-NodarisLocalRoots -Path $script:configPath | Out-Null } catch { $dirAclRejected = $true }
if (-not $dirAclRejected) { throw 'ACL herdada do diretório foi aceita.' }
Set-FixtureDirectoryAcl $configDir

# DACL ampla no arquivo deve falhar fechado.
Write-FixtureConfig ('{"schemaVersion":1,"allowedRoots":["' + $escapedRoot + '"]}')
$wideAcl = [IO.File]::GetAccessControl($script:configPath)
$wideUsers = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
$wideAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($wideUsers, 'Read', 'Allow'))
[IO.File]::SetAccessControl($script:configPath, $wideAcl)
$fileAclRejected = $false
try { Read-NodarisLocalRoots -Path $script:configPath | Out-Null } catch { $fileAclRejected = $true }
if (-not $fileAclRejected) { throw 'ACL ampla do arquivo foi aceita.' }

# Reparse point: quando suportado pela política local, provar a rejeição sem seguir o link.
$linkPath = Join-Path $script:TestRoot 'linked-project'
$linkRejected = $false
$junctionCreated = $false
try {
  New-Item -ItemType Junction -Path $linkPath -Target $approved -ErrorAction Stop | Out-Null
  $junctionCreated = $true
  Set-FixtureDirectoryAcl $configDir
  Write-FixtureConfig ('{"schemaVersion":1,"allowedRoots":["' + $linkPath.Replace('\', '\\') + '"]}')
  try { Read-NodarisLocalRoots -Path $script:configPath | Out-Null } catch { $linkRejected = $true }
} catch { $linkRejected = $true }
if (Test-Path -LiteralPath $linkPath) { Remove-Item -LiteralPath $linkPath -Force }
if (-not $linkRejected) { throw 'Reparse point foi aceito.' }
if (-not $junctionCreated) { throw 'Fixture de reparse point indisponível; teste de integração não comprovado.' }

if (Get-Command Set-NodarisPrivateDirectoryAcl -ErrorAction SilentlyContinue) { throw 'Fixture carregou módulo de runtime inesperadamente.' }
'local-roots-fixtures=PASS'
'reparse-fixture=PASS'
