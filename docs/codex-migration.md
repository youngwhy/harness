# Codex Migration Plan

## Decision

Migrate Harness to Codex with a Bash-first adapter while keeping the Claude Code
plugin contract intact. The shared source of truth stays in the existing
`skills/`, `agents/`, and `cli/` directories. Codex-specific files provide a
thin runtime adapter only.

## Scope

In scope for the first migration slice:

- Add a Codex plugin manifest that exposes the shared canonical skills.
- Keep `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh"` as the only writer for `plan.json` state.
- Add Codex native-agent adapters for the Harness logical subagents.
- Add a fixture and smoke script that prove the Bash-first CLI path works.
- Document the Claude/Codex runtime boundary so future work can resume safely.

Out of scope for the first migration slice:

- MCP server implementation.
- Hook parity for session guards, stop hooks, or automatic ultrawork
  transitions.
- Rewriting existing Claude Code skills or agents.
- Full multi-worker `/execute` parity.

## Runtime Model

Harness has four layers:

| Layer | Shared? | Claude Code surface | Codex surface |
| --- | --- | --- | --- |
| CLI | Yes | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh"` via Bash | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh"` via Bash |
| Skills | Yes, canonical markdown | `/skill-name` plugin commands | plugin-loaded canonical skills or `$harness-*` compatibility wrappers |
| Agents | Yes, canonical markdown | `Agent(subagent_type=...)` | native agent adapter TOML |
| Hooks | No, later | Claude hooks | excluded from v1 |

The compatibility rule is: skills and agents express the Harness protocol once,
then each runtime chooses the appropriate execution surface.

## Bash-First Rule

Codex v1 does not use MCP. Every state mutation goes through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh"`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" req init <spec_dir> --type <type> --goal "<goal>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan init <spec_dir> --type <type>
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan merge <spec_dir> --patch --json "$(cat payload.json)"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan task <spec_dir> --status T1=done --summary "..."
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan validate <spec_dir>
```

Agents and skills must not edit `plan.json` directly. Temporary JSON payload
files are preferred over inline string construction when payloads are non-trivial.

## Subagent Compatibility

Keep existing logical subagent names in the Harness protocol. Codex adapter names
may be prefixed to avoid collisions with built-in roles.

| Logical agent | Claude Code | Codex adapter |
| --- | --- | --- |
| `code-explorer` | `Agent(subagent_type="code-explorer")` | `harness-code-explorer` |
| `worker` | `Agent(subagent_type="worker")` | `harness-worker` |
| `verifier` | `Agent(subagent_type="verifier")` | `harness-verifier` |
| `code-reviewer` | `Agent(subagent_type="code-reviewer")` | `harness-code-reviewer` |
| `browser-explorer` | `Agent(subagent_type="harness:browser-explorer")` | `harness-browser-explorer` |
| `docs-researcher` | `Agent(subagent_type="docs-researcher")` | `harness-docs-researcher` |
| `external-researcher` | `Agent(subagent_type="external-researcher")` | `harness-external-researcher` |

The canonical prompt remains in `agents/*.md`. Codex TOML files are adapters
that point back to those prompts. Executable canonical agents have matching
`harness-*` adapters; `_karpathy.md` remains a shared prompt fragment rather
than a spawnable agent.

## Model Portability

Codex adapters do not pin `model` or `model_reasoning_effort`. Codex resolves
those values from an explicit spawn override, the user's `[agents]` defaults,
or the parent session. This avoids coupling Harness releases to one model name
or to model availability for a specific account.

Claude-only `model: haiku|sonnet|opus` frontmatter stays in canonical
`agents/*.md` files for Claude Code. Codex does not translate or reuse those
values; the TOML adapter is the runtime boundary.

## Migration Phases

### Phase 1: Plugin shell

- Add `.codex-plugin/plugin.json`.
- Expose the required `skills: "./skills/"` plugin path so Codex loads the
  canonical skills through the plugin namespace.
- Keep `codex/skills/harness-*` as prefixed compatibility wrappers for direct
  installation into `${CODEX_HOME:-~/.codex}/skills/`.
- Do not declare `mcpServers` yet.
- Keep `.claude-plugin/plugin.json` unchanged.

Validation:

- JSON parses.
- Manifest points at existing `codex/skills/`.

### Phase 2: Agent adapters

- Add Codex adapter TOMLs under `codex/agents/`.
- Provide one `harness-*` adapter for every spawnable canonical agent.
- Keep `_karpathy.md` as a shared prompt fragment without an adapter.
- Preserve the canonical markdown prompts under `agents/`.
- Let adapters inherit the active Codex model and reasoning effort.

Validation:

- `scripts/codex-adapters-smoke.sh` exits 0.
- TOML files are syntactically parseable.
- Each adapter references an existing canonical prompt path.
- No adapter pins `model` or `model_reasoning_effort`.

### Phase 3: Bash-first CLI smoke

- Add a fixture under `fixtures/codex-migration/todo-toggle/`.
- Add `scripts/codex-blueprint-smoke.sh`.
- The script copies the fixture to a temp directory, initializes `plan.json`,
  merges a payload, validates it, mutates a task, and validates again.

Validation:

- `scripts/codex-blueprint-smoke.sh` exits 0.
- `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan validate` passes after init/merge and after task mutation.

### Phase 4: Skill runtime annotations

- Add a `Runtime Surface` section to `skills/blueprint/SKILL.md`.
- Then repeat for `skills/execute/SKILL.md` and `skills/specify/SKILL.md`.
- Do not remove Claude Code instructions; classify them by runtime.

Validation:

- Existing Claude instructions remain available.
- Codex instructions state Bash-first and no-hook assumptions.

### Phase 5: Execute parity

- Keep single-worker execution as the baseline smoke path.
- Use `harness-worker` for task execution and `harness-verifier` for final checks.
- Parallel execution may use `spawn_agent(agent_type="harness-worker")` for
  disjoint `parallel_safe` tasks when the adapter is prompt-visible.
- Treat `scripts/codex-execute-smoke.sh` as plan-state validation only; it does
  not prove parallel subagent behavior.

Validation:

- Pending/running/done/blocked state changes happen only through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh"`.
- A failed worker leaves a recoverable `failed` or `blocked` task status.
- `scripts/codex-execute-smoke.sh` exits 0 and validates the plan after
  single-worker task completion.

### Phase 6: Native adapter install

- Install `codex/agents/*.toml` into `${CODEX_HOME:-~/.codex}/agents/` only
  through `scripts/install-codex-agent-adapters.sh`.
- Resolve `__HARNESS_PLUGIN_ROOT__` in installed adapters so canonical prompts
  remain readable when Codex runs in another repository.
- Restart Codex before assuming the new adapter names are available in the
  current session.

Validation:

- The install script reports all copied adapter files.
- A new Codex session exposes the `harness-*` adapter names before `/execute`
  dispatch depends on them.

### Phase 7: Skill adapter install

- Add prefixed Codex skill wrappers under `codex/skills/harness-*`.
- Keep the canonical workflow bodies in `skills/specify`, `skills/blueprint`,
  and `skills/execute`.
- Install wrappers into `${CODEX_HOME:-~/.codex}/skills/` through
  `scripts/install-codex-skill-adapters.sh`.
- Use prefixed names to avoid collisions with generic skills:
  `$harness-specify`, `$harness-blueprint`, and `$harness-execute`.

Validation:

- Installed wrappers contain resolved absolute canonical skill paths.
- A new Codex session exposes `$harness-*` in skill discovery.

### Phase 8: Research/browser adapters

- Add prefixed Codex wrappers for research/browser skills:
  `$harness-dev-scan`, `$harness-browser-work`, `$harness-deep-research`,
  `$harness-google-search`, and `$harness-reference-seek`.
- Add native-agent adapters for `browser-explorer`, `docs-researcher`, and
  `external-researcher`.
- Keep chromux, Gemini, `gh`, and vendor scripts as Bash-first channels.
- Treat optional sources such as ProductHunt and Gemini as degradable when
  credentials or binaries are missing.

Validation:

- `scripts/codex-research-smoke.sh` exits 0.
- Installed wrappers contain resolved absolute canonical skill paths.
- A new Codex session exposes the `$harness-*` research skill names and
  `harness-*` research agent names.

## Resume Checklist

When resuming this migration:

1. Run `git status --short`.
2. Run `scripts/codex-adapters-smoke.sh`.
3. Run `scripts/codex-blueprint-smoke.sh`.
4. Run `scripts/codex-execute-smoke.sh`.
5. Run `scripts/codex-research-smoke.sh`.
6. Confirm `.codex-plugin/plugin.json` still exposes `skills`.
7. Confirm every spawnable `agents/*.md` has a `codex/agents/harness-*.toml`.
8. Run `scripts/install-codex-agent-adapters.sh`.
9. Run `scripts/install-codex-skill-adapters.sh`.
10. Confirm installed adapters contain no unresolved `__HARNESS_PLUGIN_ROOT__`.
11. Continue with true native-adapter dispatch after restarting Codex.

## MCP Reconsideration Gate

Do not add MCP until at least one of these is repeatedly observed:

- CLI JSON quoting failures.
- Race conditions around multi-agent task status updates.
- Shell output parsing becomes a recurring source of bugs.
- Codex App/CLI surfaces need a non-shell state API.

If MCP becomes necessary, start with only:

- `harness_plan_get`
- `harness_plan_validate`
- `harness_task_status`
- `harness_task_claim`
