---
name: harness-blueprint
description: |
  Harness blueprint workflow for Codex. Use when the user invokes
  "$harness-blueprint" or wants to turn requirements.md into a validated
  plan.json and optional contracts.md. This adapter loads the canonical
  blueprint skill and follows its Codex runtime surface.
---

# harness-blueprint

This is the Codex-facing wrapper for Harness's canonical `blueprint` skill.

Canonical skill:
- Installed root: `__HARNESS_PLUGIN_ROOT__/skills/blueprint/SKILL.md`
- Repo-local fallback: `skills/blueprint/SKILL.md` from the current Harness repo

When this skill is invoked:

1. Read the canonical skill file above before executing the workflow.
2. Follow the `Runtime Surface` -> `Codex` section in that file.
3. Mutate `plan.json` only through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan init|merge|validate`.
4. Prefer temporary JSON files over inline complex JSON.
5. Do not rely on hooks or MCP for Codex v1.
6. Use Harness native-agent adapter names when dispatching subagents:
   `harness-code-explorer`, `harness-worker`, `harness-verifier`, and
   `harness-code-reviewer`.

The output contract remains the canonical Harness contract:
`<spec_dir>/plan.json` and, when useful, `<spec_dir>/contracts.md`.
