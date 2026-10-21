<#
.SYNOPSIS
    Apply this dotfiles repo to the current Windows machine.

.DESCRIPTION
    Copies/merges configuration into place, backing up every file it replaces to
    %LOCALAPPDATA%\dotfiles-backups\<timestamp>\. Safe to re-run: files whose hash
    already matches are left alone.

    Never touches credentials - see README.md for the excluded files.

.PARAMETER SkipEnv
    Do not modify user environment variables (PATH, GHIDRA_INSTALL_DIR).

.EXAMPLE
    .\install.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipEnv
)

$ErrorActionPreference = 'Stop'
$repo    = $PSScriptRoot
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup  = Join-Path $env:LOCALAPPDATA "dotfiles-backups\$stamp"
$changed = [System.Collections.Generic.List[string]]::new()

$docs     = [Environment]::GetFolderPath('MyDocuments')
$homeDir  = $env:USERPROFILE
$appData  = $env:APPDATA
$localApp = $env:LOCALAPPDATA

function Backup-Existing {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    $flat = ($Path -replace '^[A-Za-z]:\\', '') -replace '[\\/:*?"<>|]', '_'
    Copy-Item $Path (Join-Path $backup "$flat.bak") -Force
    Write-Host "      backed up -> $backup\$flat.bak"
}

function Install-Config {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not (Test-Path $Source)) { Write-Warning "missing source for ${Label}: $Source"; return }

    $dir = Split-Path $Target -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    if ((Test-Path $Target) -and
        ((Get-FileHash $Source).Hash -eq (Get-FileHash $Target).Hash)) {
        Write-Host "      unchanged  $Label"
        return
    }
    Backup-Existing $Target
    Copy-Item $Source $Target -Force
    $changed.Add($Label)
    Write-Host "      installed  $Label -> $Target"
}

function Get-GitBashPath {
    $candidates = @(
        (Join-Path $localApp 'mise\installs\github-git-for-windows-git\latest\bin\bash.exe'),
        'C:\Program Files\Git\bin\bash.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-ClaudeSettings {
    $tpl  = Join-Path $repo 'claude\settings.json.template'
    $dest = Join-Path $homeDir '.claude\settings.json'
    if (-not (Test-Path $tpl)) { Write-Warning 'claude template missing'; return }

    $gitBash = Get-GitBashPath
    if (-not $gitBash) {
        Write-Warning 'bash.exe not found - the Bash tool path will be left blank.'
        $gitBash = ''
    }
    # backslashes must be escaped to stay valid JSON
    $rendered = (Get-Content $tpl -Raw).Replace('{{CLAUDE_CODE_GIT_BASH_PATH}}', $gitBash.Replace('\', '\\'))
    $incoming = $rendered | ConvertFrom-Json

    if (Test-Path $dest) {
        # merge: keep keys Claude Code added itself (theme, plugins, ...)
        $current = Get-Content $dest -Raw | ConvertFrom-Json
        foreach ($p in $incoming.PSObject.Properties) {
            $current | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
        }
        $merged = $current
    } else {
        $merged = $incoming
    }

    $dir = Split-Path $dest -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Backup-Existing $dest
    ($merged | ConvertTo-Json -Depth 20) + "`n" | Set-Content -Path $dest -Encoding utf8 -NoNewline
    $changed.Add('claude settings.json')
    Write-Host "      installed  claude settings.json -> $dest (bash: $gitBash)"
}

function Add-UserPathEntry {
    param([string]$Entry, [string]$Label)
    if (-not (Test-Path $Entry)) { Write-Host "      skipped    $Label (not installed yet: $Entry)"; return }
    $key  = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $raw  = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $kind = $key.GetValueKind('Path')
    $parts = @($raw -split ';' | Where-Object { $_ -ne '' })
    if ($parts -contains $Entry) {
        $key.Close(); Write-Host "      ok         $Label already on PATH"; return
    }
    $key.SetValue('Path', (($Entry + ';' + ($parts -join ';'))), $kind)
    $key.Close()
    $changed.Add("PATH: $Label")
    Write-Host "      added      $Label -> $Entry"
}

function Set-UserVariable {
    param([string]$Name, [string]$Value)
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $current = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if ($current -eq $Value) { $key.Close(); Write-Host "      ok         $Name already set"; return }
    $key.SetValue($Name, $Value, 'String')
    $key.Close()
    $changed.Add("env: $Name")
    Write-Host "      set        $Name = $Value"
}

function Send-EnvChange {
    if (-not ('Win32.NativeMethods' -as [type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $r = [UIntPtr]::Zero
    [void][Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r)
}

Write-Host "`n=== dotfiles install ($repo) ==="
Write-Host "  backups: $backup`n"

Write-Host '[ configs ]'
Install-Config (Join-Path $repo 'mise\config.toml')            (Join-Path $homeDir '.config\mise\config.toml') 'mise config.toml'
Install-Config (Join-Path $repo 'mise\extract-git-full.py')    (Join-Path $homeDir '.config\mise\extract-git-full.py') 'mise git extractor'
Install-Config (Join-Path $repo 'git\.gitconfig')              (Join-Path $homeDir '.gitconfig') 'git .gitconfig'
Install-Config (Join-Path $repo 'powershell\Microsoft.PowerShell_profile.ps1') (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1') 'pwsh profile'
Install-Config (Join-Path $repo 'herdr\config.toml')           (Join-Path $appData 'herdr\config.toml') 'herdr config.toml'
Install-Config (Join-Path $repo 'gh\config.yml')               (Join-Path $appData 'GitHub CLI\config.yml') 'gh config.yml'
Install-ClaudeSettings

if (-not $SkipEnv) {
    Write-Host "`n[ user environment ]"
    Add-UserPathEntry (Join-Path $localApp 'Programs\mise\bin') 'mise bin'
    Add-UserPathEntry (Join-Path $localApp 'mise\shims')         'mise shims'

    $ghidra = Join-Path $localApp 'mise\installs\github-national-security-agency-ghidra\Ghidra_latest'
    if (Test-Path $ghidra) { Set-UserVariable 'GHIDRA_INSTALL_DIR' $ghidra }
    else { Write-Host '      skipped    GHIDRA_INSTALL_DIR (ghidra not installed yet)' }

    Send-EnvChange
}

Write-Host "`n=== summary ==="
if ($changed.Count -eq 0) {
    Write-Host '  everything already up to date - nothing changed.'
} else {
    Write-Host "  $($changed.Count) change(s):"
    $changed | ForEach-Object { Write-Host "    - $_" }
    if (Test-Path $backup) { Write-Host "`n  replaced files backed up in: $backup" }
    Write-Host "`n  Restart Windows Terminal so new shells pick up environment changes."
}
