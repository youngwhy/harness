# Codex Plugin Architecture

## Decision

Harness uses one canonical source for Claude Code and Codex:

- `skills/` contains workflow instructions.
- `agents/` contains the 27 specialized role prompts.
- `scripts/cli.sh` is the only writer for Harness plan state.
- `codex/PLUGIN_RUNTIME.md` translates Claude-oriented orchestration examples
  to the native tools exposed by the current Codex session.

No Codex-specific agent TOMLs, skill wrappers, model pins, or post-install
scripts are required.

## Installation

```bash
codex plugin marketplace add youngwhy/harness
codex plugin add harness@youngwhy
```

Start a new Codex thread after installation. Skills are available under the
plugin namespace, for example:

```text
$harness:specify
$harness:blueprint
$harness:execute
$harness:agent code-explorer map the authentication flow
```

## Runtime Boundary

| Layer | Claude Code | Codex |
| --- | --- | --- |
| Skills | Canonical `skills/*/SKILL.md` | Same canonical files through the plugin |
| Roles | Registered logical agent type | Read `agents/<role>.md`, then pass it to the current native subagent tool |
| Teams | `TeamCreate`, `Task*`, `SendMessage` | Parent-owned orchestration and native messaging when available |
| Hooks | Claude hook lifecycle | Suppressed by `claude-only-hook.sh`; use explicit bounded loops |
| State | `scripts/cli.sh` | Same Bash CLI through the resolved plugin root |

The current native subagent tool schema is authoritative. Harness does not
assume an `agent_type` field or pin a model. Spawned agents inherit the current
Codex runtime defaults unless the user explicitly chooses otherwise.

If Codex exposes no native subagent tool, a skill performs the smallest safe
direct pass and reports the fallback.

Bundled Claude hooks are routed through `scripts/claude-only-hook.sh`. The
wrapper exits silently when `CODEX_THREAD_ID` is present, preventing hook
context injection and Claude-specific session state in Codex.

## Plugin Root

Codex resolves the plugin root from `PLUGIN_ROOT`, compatibility
`CLAUDE_PLUGIN_ROOT`, or the active skill source path. Commands and subagent
messages use the resolved absolute path, so no global copy under
`~/.codex/agents/` is necessary.

## State Rule

Never edit `plan.json` directly. All changes go through:

```bash
bash "<plugin-root>/scripts/cli.sh" plan ...
```

## Validation

```bash
bash scripts/codex-plugin-runtime-smoke.sh
bash scripts/codex-blueprint-smoke.sh
bash scripts/codex-execute-smoke.sh
bash scripts/codex-research-smoke.sh
```

The research smoke also checks optional local browser dependencies and may
report a missing `chromux` installation independently of plugin correctness.
