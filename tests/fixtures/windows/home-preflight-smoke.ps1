<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\..\..\scripts\windows\home-preflight.ps1'
. ([IO.Path]::GetFullPath($scriptPath))

function Assert-Equal($Actual, $Expected, [string]$Message) {
  if ($Actual -ne $Expected) { throw "ASSERTION_FAILED: $Message" }
}

function Invoke-Fixture([object[]]$Checks, [string]$ExpectedStatus, [string]$Label) {
  $callCount = [ref]0
  $collector = {
    param($path)
    $callCount.Value++
    return $Checks
  }.GetNewClosure()
  $report = Invoke-NodarisHomePreflight -SelectedPath 'X:\Fixture Nodaris\á' -Collector $collector
  Assert-Equal $report.overallStatus $ExpectedStatus $Label
  Assert-Equal $callCount.Value 1 "$Label coleta simulada uma vez"
  Assert-Equal $report.effectsPerformed $false "$Label sem efeitos"
  Assert-Equal $report.privateFileContentsRead $false "$Label sem ler conteúdo privado"
  if ($report.checks.Count -eq 0) { throw "ASSERTION_FAILED: $Label precisa conter checagens" }
  return $report
}

$cleanChecks = @(
  (New-HomeCheck 'windows' 'PASS' 'WINDOWS_SUPPORTED' ([pscustomobject]@{ version = '10.0'; architecture = 'x64' })),
  (New-HomeCheck 'node' 'PASS' 'NODE_SUPPORTED' 'v22.12.0'),
  (New-HomeCheck 'pnpm' 'PASS' 'PNPM_SUPPORTED' '12.8.1'),
  (New-HomeCheck 'selected_directory' 'PASS' 'TARGET_DIRECTORY_READABLE' ([pscustomobject]@{ absolute = $true; containsSpaces = $true; containsUnicode = $true; nonDefault = $true })),
  (New-HomeCheck 'repository' 'PASS' 'GIT_MAIN_CLEAN_LOCKED_CHECKOUT' ([pscustomobject]@{ dirtyEntryCount = 0 })),
  (New-HomeCheck 'disk_space' 'PASS' 'DISK_SPACE_SUFFICIENT' 4096),
  (New-HomeCheck 'scheduled_tasks' 'PASS' 'NO_NODARIS_TASK'),
  (New-HomeCheck 'process_identity' 'PASS' 'NO_NODARIS_PROCESSES'),
  (New-HomeCheck 'port_3333' 'PASS' 'PORT_FREE'),
  (New-HomeCheck 'port_3334' 'PASS' 'PORT_FREE'),
  (New-HomeCheck 'port_8080' 'PASS' 'PORT_FREE'),
  (New-HomeCheck 'local_roots_configuration' 'PASS' 'ROOT_CONFIGURATION_ABSENT_ALLOWLIST_EMPTY'),
  (New-HomeCheck 'private_file_presence' 'PASS' 'NO_LOCAL_PRIVATE_DATA_FOUND'),
  (New-HomeCheck 'user_scope_write_access' 'NOT_CHECKED' 'NO_WRITE_PROBE_PERFORMED')
)

$clean = Invoke-Fixture $cleanChecks 'INCONCLUSIVE' 'estado limpo com capacidade de escrita não testada'
$privateCheck = @($clean.checks | Where-Object name -eq 'private_file_presence')[0]
Assert-Equal $privateCheck.code 'NO_LOCAL_PRIVATE_DATA_FOUND' 'credenciais e arquivos privados ausentes'
$cleanJson = $clean | ConvertTo-Json -Depth 8
if ($cleanJson.Contains('X:\Fixture') -or $cleanJson.Contains('á')) { throw 'ASSERTION_FAILED: relatório revelou caminho' }
$plan = Get-HomePlan $clean
Assert-Equal $plan.executionPerformed $false 'plano não executa'
Assert-Equal $plan.installationAllowed $false 'plano exige autorização separada'
if ($plan.rollback.Count -lt 3) { throw 'ASSERTION_FAILED: plano de rollback incompleto' }

$supported = @($cleanChecks | Where-Object { $_.name -ne 'user_scope_write_access' })
$null = Invoke-Fixture $supported 'PASS' 'Windows compatível e facts completos'

$blockedScenarios = @(
  @{ label = 'Windows não suportado'; check = New-HomeCheck 'windows' 'BLOCKED' 'WINDOWS_UNSUPPORTED' },
  @{ label = 'Node ausente'; check = New-HomeCheck 'node' 'BLOCKED' 'NODE_MISSING' },
  @{ label = 'pnpm ausente'; check = New-HomeCheck 'pnpm' 'BLOCKED' 'PNPM_MISSING' },
  @{ label = 'porta ocupada por outra instalação'; check = New-HomeCheck 'port_3333' 'BLOCKED' 'PORT_OWNED_BY_OTHER_NODARIS_INSTALLATION' },
  @{ label = 'listener identificado fora de loopback'; check = New-HomeCheck 'port_3334' 'BLOCKED' 'PORT_LISTENER_NON_LOOPBACK_IDENTIFIED' ([pscustomobject]@{ binding = 'non_loopback' }) },
  @{ label = 'tarefa conflitante'; check = New-HomeCheck 'scheduled_tasks' 'BLOCKED' 'NODARIS_TASK_CONFLICT' },
  @{ label = 'identidade de processo inconclusiva'; check = New-HomeCheck 'process_identity' 'INCONCLUSIVE' 'PROCESS_IDENTITY_UNCONFIRMED' },
  @{ label = 'diretório inexistente'; check = New-HomeCheck 'selected_directory' 'BLOCKED' 'TARGET_DIRECTORY_MISSING' },
  @{ label = 'configuração presente ou inválida não inspecionada'; check = New-HomeCheck 'local_roots_configuration' 'BLOCKED' 'ROOT_CONFIGURATION_PRESENT_CONTENT_NOT_READ' },
  @{ label = 'credenciais presentes não reutilizáveis'; check = New-HomeCheck 'private_file_presence' 'BLOCKED' 'LOCAL_PRIVATE_DATA_EXISTS_DO_NOT_COPY' },
  @{ label = 'permissão de instalação não verificada'; check = New-HomeCheck 'user_scope_write_access' 'NOT_CHECKED' 'NO_WRITE_PROBE_PERFORMED' }
)
foreach ($scenario in $blockedScenarios) {
  $scenarioChecks = @($supported | Where-Object { $_.name -ne $scenario.check.name }) + @($scenario.check)
  $expected = if ($scenario.check.status -eq 'INCONCLUSIVE' -or $scenario.check.status -eq 'NOT_CHECKED') { 'INCONCLUSIVE' } else { 'BLOCKED' }
  $null = Invoke-Fixture $scenarioChecks $expected $scenario.label
}

$pathRoot = Join-Path $env:TEMP ('Nodaris WIN02A ' + [Guid]::NewGuid().ToString() + ' á')
try {
  $null = New-Item -ItemType Directory -Path $pathRoot
  $features = Test-PathFeatures $pathRoot
  Assert-Equal $features.absolute $true 'path absoluto'
  Assert-Equal $features.containsSpaces $true 'path com espaços'
  Assert-Equal $features.containsUnicode $true 'path Unicode'
  Assert-Equal $features.nonDefault $true 'path não padrão'
} finally {
  Remove-Item -LiteralPath $pathRoot -Force -ErrorAction SilentlyContinue
}

Write-Output 'WINDOWS_HOME_PREFLIGHT_FIXTURE=PASS'
$parityReport = New-HomeReport -Checks $cleanChecks
$parityJson = $parityReport | ConvertTo-Json -Depth 8 -Compress
$parityBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($parityJson))
Write-Output ('WINDOWS_HOME_PREFLIGHT_REPORT_BASE64=' + $parityBase64)
