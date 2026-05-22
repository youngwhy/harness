---
name: harness-clarify
description: |
  Harness ambiguity-resolution interview for Codex. Use when the user invokes
  "$harness-clarify", "/clarify", asks to keep asking until clear, remove
  ambiguity, clarify requirements/design/domain/plan, or says Korean phrases
  like "모호한 게 없게", "명확해질 때까지", "질문 계속해", or "Q&A로 정리".
---

# harness-clarify

This is the Codex-facing wrapper for Harness's canonical `clarify` skill.

Canonical skill:
- Installed root: `__HARNESS_PLUGIN_ROOT__/skills/clarify/SKILL.md`
- Repo-local fallback: `skills/clarify/SKILL.md` from the current Harness repo

When this skill is invoked:

1. Read the canonical skill file above before executing the workflow.
2. Follow the one-question-at-a-time ambiguity-resolution loop.
3. Write Q&A state under `.harness/clarify/<topic-slug>/`.
4. Use `harness-clarity-auditor` at audit boundaries when native adapters are
   loaded. If unavailable, do a compact direct audit and record the fallback.
5. Use `harness-code-explorer` when code/docs can answer a question better than
   the user can.
6. Do not implement, write final `requirements.md`, mutate `plan.json`, or
   create ADRs unless the user explicitly asks for that handoff.

The output contract remains the canonical Harness contract:
`.harness/clarify/<topic-slug>/qa-log.md` and, when sufficient,
`.harness/clarify/<topic-slug>/clarity-summary.md`.
