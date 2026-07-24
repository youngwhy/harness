# Project Guidelines

## Experimentation

Use `.playground/` directory for experiments and testing. This directory is git-ignored.

## Agent/Skill Development

### validate_prompt

To automatically validate agent/skill output, add a `validate_prompt` field to the frontmatter.

**Agent example** (`.claude/agents/my-agent.md`):
```yaml
---
name: my-agent
description: My custom agent
validate_prompt: |
  Must contain X, Y, Z sections.
  Output should be in JSON format.
---
```

**Skill example** (`.claude/skills/my-skill/SKILL.md`):
```yaml
---
name: my-skill
description: My custom skill
validate_prompt: |
  Must produce valid output.
---
```

**How it works:**
1. `PostToolUse` hook detects Task/Skill completion
2. Extracts `subagent_type` or `skill` name from tool input
3. Finds agent/skill file and parses `validate_prompt` from frontmatter
4. Outputs validation reminder to Claude

### Implementation Files

- `.claude/scripts/validate-output.sh` - PostToolUse validation hook
- `.claude/settings.json` - registers PostToolUse hook for Task|Skill

## Hook System

Hooks are registered in `.claude/settings.json` and automate pipeline transitions and quality enforcement.

### Hook Types

| Type | When it fires | Use case |
|------|--------------|----------|
| `SessionStart` | Session begins | Initialize session-level state |
| `UserPromptSubmit` | User submits a prompt | Initialize state, intercept slash commands |
| `PreToolUse` | Before a tool executes | Block or modify tool calls |
| `PostToolUse` | After a tool completes | Validate output, trigger follow-up |
| `PostToolUseFailure` | After a tool fails | Error recovery, failure tracking |
| `Stop` | Session ends | Transition to next pipeline stage |

### Active Hooks

| Script | Type | Purpose |
|--------|------|---------|
| `session-compact-hook.sh` | SessionStart | Unified compact recovery — outputs skill name + state.json path |
| `ultrawork-init-hook.sh` | UserPromptSubmit | Initialize ultrawork pipeline state when `/ultrawork` is typed |
| `skill-session-init.sh` | UserPromptSubmit + PreToolUse[Skill] | Initialize session state for specify/execute/blueprint skills |
| `rv-detector.sh` | UserPromptSubmit | Detect `!rv` keyword to trigger re-validation loop |
| `skill-session-guard.sh` | PreToolUse[Edit\|Write] | Plan guard (specify) / orchestrator guard (execute) |
| `ralph-dod-guard.sh` | PreToolUse[Edit\|Write] | Enforce DoD before allowing writes in /ralph loop |
| `validate-output.sh` | PostToolUse[Task\|Skill] | Validate agent/skill output against `validate_prompt` frontmatter |
| `tool-output-truncator.sh` | PostToolUse[Grep\|Glob\|WebFetch\|Bash] | Truncate oversized tool output (50K/10K limits, stderr preserved) |
| `edit-error-recovery.sh` | PostToolUseFailure[Edit\|Write] | Detect Edit failures and inject recovery guidance (5 error patterns) |
| `large-file-recovery.sh` | PostToolUseFailure[Read] | Detect large/binary file Read failures, suggest chunked read, agent delegation, or Grep |
| `tool-failure-tracker.sh` | PostToolUseFailure[*] | Track repeated failures per tool, escalate at 3/5 failures in 60s window |
| `ultrawork-stop-hook.sh` | Stop | Advance ultrawork pipeline on session stop |
| `skill-session-stop.sh` | Stop | Block exit if execute has incomplete tasks (circuit breaker: 30 iter) |
| `rv-validator.sh` | Stop | Run re-validation pass on stop |
| `rulph-stop.sh` | Stop | Rubric-mode loop guard for /ralph (`.rulph` state namespace) |
| `ralph-stop.sh` | Stop | Ralph loop DoD verification + prompt re-injection |
| `skill-session-cleanup.sh` | SessionEnd | Clean up session dir (`rm -rf ~/.harness/{session_id}/`) |

### Hook Development Notes

- Hook scripts live in `.claude/scripts/` (symlink to `scripts/`) and must be executable (`chmod +x`)
- **When adding a new hook script, you MUST update all three:**
  1. `hooks/hooks.json` — plugin-level registration (uses `${CLAUDE_PLUGIN_ROOT}/scripts/...`)
  2. `.claude/settings.json` — project-level registration (uses `.claude/scripts/...`)
  3. `CLAUDE.md` — add entry to the Active Hooks table above
- A hook script that is not registered in settings will **not fire** — creating the file alone is not enough
- Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" session get --sid <id>` to verify session state after changes
- Hook behavior gotchas are documented in commit history and session learnings

## Git Branching & Release

- **`main`** — release only. Do not commit directly.
- **`develop`** — integration branch. Feature branches merge here.
- **Feature branches** — `feat/xxx` from `develop`, merge back to `develop` via `--no-ff`.

### Pre-Release Checklist

- [ ] All content must be written in English (SKILL.md, agent .md, CLAUDE.md, README.md, commit messages, comments)
- [ ] When `README.md` is updated, sync the Korean translation: `README.ko.md` (zh/ja translations were dropped in v1.12.0)

### Release Flow

```
1. All features merged to develop
2. Version bump commit on develop (Claude manifest + marketplace + Codex manifest)
3. Update CLAUDE.md (Recent Changes) and README.md (if new skills/agents added)
4. git checkout main && git merge develop --no-ff -m "Release X.Y.Z"
5. git tag vX.Y.Z && git push origin main --tags && git push origin develop
6. gh release create vX.Y.Z --title "vX.Y.Z" --notes "## What's New in X.Y.Z ..."
```

## Versioning

- Plugin version is in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json`
- **Bump all three files** in a single commit on `develop` before merging to `main`
- The CLI (`harness-cli` = `scripts/cli.sh`) ships inside the plugin — no separate package version to sync

## Fork Notes

This repo is `youngwhy/harness`, synced to its upstream (`git remote get-url upstream`) at v1.7.1.

- **CLI in pure bash** — the upstream npm CLI is replaced by **harness-cli** = `scripts/cli.sh` (pure bash + jq). All skills/agents/hooks/codex adapters invoke it by path via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" <group> <sub>`. No npm install, no `cli/` package, no `cli-version-sync.sh` hook.
- **Rebranded** — the upstream brand and org names are replaced by `harness` / `youngwhy`. Install via `/plugin install harness@youngwhy`.
- **Upstream sync** — to pull newer upstream code: add the upstream remote, overlay `upstream/main`, preserve `scripts/cli.sh`, drop npm artifacts (`cli/`, `cli-version-sync.sh`, `pre-commit-cli-build.sh`, npm CI workflows), then re-run the brand scrub (upstream name → `harness`) and the npm-CLI → bash-cli rewrite.

## Recent Changes (v1.14.1)

- Completed Codex native-agent coverage for every spawnable canonical agent.
- Removed Codex model and reasoning-effort pins so adapters inherit session defaults.
- Resolved canonical agent prompt paths during Codex adapter installation.
- Added Codex installation guidance and synchronized plugin manifest versions.

## Recent Changes (v1.12.0)

### New `quality-loop` skill — spare-token quality sweep

Invests leftover weekly token budget into the two properties that let agents
run long and autonomously: test coverage (how bold each attempt can be) and
feedback speed (how fast the loop turns).

- **Phase 0** loads `.harness/quality-loop/patterns.md` (per-project pattern
  memory) and runs every recorded `detect:` command first, then measures a
  test/lint/hook-time baseline.
- **Phase 1** sweeps the codebase N times (default 3) with rotating lenses —
  subtle bugs, duplication, test health — via parallel explore subagents;
  findings are adversarially verified before fixing; two consecutive dry
  passes exit early. Test deletion requires one of three cited proofs
  (feature gone / covered elsewhere / cannot fail).
- **Phase 2** runs `references/speed-checklist.md`: 7 feedback-loop failure
  modes (stale tests, redundant coverage, broken change-scoping,
  over-parallelism, CI-grade hooks, repeated bootstrapping, cold caches).
  Every speed change must show a measured before/after improvement or be
  reverted; coverage is never traded for speed.
- **Phase 3** appends new patterns (with mechanical detect commands) to the
  pattern memory so each run starts where the last ended, and reports a
  before/after metrics table.

Grounded in SWE-at-Google test sizes (hook tiering), Fowler's
non-determinism article (parallel contention), mutation testing
(cannot-fail detection), and test impact analysis (change scoping).

### Docs: drop zh/ja READMEs, sync Korean

`README.zh.md` and `README.ja.md` removed — only `README.ko.md` is
maintained alongside `README.md`. Korean README synced to the current
skill set (Test category row, /qa and /quality-loop entries, ralph
two-mode description). Skill/agent counts in both READMEs corrected to
the measured 24 skills · 26 agents · 18 hooks.

## Recent Changes (v1.11.0)

### ralph absorbs rulph — one "until done" loop, two judgment modes

ralph and rulph shared the same machinery (Stop-hook loop + circuit breaker +
independent evaluation) and differed only in how "done" is judged. Merged:

- **`/ralph` Phase 0 added** — (0.1) plan-shape routing guard: requests that
  decompose into a task list get pointed at /specify → /blueprint → /execute
  instead of a blind retry loop; (0.2) judgment mode selection: binary
  system-state targets → checklist (DoD, default), graded-quality artifacts →
  rubric (proposed via AskUserQuestion; `--dod` / `--rubric` flags skip).
- **Rubric mode** = former rulph, ported verbatim to
  `skills/ralph/references/rubric-mode.md`. It keeps the `.rulph` state
  namespace so `rulph-stop.sh` (now documented as ralph's rubric-mode stop
  guard) continues to enforce the loop unchanged.
- **Removed**: `rulph` skill and `rulph-init.sh` (redundant — the skill flow
  writes the full `.rulph` state itself, including the safety counters the
  init hook seeded). Hook registrations updated in hooks.json and
  .claude/settings.json; skill-rules keywords merged into ralph.

## Recent Changes (v1.10.0)

### Council becomes the single decision/review entry point

The review/decision cluster (council, tribunal, tech-decision, dev-scan,
stepback) consolidates to two user-facing skills:

- **`/council`** routes by target type detected in Phase 1:
  - **REVIEW** (plan/PR/diff/proposal) → adversarial-leaning panel; Phase 3
    gains the tribunal verdict matrix (Risk × Value × Feasibility →
    APPROVE/REVISE/REJECT). Quick mode + REVIEW target = the former /tribunal.
  - **COMPARISON** ("A vs B") → new 1.6 research stage (weighted criteria via
    `references/evaluation-criteria.md` + parallel code-explorer /
    docs-researcher / dev-scan evidence gathering) feeding an advocate-per-option
    panel; conclusion-first report per `references/comparison-report.md`.
    This absorbs the former /tech-decision (which had rotted — it referenced
    the nonexistent agent-council skill and decision-synthesizer agent).
- **`/stepback`** unchanged — mid-work self-check, distinct category.
- **Removed**: `tribunal` and `tech-decision` skills; tribunal's three dedicated
  agents (`codex-risk-analyst`, `value-assessor`, `feasibility-checker`) —
  council designs topic-fit panels dynamically, so fixed panel agents are dead
  weight in every session's context.
- **`dev-scan` demoted** to a data source: description and skill-rules triggers
  now point decision-seeking requests to /council, which calls it internally
  (Full mode). Direct invocation still works for raw community-opinion asks.

## Recent Changes (v1.9.0)

### Clarify Escalation Gate in /specify

Users no longer need to judge when to use /clarify — /specify detects it.
The Phase 1 "I Don't Know" handler now classifies every don't-know answer:

- **Delegation** ("up to you") → tentative default + assumption, continue (as before)
- **Leaf deferral** (isolated unknown, downstream questions unaffected) →
  recommend + Open Decision, continue; 2 leaf deferrals in one axis triggers
  the gate as a backstop
- **Structural deferral** (the answer shapes the requirement tree, or the user
  signals decision anxiety) → escalation gate fires on the FIRST occurrence

The gate offers (never forces) a scoped /clarify run on just the blocked
decision; on SUFFICIENT the summary is imported into qa-log.md as resolved and
the interview resumes at the triggering question. `clarify` gains a "Scoped
Invocation" contract (narrow SUFFICIENT bar, 2-6 questions, no follow-up
command suggestion). `discuss` drops requirements-clarification trigger
phrases — requirements ambiguity now routes specify → clarify automatically.

Recommended entry points are now just two: `/discuss` (is this a good idea?)
and `/specify` (everything else — it escalates to clarify by itself).

## Recent Changes (v1.8.1)

### Remove `mirror` skill

The standalone `/mirror` skill is fully subsumed by `/specify` Phase 0.1
(Mirror — prove understanding before asking) and the mirroring step in
`/clarify`'s core loop. Removed `skills/mirror/`, its skill-rules entry, and
doc/README references; `/stepback`'s comparison table now points to
`/specify` Phase 0 Mirror.

## Recent Changes (v1.8.0)

### Hierarchical model economics (planner-worker tiering)

Inspired by Cursor's agent-swarm model-economics findings (frontier planner +
low-cost workers beat a single frontier swarm on both cost and pass rate):

- **Planning tier → session model (frontier)**: `taskgraph-planner`, `verify-planner`,
  `contract-deriver` drop their `model:` frontmatter and inherit the session model —
  whatever frontier model runs the orchestrator also makes the design decisions.
- **Mechanical verification tier → down**: `verifier`, `qa-verifier` opus → sonnet
  (verifier is judgment-free by contract); `ralph-verifier` gains an explicit
  `model: sonnet` (previously leaked the session model).
- **Judgment gate → up**: `code-reviewer` sonnet → opus (SHIP/NEEDS_FIXES verdict is
  the rework-loop gate — worth the intelligence).
- **Mechanical helpers → haiku**: `git-master`, `business-extractor`, `tech-extractor`,
  `interaction-extractor` sonnet → haiku.
- **Complexity-based worker routing**: `taskgraph-planner` now emits
  `complexity: trivial | standard | complex` per task (validated by
  `cli.sh plan validate`); /execute agent mode routes each worker group's `model`
  param by its hardest task (trivial → haiku, standard → worker default sonnet,
  complex → opus) with tier escalation on retry. Legacy plans without `complexity`
  and team/direct modes keep frontmatter defaults.

## Recent Changes (v1.7.1)

### chromux skill/agent sync
- Drop duplicated chromux command tables across 5 consumer files; delegate to the canonical chromux skill loaded via global agent context
- `agents/browser-explorer.md`: replace 18-line command catalog with category summary; switch debug rule and anti-patterns from legacy `eval`/`console`/`network` to `run`/`watch`
- `skills/browser-work/references/chromux-guide.md`: rewrite as a thin browser-work-specific overlay; document `--headless`/`--hidden` semantics + auto-launch default; add `snippets/_builtin/scroll-until.js` pattern
- `skills/qa/references/browser-mode.md`: keep `qa-XXXX` / `.qa-reports` conventions only; convert `eval`/`console`/`network` examples to `run` + `watch`
- `skills/qa/references/browser-verify.md`: 4 `eval` blocks → `run` + `js()`; `console` → `watch console`
- `skills/qa/references/spec-drift-check.md`: same conversion
- `skills/deep-research/SKILL.md`: `chromux wait` → `sleep`
- Codex adapters inherit the fix automatically (already point to canonical files)
- Legacy chromux aliases remain supported per upstream policy; we just stop teaching them as the primary surface

## Recent Changes (v1.7.0)

### Codex CLI Parity
- New `.codex-plugin/plugin.json` — Codex runtime adapter package alongside the Claude Code plugin
- `codex/agents/*.toml` adapters (9): `harness-{browser-explorer, clarity-auditor, code-explorer, code-reviewer, docs-researcher, external-researcher, gap-auditor, verifier, worker}` — dispatch Harness logical subagents via Codex
- `codex/skills/harness-*/SKILL.md` bridges (10): blueprint, browser-work, clarify, deep-research, dev-scan, discuss, execute, google-search, reference-seek, specify
- `skills/{blueprint, browser-work, deep-research, dev-scan, execute, google-search, reference-seek, specify}/SKILL.md` — added **Runtime Surface** sections documenting Claude Code vs Codex dispatch semantics (Bash-first state, JSON-payload files, no MCP/hooks in v1)
- Installers: `scripts/install-codex-{agent,skill}-adapters.sh`
- Smoke tests: `scripts/codex-{blueprint, execute, research}-smoke.sh`
- Migration reference: `docs/codex-migration.md` + `fixtures/codex-migration/todo-toggle/`

### New `clarify` Skill
- Relentless ambiguity-resolution interview that records Q&A under `.harness/clarify/<topic>/`
- Templates: `qa-log.md`, `clarity-summary.md`
- New `clarity-auditor` agent (Claude + Codex adapter)
- Hands off to specify/blueprint/docs when clear

## Recent Changes (v1.6.0)

### Pipeline v2 Migration
- **BREAKING**: Removed old specify (v1), execute (v1), quick-plan skills and bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" (v1)
- **Renamed**: specify2 → specify, execute2 → execute (clean names)
- New pipeline: `/specify` (requirements.md) → `/blueprint` (plan.json + contracts.md) → `/execute` (dispatch workers)
- New CLI: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh"` with groups: req, plan, learning, issue, session
- Rewired `/bugfix` from spec.json → requirements.md pipeline
- Updated all hooks, agents, and downstream skills for v2
- Codebase reconnaissance added to `/blueprint` (Phase 0.5, non-greenfield)
- Preview gates added to `/specify` (requirements preview) and `/blueprint` (task graph + verify plan)
- Inline planning fallback in `/execute` when no blueprint exists

### Execute (plan-driven orchestrator)
- 3-axis config: dispatch (direct/agent/team) × work (worktree/branch/no-commit) × verify (light/standard/thorough)
- 6 dispatch/verify reference recipes: direct.md, agent.md, team.md, worker-charter.md, verify.md, contracts-patch.md
- Pre-work gate, inline planning fallback, resume behavior with idempotent done-skip

### CLI (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh"`)
- `req init` — requirements.md scaffolding
- `plan init/merge/get/list/task/validate` — plan.json operations
- `learning` — structured learnings to context/learnings.json
- `issue` — structured issues to context/issues.json
- `session set/get` — session state management

## CLI Reference (bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh")

| Group | Command | Description |
|-------|---------|-------------|
| `req` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" req init <spec_dir> --type <type> [--goal "..."]` | Create spec_dir + requirements.md template |
| `plan` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan init <spec_dir> --type <type>` | Create empty plan.json stub |
| `plan` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan merge <spec_dir> --json '<payload>' [--patch\|--append]` | Merge payload into plan.json |
| `plan` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan get <spec_dir> --path <dotted.path>` | Read field by dot notation |
| `plan` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan list <spec_dir> [--status <state>] [--json]` | List tasks with optional filter |
| `plan` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan task <spec_dir> --status <id>=<state>` | Update task status (monotonic done-lock) |
| `plan` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan validate <spec_dir>` | Schema + cross-ref integrity check |
| `learning` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" learning --task <id> --json '{...}' <spec_dir>` | Add learning to context/learnings.json |
| `issue` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" issue --task <id> --json '{...}' <spec_dir>` | Add issue to context/issues.json |
| `session` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" session set --sid <id> [--key k --value v] [--json '{...}']` | Update session state |
| `session` | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" session get --sid <id>` | Read session state |

**Key conventions:**
- **File-based JSON passing** — write JSON to `/tmp/spec-merge.json` via heredoc (`<< 'EOF'`), pass via `--json "$(cat /tmp/spec-merge.json)"`. Never pass JSON directly as CLI argument (zsh glob expansion corrupts `[`, `{`, `$`)
- **One merge per section** — call `plan merge` once per top-level key
- **`--append` for arrays** — use when adding to existing arrays
- **`--patch` for nested updates** — use when updating specific items within arrays
- **`--stdin` for subagents** — learning and issue commands support `--stdin` to read JSON from stdin

**Learning & Issue examples:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" learning --task T1 --stdin <spec_dir> << 'EOF'
{"problem": "...", "cause": "...", "rule": "...", "tags": [...]}
EOF

bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" issue --task T1 --stdin <spec_dir> << 'EOF'
{"type": "failed_approach|out_of_scope|blocker", "description": "..."}
EOF
```

## Testing Strategy

See [VERIFICATION.md](VERIFICATION.md) for the 4-Tier Testing Model (Unit → Integration → E2E → Agent Sandbox). Verification agents use this as their framework.

## Lessons Learned

Hook/tool behavior gotchas are documented in commit history and session learnings.
