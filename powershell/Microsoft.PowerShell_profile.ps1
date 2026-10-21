# =============================================================================
# PowerShell 7 profile
# Created during mise-en-place setup. Safe to edit or extend.
# =============================================================================

#region mise (mise-en-place)
# Activates mise version management for this shell: it prepends the bin paths of
# the tools pinned in ~/.config/mise/config.toml (globally) or the nearest
# mise.toml (per project) and exports their environment variables.
#
# The PATH guard keeps this idempotent if the profile is re-dotted in a session.
$MiseBinDir = Join-Path $env:LOCALAPPDATA 'Programs\mise\bin'
if ((Test-Path (Join-Path $MiseBinDir 'mise.exe')) -and ($env:PATH -notlike "*$MiseBinDir*")) {
    $env:PATH = "$MiseBinDir;$env:PATH"
}

if (Get-Command mise -ErrorAction SilentlyContinue) {
    (& mise activate pwsh) | Out-String | Invoke-Expression
}
#endregion

#region herdr (auto-launch)
# Opens herdr (the terminal workspace manager) automatically in a new terminal.
# `herdr` launches or attaches to the persistent session, so a second terminal
# attaches to the same session instead of starting an empty one.
#
# Deliberately skipped when any of these is true:
#   * HERDR_ENV=1     -> already inside a herdr pane. Without this guard, every
#                        pane shell would launch herdr inside herdr, recursively.
#                        herdr sets this for every process in a pane.
#   * redirected I/O  -> scripts, `pwsh -Command`, build tasks, MCP servers and
#                        other automation must never open an interactive TUI.
#   * IDE terminals   -> VS Code / JetBrains panels keep their normal shell.
#   * HERDR_AUTOSTART=0 -> manual override for a plain shell (set it in your
#                        environment or run `$env:HERDR_AUTOSTART='0'` first).
#
# When you quit herdr you land in a normal shell prompt, so nothing is lost.
if ($env:HERDR_ENV -ne '1' -and
    $env:HERDR_AUTOSTART -ne '0' -and
    -not [Console]::IsInputRedirected -and
    -not [Console]::IsOutputRedirected -and
    $env:TERM_PROGRAM -ne 'vscode' -and
    $env:TERMINAL_EMULATOR -notlike 'JetBrains*') {

    if (Get-Command herdr -ErrorAction SilentlyContinue) {
        try {
            herdr
        } catch {
            Write-Warning "herdr failed to start: $($_.Exception.Message)"
        }
    }
}
#endregion
