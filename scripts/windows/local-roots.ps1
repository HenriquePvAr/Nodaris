<# SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
   SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 #>

# Leitor isolado. Este arquivo não é carregado pelo supervisor nesta etapa.
$script:NodarisLocalRootsInstallRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

function Get-NodarisLocalRootsConfigPath {
  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'NODARIS_ROOT_CONFIG_REJECTED' }
  return (Join-Path $env:LOCALAPPDATA 'Nodaris\config\allowed-roots.json')
}

function Test-NodarisPathWithin([string]$Path, [string]$Parent) {
  $normalizedParent = $Parent.TrimEnd('\')
  return $Path.Equals($normalizedParent, [StringComparison]::OrdinalIgnoreCase) -or
    $Path.StartsWith($normalizedParent + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-NodarisRootWouldBroadenInstall([string]$Candidate, [string]$InstallRoot = $script:NodarisLocalRootsInstallRoot) {
  return (Test-NodarisPathWithin $InstallRoot $Candidate) -and
    -not $Candidate.Equals($InstallRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Skip-NodarisJsonWhitespace($Parser) {
  while ($Parser.Index -lt $Parser.Text.Length -and [char]::IsWhiteSpace($Parser.Text[$Parser.Index])) { $Parser.Index = $Parser.Index + 1 }
}

function Read-NodarisJsonString($Parser) {
  if ($Parser.Index -ge $Parser.Text.Length -or $Parser.Text[$Parser.Index] -ne '"') { throw 'invalid' }
  $start = $Parser.Index
  $Parser.Index = $Parser.Index + 1
  $escaped = $false
  while ($Parser.Index -lt $Parser.Text.Length) {
    $character = $Parser.Text[$Parser.Index]
    $Parser.Index = $Parser.Index + 1
    if ($escaped) { $escaped = $false; continue }
    if ($character -eq '\') { $escaped = $true; continue }
    if ($character -eq '"') {
      $token = $Parser.Text.Substring($start, $Parser.Index - $start)
      $builder = [Text.StringBuilder]::new()
      for ($offset = 1; $offset -lt $token.Length - 1; $offset++) {
        $character = $token[$offset]
        if ($character -ne '\') {
          if ([int]$character -lt 0x20) { throw 'invalid' }
          $null = $builder.Append($character)
          continue
        }
        $offset++
        if ($offset -ge $token.Length - 1) { throw 'invalid' }
        switch ($token[$offset]) {
          '"' { $null = $builder.Append('"') }
          '\' { $null = $builder.Append('\') }
          '/' { $null = $builder.Append('/') }
          'b' { $null = $builder.Append([char]8) }
          'f' { $null = $builder.Append([char]12) }
          'n' { $null = $builder.Append([char]10) }
          'r' { $null = $builder.Append([char]13) }
          't' { $null = $builder.Append([char]9) }
          'u' {
            if ($offset + 4 -ge $token.Length - 1) { throw 'invalid' }
            $hex = $token.Substring($offset + 1, 4)
            $codeUnit = 0
            if (-not [int]::TryParse($hex, [Globalization.NumberStyles]::HexNumber, [Globalization.CultureInfo]::InvariantCulture, [ref]$codeUnit)) { throw 'invalid' }
            $null = $builder.Append([char]$codeUnit)
            $offset += 4
          }
          default { throw 'invalid' }
        }
      }
      return $builder.ToString()
    }
  }
  throw 'invalid'
}

function Read-NodarisJsonValue($Parser, [int]$Depth = 0) {
  if ($Depth -gt 8) { throw 'invalid' }
  $Parser.TokenCount = $Parser.TokenCount + 1
  if ($Parser.TokenCount -gt 4096) { throw 'invalid' }
  Skip-NodarisJsonWhitespace $Parser
  if ($Parser.Index -ge $Parser.Text.Length) { throw 'invalid' }
  $character = $Parser.Text[$Parser.Index]
  if ($character -eq '"') { $null = Read-NodarisJsonString $Parser; return }
  if ($character -eq '{') {
    $null = $Parser.Index++
    Skip-NodarisJsonWhitespace $Parser
    if ($Parser.Index -lt $Parser.Text.Length -and $Parser.Text[$Parser.Index] -eq '}') { $null = $Parser.Index++; return }
    # O Windows PowerShell materializa propriedades sem distinguir caixa.
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($true) {
      Skip-NodarisJsonWhitespace $Parser
      $key = Read-NodarisJsonString $Parser
      $Parser.TokenCount = $Parser.TokenCount + 1
      if ($Parser.TokenCount -gt 4096) { throw 'invalid' }
      if (-not $keys.Add($key)) { throw 'invalid' }
      Skip-NodarisJsonWhitespace $Parser
      if ($Parser.Index -ge $Parser.Text.Length -or $Parser.Text[$Parser.Index] -ne ':') { throw 'invalid' }
      $null = $Parser.Index++
      Read-NodarisJsonValue $Parser ($Depth + 1)
      Skip-NodarisJsonWhitespace $Parser
      if ($Parser.Index -ge $Parser.Text.Length) { throw 'invalid' }
      if ($Parser.Text[$Parser.Index] -eq '}') { $null = $Parser.Index++; return }
      if ($Parser.Text[$Parser.Index] -ne ',') { throw 'invalid' }
      $null = $Parser.Index++
    }
  }
  if ($character -eq '[') {
    $null = $Parser.Index++
    Skip-NodarisJsonWhitespace $Parser
    if ($Parser.Index -lt $Parser.Text.Length -and $Parser.Text[$Parser.Index] -eq ']') { $null = $Parser.Index++; return }
    while ($true) {
      Read-NodarisJsonValue $Parser ($Depth + 1)
      Skip-NodarisJsonWhitespace $Parser
      if ($Parser.Index -ge $Parser.Text.Length) { throw 'invalid' }
      if ($Parser.Text[$Parser.Index] -eq ']') { $null = $Parser.Index++; return }
      if ($Parser.Text[$Parser.Index] -ne ',') { throw 'invalid' }
      $null = $Parser.Index++
    }
  }
  $start = $Parser.Index
  while ($Parser.Index -lt $Parser.Text.Length -and -not [char]::IsWhiteSpace($Parser.Text[$Parser.Index]) -and $Parser.Text[$Parser.Index] -notin @(',', ']', '}')) { $null = $Parser.Index++ }
  if ($Parser.Index -eq $start) { throw 'invalid' }
}

function Test-NodarisJsonKeysUnique([string]$Json) {
  $parser = [pscustomobject]@{ Text = $Json; Index = 0; TokenCount = 0 }
  Read-NodarisJsonValue $parser
  Skip-NodarisJsonWhitespace $parser
  if ($parser.Index -ne $Json.Length) { throw 'invalid' }
  return $true
}

function Test-NodarisNoReparseComponents([string]$Path) {
  try {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $relative = $full.Substring($root.Length)
    foreach ($segment in $relative.Split([char]'\', [StringSplitOptions]::RemoveEmptyEntries)) {
      $current = Join-Path $current $segment
      if (-not (Test-Path -LiteralPath $current)) { return $false }
      $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    }
    return $true
  } catch { return $false }
}

function Test-NodarisExactPrivateAcl([string]$Path, [bool]$IsDirectory) {
  try {
    if ($IsDirectory) { $acl = [IO.Directory]::GetAccessControl($Path) }
    else { $acl = [IO.File]::GetAccessControl($Path) }
    if (-not $acl.AreAccessRulesProtected) { return $false }
    $sidType = [Security.Principal.SecurityIdentifier]
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $expected = @($currentSid, 'S-1-5-18') | Sort-Object
    $rules = @($acl.GetAccessRules($true, $true, $sidType))
    if ($rules.Count -ne 2) { return $false }
    $actual = @()
    foreach ($rule in $rules) {
      if ($rule.IsInherited -or $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { return $false }
      if ([int]$rule.FileSystemRights -ne [int][Security.AccessControl.FileSystemRights]::FullControl) { return $false }
      if ($rule.PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None) { return $false }
      if ($IsDirectory) {
        $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
        if ($rule.InheritanceFlags -ne $inherit) { return $false }
      } elseif ($rule.InheritanceFlags -ne [Security.AccessControl.InheritanceFlags]::None) { return $false }
      $actual += $rule.IdentityReference.Value
    }
    return (($actual | Sort-Object) -join ',') -eq ($expected -join ',')
  } catch { return $false }
}

function Read-NodarisLocalRoots {
  [CmdletBinding()]
  param([string]$Path = (Get-NodarisLocalRootsConfigPath))

  # Mensagens deliberadamente genéricas: erros não revelam caminhos ou conteúdo.
  try {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or $Path.Contains('/')) { throw 'invalid' }
    $fullConfigPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullConfigPath.Equals($Path, [StringComparison]::OrdinalIgnoreCase)) { throw 'invalid' }
    if (-not (Test-Path -LiteralPath $fullConfigPath -PathType Leaf) -or -not (Test-NodarisNoReparseComponents $fullConfigPath)) { throw 'invalid' }
    $configDirectory = Split-Path -Parent $fullConfigPath
    if (-not (Test-NodarisExactPrivateAcl $configDirectory $true) -or -not (Test-NodarisExactPrivateAcl $fullConfigPath $false)) { throw 'invalid' }

    $configFile = Get-Item -LiteralPath $fullConfigPath -Force -ErrorAction Stop
    if ($configFile.Length -gt 32768) { throw 'invalid' }
    $json = [IO.File]::ReadAllText($fullConfigPath, [Text.Encoding]::UTF8)
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 32768) { throw 'invalid' }
    # Parse estrutural detecta duplicatas após decodificar escapes JSON (inclusive chaves aninhadas).
    $null = Test-NodarisJsonKeysUnique $json
    $data = $json | ConvertFrom-Json -ErrorAction Stop
    $properties = @($data.PSObject.Properties.Name | Sort-Object)
    if (($properties -join ',') -ne 'allowedRoots,schemaVersion') { throw 'invalid' }
    if (($data.schemaVersion -isnot [int] -and $data.schemaVersion -isnot [long]) -or $data.schemaVersion -ne 1) { throw 'invalid' }
    if ($data.allowedRoots -isnot [Array] -or $data.allowedRoots.Count -lt 1 -or $data.allowedRoots.Count -gt 32) { throw 'invalid' }

    $roots = [Collections.Generic.List[string]]::new()
    foreach ($candidate in $data.allowedRoots) {
      if ($candidate -isnot [string] -or $candidate.Length -lt 4 -or $candidate.Length -gt 240) { throw 'invalid' }
      if ($candidate.Contains(';')) { throw 'invalid' }
      if ($candidate -notmatch '^[A-Za-z]:\\' -or $candidate.Contains('/') -or $candidate.Substring(2).Contains(':') -or $candidate -match '[*?"<>|]' -or $candidate -match '\\(?:\.\.?)(?:\\|$)') { throw 'invalid' }
      foreach ($segment in $candidate.Substring(3).Split([char]'\', [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($segment.EndsWith(' ') -or $segment.EndsWith('.') -or $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') { throw 'invalid' }
      }
      $normalized = [IO.Path]::GetFullPath($candidate)
      if (-not $normalized.Equals($candidate, [StringComparison]::OrdinalIgnoreCase) -or $normalized -match '^[A-Za-z]:\\$') { throw 'invalid' }
      if (Test-NodarisRootWouldBroadenInstall $normalized) { throw 'invalid' }
      if (-not (Test-Path -LiteralPath $normalized -PathType Container) -or -not (Test-NodarisNoReparseComponents $normalized)) { throw 'invalid' }
      foreach ($existing in $roots) {
        if ((Test-NodarisPathWithin $normalized $existing) -or (Test-NodarisPathWithin $existing $normalized)) { throw 'invalid' }
      }
      $roots.Add($normalized)
    }
    return [pscustomobject]@{ schemaVersion = 1; allowedRoots = [string[]]$roots.ToArray() }
  } catch { throw 'NODARIS_ROOT_CONFIG_REJECTED' }
}
