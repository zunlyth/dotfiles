<#
.SYNOPSIS
    Install mise-en-place on Windows from the official GitHub release.

.DESCRIPTION
    Downloads the windows-x64 release asset, verifies it against the published
    SHASUMS256.txt, extracts it to a user-scope directory and adds it to the user
    PATH. No admin required.

    Safe to re-run; an existing install is replaced only after the new download
    verifies.

.PARAMETER Version
    Release tag to install, e.g. 'v2026.10.15', or 'latest' (default).

.PARAMETER InstallDir
    Target directory. Defaults to %LOCALAPPDATA%\Programs\mise.

.EXAMPLE
    .\bootstrap\mise.ps1
    .\bootstrap\mise.ps1 -Version v2026.10.15
#>
[CmdletBinding()]
param(
    [string]$Version = 'latest',
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\mise')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

if ($pwd.Provider.Name -ne 'FileSystem') { throw 'Run this from a normal PowerShell prompt.' }

# ---------------------------------------------------------------- resolve tag
if ($Version -eq 'latest') {
    Write-Host 'Resolving latest mise release ...'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/jdx/mise/releases/latest' `
        -Headers @{ 'User-Agent' = 'dotfiles-bootstrap' } -TimeoutSec 30
    $tag = $rel.tag_name
} else {
    $tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
}

$asset = "mise-$tag-windows-x64.zip"
$base  = "https://github.com/jdx/mise/releases/download/$tag"
$tmp   = Join-Path $env:TEMP ('mise-boot-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    # ------------------------------------------------------------ download
    Write-Host "Downloading $asset ..."
    curl.exe -L --fail --silent --show-error --retry 3 -o (Join-Path $tmp $asset) "$base/$asset"
    if ($LASTEXITCODE -ne 0) { throw "download failed ($LASTEXITCODE)" }
    curl.exe -L --fail --silent --show-error --retry 3 -o (Join-Path $tmp 'SHASUMS256.txt') "$base/SHASUMS256.txt"
    if ($LASTEXITCODE -ne 0) { throw "checksum download failed ($LASTEXITCODE)" }

    # -------------------------------------------------------------- verify
    $line = Select-String -Path (Join-Path $tmp 'SHASUMS256.txt') -Pattern ([regex]::Escape($asset) + '$') |
        Select-Object -First 1
    if (-not $line) { throw "no checksum entry for $asset" }
    $want = $line.Line.Split(' ')[0].Trim()
    $got  = (Get-FileHash (Join-Path $tmp $asset) -Algorithm SHA256).Hash.ToLower()
    if ($want -ne $got) { throw "SHA256 mismatch!`n  expected $want`n  actual   $got" }
    Write-Host "  SHA256 verified: $got"

    # ------------------------------------------------------------- extract
    Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath (Join-Path $tmp 'x') -Force
    $src = Join-Path $tmp 'x\mise'
    if (-not (Test-Path (Join-Path $src 'bin\mise.exe'))) { throw 'unexpected archive layout (no mise\bin\mise.exe)' }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Copy-Item (Join-Path $src '*') -Destination $InstallDir -Recurse -Force
    Write-Host "  installed to $InstallDir"

    # ---------------------------------------------------------------- PATH
    $bin = Join-Path $InstallDir 'bin'
    $key  = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $raw  = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $kind = $key.GetValueKind('Path')
    $parts = @($raw -split ';' | Where-Object { $_ -ne '' })
    if ($parts -notcontains $bin) {
        $key.SetValue('Path', (($bin + ';' + ($parts -join ';'))), $kind)
        Write-Host "  added to user PATH: $bin"
    } else {
        Write-Host "  already on user PATH: $bin"
    }
    $key.Close()

    Write-Host ''
    Write-Host "mise $tag installed. Next:"
    Write-Host '  1. restart Windows Terminal (so PATH is inherited)'
    Write-Host '  2. .\bootstrap\install-tools.ps1'
    Write-Host '  3. .\install.ps1'
} finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
