# dotfiles — Windows 10 IoT LTSC · PowerShell 7 · mise

Configuration for this Windows development machine. Tool **versions** are owned by
[mise](https://mise.jdx.dev); this repo records *which* tools, and the shell /
agent / git behaviour around them.

## Layout

| Path in repo | Installs to | Purpose |
|---|---|---|
| `mise/config.toml` | `~/.config/mise/config.toml` | Global tool pins (node, bun, rust, java, pnpm, git, git-lfs, gh, claude, herdr, ghidra) |
| `mise/extract-git-full.py` | `~/.config/mise/extract-git-full.py` | Workaround: extract Git for Windows' `.tar.bz2` without symlink privilege |
| `powershell/Microsoft.PowerShell_profile.ps1` | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` | mise activation + guarded herdr auto-launch |
| `git/.gitconfig` | `~/.gitconfig` | `init.defaultBranch=main`, `core.autocrlf=input`, 10 aliases, LFS filters |
| `claude/settings.json.template` | `~/.claude/settings.json` | `DISABLE_UPDATES=1` (mise owns the version) + Git Bash path for the Bash tool |
| `herdr/config.toml` | `%APPDATA%\herdr\config.toml` | herdr preferences |
| `gh/config.yml` | `%APPDATA%\GitHub CLI\config.yml` | gh preferences and aliases (no credentials) |
| `bootstrap/mise.ps1` | — | Install mise from the official release, SHA-256 verified |
| `bootstrap/install-tools.ps1` | — | `mise install`, reshim, user env vars |
| `docs/windows-toolchain.md` | — | Native prerequisites mise cannot provide (MSVC, WebView2, Ghidra, caveats) |
| `docs/rea-mcp-registration.md` | — | REA MCP registration + tool-catalog sizing notes |

## Apply to this machine

```powershell
cd C:\Users\<you>\code\dotfiles
.\install.ps1                 # copies configs, backing up anything replaced
```

`install.ps1` is idempotent, compares hashes before overwriting, and stores every
replaced file under `%LOCALAPPDATA%\dotfiles-backups\<timestamp>\`.

### Fresh machine, nothing installed yet

```powershell
.\bootstrap\mise.ps1           # mise -> %LOCALAPPDATA%\Programs\mise (+ user PATH)
.\bootstrap\install-tools.ps1  # mise install from mise/config.toml, reshim, env vars
.\install.ps1                  # shell / git / agent configs
```

Then complete the native prerequisites in `docs/windows-toolchain.md` (MSVC Build
Tools needs an elevated install; mise cannot do it).

## What this repo deliberately does NOT contain

These exist on the machine but must never be committed — they carry live
credentials or unique machine state:

| File | Why excluded |
|---|---|
| `%APPDATA%\GitHub CLI\hosts.yml` | gh OAuth token |
| `~/.claude.json` | Claude Code `oauthAccount`, `userID`, `machineID`, MCP registration state |
| `~/.dsh/.credentials.yaml` | harness credentials |
| `~/.git-credentials` | plaintext git credentials (should not exist at all) |
| `%APPDATA%\herdr\session.json`, `session-snapshots\` | live session data |

Secrets are re-established interactively: `gh auth login`, `claude` (browser
login), never by copying files.

## Machine assumptions

- Windows 10/11 x64, PowerShell 7 (`pwsh`), Windows Terminal
- User-scope installs only — no admin required except the MSVC Build Tools step
- mise owns PATH via `%LOCALAPPDATA%\Programs\mise\bin` and `%LOCALAPPDATA%\mise\shims`

## Restore trigger

After `install.ps1`, **restart Windows Terminal** so the new user environment
(PATH, `GHIDRA_INSTALL_DIR`) is inherited by new shells.
