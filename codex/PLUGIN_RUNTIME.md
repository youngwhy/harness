# Codex Plugin Runtime

This contract applies when a Harness skill runs inside Codex. Claude Code keeps
using the canonical `Agent`, `Task`, `TeamCreate`, and hook instructions written
in each skill.

## Resolve the Plugin Root

Resolve the Harness plugin root in this order:

1. `PLUGIN_ROOT`, when the Codex plugin runtime provides it.
2. `CLAUDE_PLUGIN_ROOT`, when compatibility context provides it.
3. The parent of the active skill's `skills/<skill>/` directory.

Use the resolved absolute path literally in commands and subagent messages.
Do not assume an environment variable survives into a shell or subagent.

## Dispatch Canonical Roles

Harness role prompts live at `<plugin-root>/agents/<logical-role>.md`. For every
canonical `Agent(...)` or `Task(...)` instruction:

1. Read the canonical role prompt.
2. Use the native subagent spawn tool exposed by the current Codex session.
3. Use only fields present in that tool's live schema. In particular, do not
   assume an `agent_type` field exists.
4. Derive a short task name from the logical role and task ID.
5. Include in the message:
   - the absolute canonical role prompt path and an instruction to read it;
   - the concrete task, inputs, constraints, and expected output;
   - explicit read/write boundaries;
   - `Do not delegate recursively.`
6. Wait for every required result before continuing.

A common Codex tool shape is:

```text
spawn_agent(
  task_name="worker_t1",
  message="Read <plugin-root>/agents/worker.md and follow it as your role. ... Do not delegate recursively."
)
```

The live tool schema is authoritative; the example is not.

## Translate Orchestration

| Canonical instruction | Codex behavior |
| --- | --- |
| `Agent` / `Task` | Spawn with the current native subagent tool and canonical role prompt |
| `TeamCreate` / `TaskCreate` / `TaskUpdate` | Parent-owned orchestration plus Harness CLI plan state |
| `SendMessage` | Current agent messaging tool, or parent relay when unavailable |
| Claude hooks / stop hooks | Explicit bounded loop in the current Codex turn |

Parallel dispatch is allowed only for independent tasks with disjoint write
boundaries. If no native subagent tool is available, perform the smallest safe
direct pass and state the fallback.

## Hook Isolation

The shared package contains Claude Code hooks, but every hook command passes
through `scripts/claude-only-hook.sh`. When `CODEX_THREAD_ID` is present, the
wrapper exits without output or state changes. Codex skills must not depend on
those hooks.

## State Invariant

Never edit `plan.json` directly. Resolve the plugin root and mutate plan state
only through:

```bash
bash "<plugin-root>/scripts/cli.sh" plan ...
```
