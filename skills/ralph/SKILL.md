---
name: ralph
description: |
  Iterative "until it's done" loop with two judgment modes. Checklist mode
  (default): user-confirmed Definition of Done, Stop hook blocks exit until an
  independent verifier passes every item. Rubric mode (formerly /rulph): build
  a scoring rubric, evaluate with multiple models in parallel, improve one
  criterion at a time until the score threshold is met. Both use the Ralph
  Wiggum technique (prompt re-injection via Stop hook) with circuit breakers.
  NOT for plan-shaped build work — Phase 0 routes those to /specify.
  "/ralph", "ralph loop", "ralph 루프", "반복 작업", "DoD 루프",
  "완료 검증 루프", "task loop", "keep going until done", "될 때까지",
  "rubric evaluate", "rubric score", "score and improve", "grade this",
  "루브릭 평가", "채점 루프", "자율 개선", "개선 루프"
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Agent
  - AskUserQuestion
validate_prompt: |
  Must contain Phase 0 (Routing Guard + Mode Selection), Phase 1 (DoD Collection), Phase 2 (Work Execution).
  Checklist mode must use AskUserQuestion for DoD confirmation and write state
  via bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" session set with .ralph namespace,
  write DoD file to session files directory, and store the prompt for Stop hook re-injection.
  Rubric mode must follow references/rubric-mode.md (state namespace .rulph).
---

# ralph

Iterative "until it's done" loop. Two judgment modes share the same machinery
(Stop-hook loop + circuit breaker + independent evaluation); they differ in how
"done" is judged:

| Mode | "Done" means | Best for |
|------|--------------|----------|
| **Checklist** (default) | every DoD item passes independent verification (binary) | convergence work: make tests green, zero lint errors, migration passes |
| **Rubric** (formerly /rulph) | weighted score meets threshold + per-criterion floors | quality iteration: writing, design docs, refactoring quality — things that get *better*, not *done* |

**Checklist mode flow:**
1. You propose DoD criteria based on the user's request
2. User confirms/modifies via AskUserQuestion
3. You work on the task
4. When you try to stop, the Stop hook checks the DoD checklist:
   - If unchecked items remain → blocks exit, re-injects original prompt + remaining items
   - If all items checked → allows exit
5. Loop continues until all DoD items verified or a circuit breaker fires:
   - **Iteration breaker**: max 10 iterations (configurable)
   - **Stagnation recovery (self-correcting)**: the unchecked-item count
     failing to drop across a full fix+verify cycle (2 iterations) forces a
     strategy revision — spawn a fresh-context `ralph-strategist` agent that
     diagnoses the pattern (Spinning / Oscillation / Diminishing Returns),
     picks an untried lens (re-diagnose / contrarian / simplifier / hacker),
     and returns concrete steps + banned moves. The adopted strategy is
     appended to the session's `ralph-strategy.md` ledger; the Stop hook
     tracks the ledger's entry count, so grinding on without a new strategy
     is mechanically detected and re-blocked
   - **Stagnation breaker**: 4 iterations with zero progress despite strategy
     revision force-stops the loop early with a post-mortem summary built
     from the strategy ledger (which strategies were tried, with what outcome)

**Rubric mode flow**: Read and follow `references/rubric-mode.md` — rubric
building → parallel multi-model scoring → improve-one-criterion loop →
completion report. Its Stop-hook guard uses the `.rulph` state namespace.

## Runtime Surface

### Codex

- Read and apply `codex/PLUGIN_RUNTIME.md`.
- Dispatch `ralph-verifier` and `ralph-strategist` with their canonical
  `agents/<logical-role>.md` prompts.
- Do not depend on a Claude Stop hook. Run the work, independent verification,
  and strategy-revision cycle as an explicit bounded loop in the current turn.
- Preserve the same iteration and stagnation circuit breakers.

---

## Phase 0: Routing Guard + Mode Selection

### 0.1 Plan-shape check (route away if this isn't loop work)

ralph is for work whose "done" can only be written as a **condition**, not a
task list. Before anything else, ask yourself: *can this request be decomposed
into a concrete task sequence?*

- "add tagging to the memo app until it works" → decomposes (model → API → UI)
  → **plan-shaped**. Recommend the pipeline instead:

```
AskUserQuestion(
  question: "This looks like plan-shaped build work — /specify → /blueprint → /execute would give it structured tasks, per-task verification, and round commits. ralph's blind retry loop is weaker for this. Proceed how?",
  header: "Routing",
  options: [
    { label: "Use /specify pipeline (Recommended)", description: "Exit ralph; run /specify to plan and build this properly" },
    { label: "ralph anyway", description: "Skip planning; hammer at it with a DoD loop — okay for small, well-understood targets" }
  ]
)
```

- "make `npm test` exit 0", "keep going until the benchmark passes" → cannot be
  decomposed upfront → **loop-shaped**. Continue.

### 0.2 Judgment mode selection

Explicit flags win: `--dod` → checklist, `--rubric` → rubric. Otherwise infer:

- Target is a **binary condition** on code/system state (tests, lint, build,
  migration, uptime) → **checklist**. Don't ask; announce the mode.
- Target is an **artifact whose quality is graded**, with "improve / better /
  polish / 평가 / 개선" language (prose, docs, design, refactoring quality) →
  propose **rubric** via AskUserQuestion (checklist as the alternative).

On rubric mode: switch to `references/rubric-mode.md` now and follow it end to
end (it owns its own state init, loop, and completion). The phases below are
**checklist mode only**.

---

## Phase 1: DoD Collection

Build a Definition of Done through interactive confirmation before starting work.

### Step 1 — Analyze & Propose

Read the user's request carefully. Based on the task, propose 3–7 concrete, verifiable DoD criteria.

**Good criteria** (binary, independently verifiable):
- "All unit tests pass (`npm test` exits 0)"
- "New function `parseConfig()` exists in `src/config.ts`"
- "No TypeScript errors (`tsc --noEmit` exits 0)"

**Bad criteria** (vague, subjective):
- "Code is clean" → reword to "No lint warnings (`eslint .` exits 0)"
- "Works correctly" → reword to specific test or behavior check

Present as a numbered markdown checklist:

```
Based on your request, here's my proposed Definition of Done:

1. [concrete criterion 1]
2. [concrete criterion 2]
3. [concrete criterion 3]
...

Each item will be independently verified before the task is considered complete.
```

### Step 2 — User Confirmation

Use `AskUserQuestion` to confirm:

> "Here are the proposed DoD criteria. You can:
> - **Accept** as-is
> - **Add** criteria (tell me what to add)
> - **Remove** criteria (tell me which to remove)
> - **Modify** criteria (tell me what to change)
>
> Also, set **max iterations** (default: 10) if you want to limit the loop."

Loop until the user accepts. Parse their response for:
- Additions, removals, or modifications
- Custom max_iterations (default 10 if not specified)

### Step 3 — State Initialization

After user confirms, initialize the loop state and write the DoD file.

**Write DoD file** — create the checklist as a markdown file:

```
Bash: SESSION_ID="[session ID from hook]" && mkdir -p "$HOME/.harness/$SESSION_ID/files" && cat > "$HOME/.harness/$SESSION_ID/files/ralph-dod.md" << 'DODEOF'
# Definition of Done

- [ ] [criterion 1]
- [ ] [criterion 2]
- [ ] [criterion 3]
...
DODEOF
```

**Write state** — store the original prompt and configuration for the Stop hook:

```
Bash: SESSION_ID="[session ID from hook]" && PROMPT=$(cat << 'PROMPTEOF'
[The user's ORIGINAL request/prompt — exactly as they typed it, before any processing]
PROMPTEOF
) && bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" session set --sid "$SESSION_ID" --json "$(jq -n \
  --arg prompt "$PROMPT" \
  --arg dod_file "$HOME/.harness/$SESSION_ID/files/ralph-dod.md" \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{ralph: {prompt: $prompt, iteration: 0, max_iterations: 10, dod_file: $dod_file, created_at: $created_at}}')"
```

Replace `max_iterations: 10` with the user's chosen value if they specified one.

**Display confirmation:**

```
## Ralph Loop Initialized

**Task**: [summary of what you'll do]
**DoD**: [N] criteria
**Max iterations**: [max_iterations]

Starting work. The loop will verify each DoD item independently before allowing completion.
```

---

## Phase 2: Work Execution

Now do the actual work. Focus on completing the task to satisfy all DoD criteria.

**Rules during work:**
- Do NOT read or modify the DoD file (`ralph-dod.md`) — it's guarded by the system
- Do NOT try to check off DoD items yourself — the Stop hook handles verification
- Focus purely on the task described in the user's original request
- Work thoroughly — the loop will catch anything you miss

When you believe the work is complete, simply finish your response normally. The Stop hook will:
1. Check the DoD file for unchecked items
2. If items remain: block exit, re-inject the original prompt in `reason`, list remaining items in `systemMessage`
3. If all items checked: allow exit

**On re-entry (after Stop hook blocks):**
- You will receive the original prompt again as your task
- The `systemMessage` will instruct you to spawn a **ralph-verifier** agent

**Verification via separate agent (context isolation):**
1. Spawn `ralph-verifier` agent with `subagent_type="ralph-verifier"` in **FOREGROUND** (do NOT use `run_in_background=true`)
   - Background spawn causes the main agent to stop → Stop hook fires → loop breaks
   - Pass the DoD file path and original prompt
2. The verifier runs in a **fresh context** — no bias from the work phase
3. Parse the verifier's JSON results:
   - `PASS` items → change `- [ ]` to `- [x]` in the DoD file
   - `FAIL` items → fix the underlying issue in this iteration
4. If FAIL items were fixed, the next Stop hook will trigger another verification round

**Why a separate agent?**
The agent that wrote the code should NOT verify its own work. The verifier agent starts clean, reads actual files/tests, and judges objectively.

---

## Prompt Hardening

- Store the original prompt in state.json via heredoc to prevent shell injection
- The Stop hook re-injects the prompt via jq JSON construction (safe)
- DoD file is guarded during work phase — only editable during verification
- Circuit breaker at max_iterations prevents infinite loops
