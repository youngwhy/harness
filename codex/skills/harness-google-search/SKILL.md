---
name: harness-google-search
description: |
  Harness Google/chromux search workflow for Codex. Use when the user invokes
  "$harness-google-search" or needs real-browser Google search, site-specific
  search, time filters, or body/comment enrichment. This adapter loads the
  canonical google-search skill and follows its Codex runtime surface.
---

# harness-google-search

This is the Codex-facing wrapper for Harness's canonical `google-search` skill.

Canonical skill:
- Installed root: `__HARNESS_PLUGIN_ROOT__/skills/google-search/SKILL.md`
- Repo-local fallback: `skills/google-search/SKILL.md` from the current Harness repo

When this skill is invoked:

1. Read the canonical skill file above before executing the workflow.
2. Follow the `Runtime Surface` -> `Codex` section in that file.
3. Use `skills/google-search/vendor/web-search.mjs` through Bash.
4. If chromux is unavailable, use Codex web search fallback and state the
   enrichment limitations.

