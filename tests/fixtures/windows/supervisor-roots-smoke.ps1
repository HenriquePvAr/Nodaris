param(
  [Parameter(Mandatory = $true)][string]$TestRoot,
  [Parameter(Mandatory = $true)][string]$SupervisorPath,
  [Parameter(Mandatory = $true)][string]$ReaderPath
)
$ErrorActionPreference = 'Stop'
$script:diagnosticRecords = [Collections.Generic.List[object]]::new()
$script:startStackCalls = 0

function Write-Diagnostic([string]$Component, [string]$Stage, [string]$Status, [string]$ReasonCode, [int]$Attempt = 0, [long]$DurationMs = 0, [int]$TimeoutSeconds = -1, [int]$BackoffSeconds = -1) {
  $null = $script:diagnosticRecords.Add([pscustomobject]@{
      component = $Component
      stage = $Stage
      status = $Status
      reasonCode = $ReasonCode
      attempt = $Attempt
      durationMs = $DurationMs
      timeoutSeconds = $TimeoutSeconds
      backoffSeconds = $BackoffSeconds
    })
}

function Set-FixtureDirectoryAcl([string]$Path, [bool]$Protected = $true) {
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().User
  $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  $acl = [Security.AccessControl.DirectorySecurity]::new()
  $acl.SetAccessRuleProtection($Protected, $false)
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

function Write-FixtureConfig([string]$Path, [string]$Json) {
  [IO.File]::WriteAllText($Path, $Json, [Text.UTF8Encoding]::new($false))
  Set-FixtureFileAcl $Path
}

function Invoke-FixtureStartup([string]$ConfigPath, [string]$ReaderScriptPath = $script:ReaderPath) {
  $script:lastFixtureStartupError = $null
  try {
    Initialize-NodarisAllowedRoots -ReaderScriptPath $ReaderScriptPath -ConfigPath $ConfigPath
    $script:startStackCalls++
    return $true
  } catch {
    $script:lastFixtureStartupError = $_.Exception.Message
    if ($_.Exception.Message -ne 'NODARIS_ROOT_CONFIG_REJECTED') { throw 'Fluxo não sanitizou a falha da configuração.' }
    return $false
  }
}

$script:TestRoot = [IO.Path]::GetFullPath($TestRoot)
$script:SupervisorPath = [IO.Path]::GetFullPath($SupervisorPath)
$script:ReaderPath = [IO.Path]::GetFullPath($ReaderPath)
$configDir = Join-Path $script:TestRoot 'config'
$oneRoot = Join-Path $script:TestRoot 'approved-one'
$twoRoot = Join-Path $script:TestRoot 'approved-two'
[IO.Directory]::CreateDirectory($configDir) | Out-Null
[IO.Directory]::CreateDirectory($oneRoot) | Out-Null
[IO.Directory]::CreateDirectory($twoRoot) | Out-Null
Set-FixtureDirectoryAcl $configDir
$configPath = Join-Path $configDir 'allowed-roots.json'
$escapedOne = $oneRoot.Replace('\', '\\')
$escapedTwo = $twoRoot.Replace('\', '\\')

# Carrega somente as definições de função do supervisor; o script de produção não é executado.
$tokens = $null
$parseErrors = $null
$supervisorAst = [System.Management.Automation.Language.Parser]::ParseFile($script:SupervisorPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Supervisor não passou no parser PowerShell.' }
$requiredFunctions = @('Get-NodarisAllowedRootsValue', 'Initialize-NodarisAllowedRoots')
foreach ($functionName in $requiredFunctions) {
  $functionAst = $supervisorAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true) | Select-Object -First 1
  if ($null -eq $functionAst) { throw 'Função de integração não encontrada no supervisor.' }
  Invoke-Expression $functionAst.Extent.Text
}

# Uma raiz válida deve passar pelo leitor publicado e chegar ao ambiente sem saída de pipeline.
Write-FixtureConfig $configPath ('{"schemaVersion":1,"allowedRoots":["' + $escapedOne + '"]}')
$env:NODARIS_ALLOWED_ROOTS = 'C:\fallback-must-not-survive'
$singleOutput = @(Invoke-FixtureStartup $configPath)
if ($singleOutput.Count -ne 1 -or -not $singleOutput[0] -or $env:NODARIS_ALLOWED_ROOTS -ne $oneRoot) { throw 'Configuração válida de raiz única falhou.' }

# Raízes irmãs não sobrepostas preservam o delimitador atual.
Write-FixtureConfig $configPath ('{"schemaVersion":1,"allowedRoots":["' + $escapedOne + '","' + $escapedTwo + '"]}')
$multiOutput = @(Invoke-FixtureStartup $configPath)
if ($multiOutput.Count -ne 1 -or -not $multiOutput[0] -or $env:NODARIS_ALLOWED_ROOTS -ne ($oneRoot + ';' + $twoRoot)) { throw 'Configuração válida de múltiplas raízes falhou.' }

# Configuração ausente, inválida ou sem ACL privada não chama o início simulado e limpa qualquer valor anterior.
$missingPath = Join-Path $configDir 'missing.json'
$env:NODARIS_ALLOWED_ROOTS = 'C:\fallback-must-not-survive'
if (Invoke-FixtureStartup $missingPath) { throw 'Configuração ausente não falhou fechado.' }
if ($script:startStackCalls -ne 2 -or -not [string]::IsNullOrEmpty($env:NODARIS_ALLOWED_ROOTS)) { throw 'Falha ausente iniciou serviços ou manteve fallback.' }

Write-FixtureConfig $configPath '{invalid-json'
$env:NODARIS_ALLOWED_ROOTS = 'C:\fallback-must-not-survive'
if (Invoke-FixtureStartup $configPath) { throw 'Configuração inválida não falhou fechado.' }
if ($script:startStackCalls -ne 2 -or -not [string]::IsNullOrEmpty($env:NODARIS_ALLOWED_ROOTS)) { throw 'Falha inválida iniciou serviços ou manteve fallback.' }

# Uma saída com estrutura incompatível do leitor também deve falhar antes do início simulado.
$unexpectedReaderPath = Join-Path $script:TestRoot 'unexpected-reader.ps1'
$unexpectedReader = @'
$global:NodarisTestFakeReaderCalls = 0
function Read-NodarisLocalRoots {
  $global:NodarisTestFakeReaderCalls++
  return [pscustomobject]@{ schemaVersion = 1; allowedRoots = 'C:\invalid' }
}
'@
[IO.File]::WriteAllText($unexpectedReaderPath, $unexpectedReader, [Text.UTF8Encoding]::new($false))
# Restaura uma configuração válida e com ACL privada para isolar a resposta estrutural do leitor.
Write-FixtureConfig $configPath ('{"schemaVersion":1,"allowedRoots":["' + $escapedOne + '"]}')
$env:NODARIS_ALLOWED_ROOTS = 'C:\fallback-must-not-survive'
if (Invoke-FixtureStartup $configPath $unexpectedReaderPath) { throw 'Estrutura inesperada do leitor foi aceita.' }
if ($global:NodarisTestFakeReaderCalls -ne 1) { throw 'O leitor falso não foi executado exatamente uma vez.' }
if ($script:lastFixtureStartupError -ne 'NODARIS_ROOT_CONFIG_REJECTED') { throw 'A falha estrutural não foi sanitizada.' }
if ($script:startStackCalls -ne 2 -or -not [string]::IsNullOrEmpty($env:NODARIS_ALLOWED_ROOTS)) { throw 'Estrutura inesperada iniciou serviços ou manteve fallback.' }
Remove-Variable NodarisTestFakeReaderCalls -Scope Global

Write-FixtureConfig $configPath ('{"schemaVersion":1,"allowedRoots":["' + $escapedOne + '"]}')
Set-FixtureDirectoryAcl $configDir $false
$env:NODARIS_ALLOWED_ROOTS = 'C:\fallback-must-not-survive'
if (Invoke-FixtureStartup $configPath $script:ReaderPath) { throw 'ACL inadequada não falhou fechado.' }
if ($script:lastFixtureStartupError -ne 'NODARIS_ROOT_CONFIG_REJECTED') { throw 'A falha de ACL não foi sanitizada.' }
if ($script:startStackCalls -ne 2 -or -not [string]::IsNullOrEmpty($env:NODARIS_ALLOWED_ROOTS)) { throw 'Falha de ACL iniciou serviços ou manteve fallback.' }

$telemetry = $script:diagnosticRecords | ConvertTo-Json -Depth 4 -Compress
if ($telemetry.Contains($script:TestRoot) -or $telemetry -match '(?i)Bearer|Authorization|runtime.?key|api.?key|allowed-roots\.json|fallback-must-not-survive') { throw 'Telemetria incluiu caminho, segredo ou conteúdo de configuração.' }
if (@($script:diagnosticRecords | Where-Object { $_.reasonCode -eq 'configuration_invalid' }).Count -lt 4) { throw 'Falhas de configuração não foram diagnosticadas.' }

'supervisor-roots-fixtures=PASS'
'valid-roots=single,multiple'
'fail-closed=missing,invalid,unexpected-output,acl'
'start-stack-calls=' + $script:startStackCalls
'telemetry-sanitized=PASS'
