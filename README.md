# agent-isolation-configurations

Common agent configuration for AgentIsolation.

`agentc` clones this repo to `~/.agentc/configurations` and mounts it read-only at
`/agent-isolation/agents` inside the container. Configurations are selected with
`agentc -c <name>[,<name>...]` (default: `claude`).

## Layout

One directory per configuration, named exactly as it is referenced:

```
<name>/
  settings.json   # required
  prepare.sh      # optional
```

## settings.json

```json
{
  "v": 0,
  "dependsOn": ["base"],
  "entrypoint": ["claude"],
  "additionalBinPaths": ["$HOME/.claude/bin", "$HOME/.bun/bin"],
  "additionalMounts": ["/home/agent/.cache/something"]
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `entrypoint` | `[String]` | Command exec'd when the session starts, with the user's CLI args appended. The **last** activated configuration that defines one wins. |
| `dependsOn` | `[String]` | Other configurations to activate first. |
| `additionalBinPaths` | `[String]` | Directories prepended to `PATH`. `$HOME` is expanded (to `/home/agent`). |
| `additionalMounts` | `[String]` | Absolute container paths that get a writable, session-persistent host directory mounted at them. |
| `v` | `Int` | Format version, currently `0`. Informational. |

A missing `settings.json` is an error; unknown fields are ignored.

### dependsOn

Dependencies are activated depth-first, before the configuration that declares them,
and a configuration shared by several dependents is only activated once. So
`agentc -c claude` where `claude` dependsOn `base` behaves exactly like
`agentc -c base,claude`.

Because the entrypoint comes from the last configuration that defines one, a
configuration can depend on another purely to extend its setup — omit `entrypoint`
and the dependency's is used:

```json
{ "v": 0, "dependsOn": ["claude"] }
```

A `dependsOn` loop is an error, as is depending on a configuration that does not exist.

### additionalMounts

Use these for state that must survive a session but lives outside `$HOME` (which is
already persistent). Each path is backed by a host directory under
`~/.agentc/profiles/<profile>/additionalMounts/<basename>-<hash>`, created
automatically and shared by every session using that profile.

## prepare.sh

Run once per session start, before the entrypoint, for each selected configuration in order.

- Runs inside the container as the unprivileged `agent` user; `sudo` is NOPASSWD.
- Executed directly if it has a shebang + exec bit, otherwise via `/bin/bash` (or `/bin/sh`).
- `PATH` already includes `additionalBinPaths` from this and previous configurations.
- Must be **idempotent and non-interactive** — guard installs with `command -v`, since
  `$HOME` persists across sessions and re-running should be near-instant.
- A non-zero exit aborts the session. Progress is announced only with `agentc -v`.

```sh
if ! command -v claude &>/dev/null; then
  echo "==> Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi
```

## Composition

`agentc -c base,claude` processes configurations left to right, after expanding
`dependsOn`: each one's `additionalBinPaths` are prepended to `PATH` (so later
configurations win), its `prepare.sh` runs, and its `additionalMounts` are mounted.
The final `exec` uses the last `entrypoint` defined, so put the agent you actually
want to launch last.
