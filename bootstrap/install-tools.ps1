<#
.SYNOPSIS
    Install every tool pinned in mise/config.toml and wire up the user environment.

.DESCRIPTION
    Runs `mise install` for the repo's global config, refreshes shims, derives
    GHIDRA_INSTALL_DIR from the mise install tree, and reports `mise doctor`.

    Prerequisite: mise is installed (see bootstrap/mise.ps1) and install.ps1 has
    already placed mise/config.toml, OR you pass -SkipInstall.

.PARAMETER SkipInstall
    Only refresh shims / env vars; do not run `mise install`.

.EXAMPLE
    .\bootstrap\install-tools.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

$bin = Join-Path $env:LOCALAPPDATA 'Programs\mise\bin'
if ($env:PATH -notlike "*$bin*") { $env:PATH = "$bin;$env:PATH" }

$mise = Get-Command mise -ErrorAction SilentlyContinue
if (-not $mise) {
    throw 'mise not found. Run .\bootstrap\mise.ps1 first, then restart the terminal.'
}

Write-Host "mise $(& mise --version)"
Write-Host "global config: $env:USERPROFILE\.config\mise\config.toml"
if (-not (Test-Path "$env:USERPROFILE\.config\mise\config.toml")) {
    throw 'mise config.toml not found. Run .\install.ps1 first.'
}

if (-not $SkipInstall) {
    Write-Host "`n=== mise install ==="
    & mise install
    if ($LASTEXITCODE -ne 0) { Write-Warning "mise install reported exit code $LASTEXITCODE" }
}

Write-Host "`n=== reshim ==="
& mise reshim

Write-Host "`n=== user environment ==="
$shims = Join-Path $env:LOCALAPPDATA 'mise\shims'
$key   = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$raw   = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$kind  = $key.GetValueKind('Path')
$parts = @($raw -split ';' | Where-Object { $_ -ne '' })
if ($parts -notcontains $shims) {
    $key.SetValue('Path', (($shims + ';' + ($parts -join ';'))), $kind)
    Write-Host "  added to user PATH: $shims"
} else {
    Write-Host "  already on user PATH: $shims"
}
$key.Close()

$ghidra = Join-Path $env:LOCALAPPDATA 'mise\installs\github-national-security-agency-ghidra\Ghidra_latest'
if (Test-Path $ghidra) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $key.SetValue('GHIDRA_INSTALL_DIR', $ghidra, 'String')
    $key.Close()
    Write-Host "  GHIDRA_INSTALL_DIR = $ghidra"
} else {
    Write-Host '  GHIDRA_INSTALL_DIR skipped (ghidra not installed)'
}

Write-Host "`n=== mise doctor ==="
& mise doctor

Write-Host @'

Reminder - mise cannot install these; see docs/windows-toolchain.md:
  * Microsoft C++ Build Tools + Windows SDK   (elevated install, required by Rust/Tauri)
  * WebView2 runtime                          (required by Tauri)
  * Developer Mode                            (optional: enables native git tarball install)

Restart Windows Terminal so new shells pick up the environment.
'@
