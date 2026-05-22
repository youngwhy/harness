---
name: harness-execute
description: |
  Harness execution workflow for Codex. Use when the user invokes
  "$harness-execute" or wants to execute a Harness plan.json through the
  Bash-first Codex adapter. This adapter loads the canonical execute skill and
  follows its Codex runtime surface.
---

# harness-execute

This is the Codex-facing wrapper for Harness's canonical `execute` skill.

Canonical skill:
- Installed root: `__HARNESS_PLUGIN_ROOT__/skills/execute/SKILL.md`
- Repo-local fallback: `skills/execute/SKILL.md` from the current Harness repo

When this skill is invoked:

1. Read the canonical skill file above before executing the workflow.
2. Follow the `Runtime Surface` -> `Codex` section in that file.
3. Mutate task state only through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan task`.
4. Do not edit `plan.json` directly.
5. Do not rely on hooks, MCP, or Claude `TeamCreate` for Codex v1.
6. Use Harness native-agent adapter names when dispatching subagents:
   - `worker` -> `harness-worker`
   - `verifier` -> `harness-verifier`
   - `code-reviewer` -> `harness-code-reviewer`
7. In Codex, dispatch those adapters with the native `spawn_agent` tool:
   - `spawn_agent(agent_type="harness-worker", message="<worker charter>")`
   - `spawn_agent(agent_type="harness-verifier", message="<verification charter>")`
   - `spawn_agent(agent_type="harness-code-reviewer", message="<review charter>")`
8. Treat canonical `Agent(...)`, `TaskCreate`, `TaskUpdate`, `TaskOutput`, and
   `TeamCreate` examples as Claude Code protocol notes, not literal Codex calls.
9. Parallel worker dispatch is allowed for disjoint `parallel_safe` tasks when
   the relevant adapter is prompt-visible. `scripts/codex-execute-smoke.sh`
   validates plan state transitions only, not parallel subagent behavior.

The output contract remains the canonical Harness contract:
all executable tasks completed or blocked with evidence, followed by plan
validation.
