# Windows toolchain notes

Things **mise cannot install**, plus the non-obvious failures hit while building
this machine. Recorded so they do not have to be rediscovered.

---

## 1. Microsoft C++ Build Tools + Windows SDK (elevated)

Required by **Rust** on the `x86_64-pc-windows-msvc` target and therefore by
**Tauri**. Without it `cargo build` fails at the link step.

```powershell
# Run elevated (UAC). ~5-7 GB, 6-30 min.
vs_BuildTools.exe --quiet --wait --norestart `
  --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended
```

Verified result on this machine:

| Component | Value |
|---|---|
| Install | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` |
| MSVC | 14.44.35207 |
| Windows SDK | 10.0.26100.0 |
| `link.exe` | `...\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe` |
| Exit code | `0` (no reboot required) |

`rustc` locates the linker on its own via `vswhere.exe` — no `vcvarsall.bat`
needed. Prove it with `cargo new x; cd x; cargo build`.

## 2. Long path support (elevated)

Rust `target/` trees exceed the 260-character limit.

```powershell
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
  -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force
```

Takes effect for newly started processes; no reboot needed.

## 3. WebView2 runtime

Tauri's renderer. Check before installing:

```powershell
Test-Path "$env:LOCALAPPDATA\Microsoft\EdgeWebView\Application"
```

A per-user Evergreen install is sufficient. Windows 10 1803+ usually has it.

## 4. Git for Windows via mise — the symlink trap

`mise use -g 'github:git-for-windows/git[asset_pattern=Git-*-64-bit.tar.bz2,bin_path=bin]'`
installs **full Git for Windows (git + Git Bash)** rather than MinGit, which is
what tooling that needs `bash.exe` requires.

**It fails without admin/Developer Mode:**

```
failed to extract tar: ... A required privilege is not held by the client. (os error 1314)
```

The tarball contains ~97 symlinks; Windows refuses `CreateSymbolicLink` without
`SeCreateSymbolicLinkPrivilege`. Windows' own `tar.exe` cannot help either — it
shells out to a missing `bzip2 -d` filter.

Two ways out:

1. **Enable Developer Mode** (recommended; one admin toggle) — then mise's own
   extraction works and `mise install --force` upgrades normally.
2. **Extract manually** with `mise/extract-git-full.py`, which materializes
   symlinks as real file copies, then place the tree in
   `%LOCALAPPDATA%\mise\installs\github-git-for-windows-git\<version>\`.

   ```powershell
   python "$env:USERPROFILE\.config\mise\extract-git-full.py" `
          "$env:TEMP\Git-full.tar.bz2" `
          "$env:LOCALAPPDATA\mise\installs\github-git-for-windows-git\<version>"
   ```

   The 5 unresolvable links are `dev/{stdin,stdout,stderr,fd}` and `etc/mtab` —
   `/proc/*` pseudo-paths MSYS recreates at runtime. Harmless.

`bin_path = "bin"` is deliberate: that directory holds only `bash.exe`,
`git.exe`, `sh.exe`. Do **not** use `usr\bin` — 84 MSYS binaries there
(`find.exe`, `sort.exe`, `tar.exe`, `ssh.exe`) would shadow Windows tools.

## 5. Java + Ghidra for REA (reverse engineering)

REA's Ghidra doctor requires all of:

| Requirement | Notes |
|---|---|
| Ghidra **12.1.x** only | e.g. `Ghidra_12.1.4_build` via `github:NationalSecurityAgency/ghidra` |
| A **full JDK, 21+** | `javac.exe` must exist; a JRE fails the check |
| `application.java.min` respected | 12.1.4 declares `21` |
| **Native decompiler** | `Ghidra\Features\Decompiler\os\win_x86_64\decompile.exe` — ships for Windows and Linux, **not macOS** |
| `support\analyzeHeadless.bat` | present in the release zip |

Install path used here:

```powershell
mise use -g java@temurin-21     # core:java, Temurin JDK
mise use -g 'github:NationalSecurityAgency/ghidra@Ghidra_12.1.4_build'
```

Then `GHIDRA_INSTALL_DIR` (user env var) points at
`%LOCALAPPDATA%\mise\installs\github-national-security-agency-ghidra\Ghidra_latest`
— the mise junction, so it survives Ghidra upgrades.

Windows caveats: Ghidra support is **experimental P0 and read-only**, and Hopper
is unavailable on Windows entirely.

## 6. herdr: never run it from an elevated terminal

An **elevated** herdr server creates its IPC sockets with a High mandatory
integrity label. A normal (Medium) terminal then gets:

```
herdr: For an elevated server, use an administrator terminal. ... Access is denied. (os error 5)
```

The DACL still lists your account with FullControl — mandatory integrity policy
is what blocks it. Worse, every pane in an elevated server runs **with admin
rights**, including any agent inside it.

Recovery (needs elevation, closes panes):

```powershell
herdr server stop      # from an administrator terminal
```

Then just run `herdr` normally. The state directory to inspect is
`%APPDATA%\herdr`; `session.json` and `session-snapshots\` are safe to keep.

Rule: elevated terminals are for installs only. Never launch herdr (or agents)
from one.

## 7. Tauri checklist

| Requirement | Where |
|---|---|
| Rust with `x86_64-pc-windows-msvc` | mise `rust@stable` (ships rustup) |
| MSVC + Windows SDK | §1 |
| WebView2 | §3 |
| Node + package manager | mise `node@lts`, `pnpm` |
| VBSCRIPT optional feature | needed only for MSI bundles; `vbscript.dll` + `cscript.exe` |

Long first build: the initial `cargo build` of a Tauri app compiles hundreds of
crates (5-15 min). The first `tauri build` downloads WiX/NSIS for installers.
