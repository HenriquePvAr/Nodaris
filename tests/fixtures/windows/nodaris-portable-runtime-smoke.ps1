<# Starts only isolated Agent/Gateway processes on ephemeral loopback ports. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('Nodaris-Portable-Runtime-' + [guid]::NewGuid().ToString('N'))
$projectRoot = Join-Path $tempRoot 'Project'
$localAppData = Join-Path $tempRoot 'LocalAppData'
$processes = [Collections.Generic.List[Diagnostics.Process]]::new()
$created = $false
$environment = $null
$checkEnvironment = $null
$token = $null

function Get-FreeLoopbackPort {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  try { $listener.Start(); return [int]$listener.LocalEndpoint.Port }
  finally { $listener.Stop() }
}

function Start-IsolatedProcess([string]$Node, [string]$Arguments, [string]$WorkingDirectory, [hashtable]$Environment) {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $Node
  $info.Arguments = $Arguments
  $info.WorkingDirectory = $WorkingDirectory
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $vars = $info.EnvironmentVariables
  $vars.Clear()
  foreach ($name in $Environment.Keys) { $vars[[string]$name] = [string]$Environment[$name] }
  try {
    $process = [Diagnostics.Process]::Start($info)
    if ($null -eq $process) { throw 'PORTABLE_RUNTIME_FIXTURE_PROCESS_START_FAILED' }
    $process | Add-Member -NotePropertyName StdoutTask -NotePropertyValue ($process.StandardOutput.ReadToEndAsync())
    $process | Add-Member -NotePropertyName StderrTask -NotePropertyValue ($process.StandardError.ReadToEndAsync())
    $processes.Add($process)
    return $process
  } finally { $info = $null }
}

try {
  if (-not $tempRoot.StartsWith(([IO.Path]::GetTempPath().TrimEnd('\') + '\Nodaris-Portable-Runtime-'), [StringComparison]::OrdinalIgnoreCase)) { throw 'PORTABLE_RUNTIME_FIXTURE_SCOPE_INVALID' }
  [void][IO.Directory]::CreateDirectory($projectRoot)
  [void][IO.Directory]::CreateDirectory($localAppData)
  [IO.File]::WriteAllText((Join-Path $projectRoot 'README.md'), '# Isolated Nodaris fixture', [Text.UTF8Encoding]::new($false))
  $created = $true
  $nodeCommand = Get-Command node.exe -ErrorAction Stop | Select-Object -First 1
  $node = [IO.Path]::GetFullPath($nodeCommand.Source)
  $tsx = Join-Path $repoRoot 'node_modules\tsx\dist\cli.mjs'
  if (-not (Test-Path -LiteralPath $tsx -PathType Leaf)) { throw 'PORTABLE_RUNTIME_FIXTURE_DEPENDENCIES_MISSING' }
  $agentPort = Get-FreeLoopbackPort
  do { $gatewayPort = Get-FreeLoopbackPort } while ($gatewayPort -eq $agentPort)
  $random = [Security.Cryptography.RandomNumberGenerator]::Create()
  $tokenBytes = New-Object byte[] 48
  try { $random.GetBytes($tokenBytes); $token = [Convert]::ToBase64String($tokenBytes) }
  finally { $random.Dispose(); [Array]::Clear($tokenBytes, 0, $tokenBytes.Length) }
  $environment = @{
    PATH = [Environment]::GetEnvironmentVariable('PATH', 'Process')
    SystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Process')
    WINDIR = [Environment]::GetEnvironmentVariable('WINDIR', 'Process')
    TEMP = $tempRoot
    TMP = $tempRoot
    LOCALAPPDATA = $localAppData
    USERPROFILE = $tempRoot
    NODARIS_TOKEN = $token
    NODARIS_ALLOWED_ROOTS = $projectRoot
    NODARIS_MACHINE_ID = ('machine-' + [guid]::NewGuid().ToString('N'))
    AGENT_HOST = '127.0.0.1'
    AGENT_PORT = [string]$agentPort
    GATEWAY_HOST = '127.0.0.1'
    GATEWAY_PORT = [string]$gatewayPort
  }
  $agent = Start-IsolatedProcess -Node $node -Arguments '--import tsx "apps/agent/src/index.ts"' -WorkingDirectory $repoRoot -Environment $environment
  $gateway = Start-IsolatedProcess -Node $node -Arguments '--import tsx "apps/gateway/src/index.ts"' -WorkingDirectory $repoRoot -Environment $environment
  $deadline = [DateTime]::UtcNow.AddSeconds(45)
  $ready = $false
  do {
    if ($agent.HasExited -or $gateway.HasExited) { throw 'PORTABLE_RUNTIME_FIXTURE_SERVICE_EXITED' }
    try {
      $headers = @{ Authorization = 'Bearer ' + $token }
      $body = @{ operation = 'health' } | ConvertTo-Json -Compress
      $health = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $agentPort + '/rpc') -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 2
      if ($health.status -eq 'ok' -and $health.machineId -eq $environment['NODARIS_MACHINE_ID']) { $ready = $true }
    } catch { Start-Sleep -Milliseconds 250 }
  } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
  if (-not $ready) { throw 'PORTABLE_RUNTIME_FIXTURE_AGENT_HEALTH_FAILED' }
  $agentListener = @(Get-NetTCPConnection -State Listen -LocalPort $agentPort -ErrorAction Stop)
  $gatewayListener = @(Get-NetTCPConnection -State Listen -LocalPort $gatewayPort -ErrorAction Stop)
  if ($agentListener.Count -ne 1 -or $gatewayListener.Count -ne 1 -or [int]$agentListener[0].OwningProcess -ne $agent.Id -or [int]$gatewayListener[0].OwningProcess -ne $gateway.Id -or [string]$agentListener[0].LocalAddress -cne '127.0.0.1' -or [string]$gatewayListener[0].LocalAddress -cne '127.0.0.1') {
    $agentActual = (@($agentListener | ForEach-Object { [string]$_.LocalAddress + ':' + [string]$_.LocalPort + '/' + [int]$_.OwningProcess }) -join ',')
    $gatewayActual = (@($gatewayListener | ForEach-Object { [string]$_.LocalAddress + ':' + [string]$_.LocalPort + '/' + [int]$_.OwningProcess }) -join ',')
    throw ('PORTABLE_RUNTIME_FIXTURE_LISTENER_IDENTITY_FAILED AGENT_COUNT=' + $agentListener.Count + ' GATEWAY_COUNT=' + $gatewayListener.Count + ' AGENT=' + $agentActual + ' GATEWAY=' + $gatewayActual + ' EXPECTED_AGENT=' + $agent.Id + ' EXPECTED_GATEWAY=' + $gateway.Id)
  }

  $checkEnvironment = @{
    PATH = $environment['PATH']; SystemRoot = $environment['SystemRoot']; WINDIR = $environment['WINDIR'];
    TEMP = $tempRoot; TMP = $tempRoot; LOCALAPPDATA = $localAppData; USERPROFILE = $tempRoot;
    NODARIS_PORTABLE_MCP_PORT = [string]$gatewayPort; NODARIS_PORTABLE_MCP_TOKEN = $token
  }
  $checker = Join-Path $repoRoot 'scripts\windows\nodaris-portable-mcp-check.cjs'
  $check = Start-IsolatedProcess -Node $node -Arguments ('"' + $checker + '"') -WorkingDirectory $repoRoot -Environment $checkEnvironment
  if (-not $check.WaitForExit(20000)) { $check.Kill(); $check.WaitForExit(5000) | Out-Null; throw 'PORTABLE_RUNTIME_FIXTURE_MCP_TIMEOUT' }
  $check.WaitForExit()
  $output = $check.StdoutTask.GetAwaiter().GetResult()
  $null = $check.StderrTask.GetAwaiter().GetResult()
  if ($check.ExitCode -ne 0 -or $output -notmatch 'PORTABLE_MCP_CHECK=PASS TOOLS=9 READ_ONLY=VERIFIED') { throw 'PORTABLE_RUNTIME_FIXTURE_MCP_TOOL_CONTRACT_FAILED' }
  Write-Output 'PORTABLE_RUNTIME_FIXTURE=PASS AGENT_HEALTH=PASS MCP_TOOLS=9 READ_ONLY=VERIFIED PROJECT_SCOPE=TEMP_ONLY TUNNEL=NOT_RUN'
} finally {
  $cleanupFailed = $false
  for ($index = $processes.Count - 1; $index -ge 0; $index--) {
    $process = $processes[$index]
    try { if (-not $process.HasExited) { $process.Kill(); if (-not $process.WaitForExit(10000)) { $cleanupFailed = $true } } }
    catch { $cleanupFailed = $true }
    finally { $process.Dispose() }
  }
  if ($created -and -not $cleanupFailed -and (Test-Path -LiteralPath $tempRoot)) {
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\Nodaris-Portable-Runtime-'
    if (-not $resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'PORTABLE_RUNTIME_FIXTURE_CLEANUP_SCOPE_INVALID' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
  $token = $null
  if ($null -ne $environment) { $environment['NODARIS_TOKEN'] = $null }
  if ($null -ne $checkEnvironment) { $checkEnvironment['NODARIS_PORTABLE_MCP_TOKEN'] = $null }
  if ($cleanupFailed) { throw 'PORTABLE_RUNTIME_FIXTURE_CLEANUP_FAILED; temporary state was preserved' }
}
