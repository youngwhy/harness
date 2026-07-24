---
name: agent
description: |
  Dispatch one of Harness's 27 specialized role prompts for a focused task.
  Use as `$harness:agent ROLE TASK`, for example
  `$harness:agent code-explorer map the authentication flow`.
allowed-tools:
  - Read
  - Agent
  - Task
---

# Harness Agent

Run one focused task with a canonical Harness specialist.

## Invocation

```text
$harness:agent <role> <task>
```

Examples:

```text
$harness:agent code-explorer map the authentication flow
$harness:agent debugger find the root cause of this failing test
$harness:agent tradeoff-analyzer compare these two cache designs
```

## Available Roles

`browser-explorer`, `business-extractor`, `clarity-auditor`, `code-explorer`,
`code-reviewer`, `codex-strategist`, `contract-deriver`, `debugger`,
`docs-researcher`, `external-researcher`, `gap-analyzer`, `gap-auditor`,
`git-master`, `interaction-extractor`, `interviewer`, `qa-verifier`,
`ralph-strategist`, `ralph-verifier`, `spec-coverage`, `taskgraph-planner`,
`tech-extractor`, `tradeoff-analyzer`, `ux-reviewer`,
`verification-planner`, `verifier`, `verify-planner`, `worker`.

## Runtime Surface

### Claude Code

- Validate that `<role>` matches an existing `agents/<role>.md`.
- Dispatch `Agent(subagent_type="<role>")` with the requested task.

### Codex

- Read and apply `codex/PLUGIN_RUNTIME.md`.
- Validate that `<role>` matches an existing canonical prompt. Never accept a
  path, slash, or role name outside the list above.
- Dispatch the role with the current native subagent tool and the canonical
  `agents/<role>.md` prompt.

## Protocol

1. Parse the first argument as `role` and the remainder as `task`.
2. If either is missing, show the invocation format and stop.
3. Resolve the canonical role prompt without accepting path traversal.
4. Give the specialist read-only access unless the task explicitly requires
   edits. Keep any write boundary narrow and explicit.
5. Include the user's full task and requested output format.
6. Do not delegate recursively.
7. Wait for the result and return it with the role name.
