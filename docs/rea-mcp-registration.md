# REA MCP registration (Claude Code)

[REA — "Reverse Engineer Anything"](https://rea.tools) (`rea-agents` on npm) is an
MCP server + CLI. This records the registration that was reviewed and applied, and
the sizing decision behind it.

## Registration

Stored in `~/.claude.json` under `mcpServers.rea` (that file also holds
`oauthAccount` and other secrets — **it is not in this repo**).

```json
{
  "mcpServers": {
    "rea": {
      "command": "cmd.exe",
      "args": ["/d", "/c", "npx", "-y", "rea-agents@6.5.0", "mcp"],
      "env": {
        "GHIDRA_INSTALL_DIR": "<LOCALAPPDATA>\\mise\\installs\\github-national-security-agency-ghidra\\Ghidra_latest",
        "JAVA_HOME": "<LOCALAPPDATA>\\mise\\installs\\java\\temurin-21.0.12+101.0.LTS",
        "REA_MCP_INPUT_SCHEMA_PROFILE": "compact",
        "REA_MCP_OUTPUT_SCHEMA_PROFILE": "off"
      }
    }
  }
}
```

`<LOCALAPPDATA>` must be a literal absolute path — JSON does not expand `%VAR%`.
On Windows the launcher is wrapped in `cmd.exe /d /c` so a stdio client can start
the `npx` shim.

Regenerate with REA's own reviewed flow:

```powershell
npx -y rea-agents@6.5.0 setup --client claude_code --dry-run --json   # read-only plan
npx -y rea-agents@6.5.0 setup --client claude_code --yes              # apply
npx -y rea-agents@6.5.0 doctor --client claude_code --json            # verify
```

REA's setup **preserves** existing env overrides and re-detects the provider
paths, so the two schema-profile keys survive a re-run. After a Java upgrade,
re-run setup to refresh the `JAVA_HOME` value (it records the concrete version
directory, not the mise alias).

## Why the schema-profile keys matter (measured)

The default catalog is far larger than REA's docs suggest. Measured against the
real server with a JSON-RPC `initialize` + `tools/list` probe:

| Config | Tools | `tools/list` payload | ≈ tokens |
|---|---|---|---|
| default (full input + full output schemas) | 207 | **3,015.6 KB** | ~772k |
| `INPUT_SCHEMA_PROFILE=compact` | 207 | 2,424.3 KB | ~621k |
| **compact + `OUTPUT_SCHEMA_PROFILE=off`** | 207 | **209.8 KB** | **~54k** |

Output schemas are ~90% of the payload. REA's documentation discusses only the
*input* profile and never mentions this. Setting both keys is a **14× reduction**;
REA still validates complete structured results against its canonical contracts,
so only the *advertised* output schemas are omitted.

Relevant when the client sends full tool definitions per request — Claude Code
disables MCP tool search when `ANTHROPIC_BASE_URL` points at a non-first-party
host (e.g. a DeepSeek Anthropic-compatible endpoint), which makes this payload
size directly matter.

## Related

- Install/verify notes: `docs/windows-toolchain.md` §5 (Java + Ghidra)
- The bundled `reverse-engineer-anything` skill lives in `~/.claude/skills/` and
  is installed by REA's setup — it is a package artifact, deliberately not
  vendored here.
