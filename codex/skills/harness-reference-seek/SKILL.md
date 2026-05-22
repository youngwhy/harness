---
name: harness-reference-seek
description: |
  Harness implementation reference discovery workflow for Codex. Use when the
  user invokes "$harness-reference-seek" or asks for internal patterns,
  open-source references, GitHub examples, official docs, or comparable
  implementations. This adapter loads the canonical reference-seek skill and
  follows its Codex runtime surface.
---

# harness-reference-seek

This is the Codex-facing wrapper for Harness's canonical `reference-seek` skill.

Canonical skill:
- Installed root: `__HARNESS_PLUGIN_ROOT__/skills/reference-seek/SKILL.md`
- Repo-local fallback: `skills/reference-seek/SKILL.md` from the current Harness repo

When this skill is invoked:

1. Read the canonical skill file above before executing the workflow.
2. Follow the `Runtime Surface` -> `Codex` section in that file.
3. Use `harness-code-explorer` for internal pattern search when loaded.
4. Use Bash-first `gh api` and `curl` for GitHub references.
5. Treat context/documentation MCP as optional; use official web docs fallback
   when MCP tools are unavailable.

