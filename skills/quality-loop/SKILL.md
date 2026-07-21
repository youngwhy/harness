---
name: quality-loop
description: |
  This skill should be used when the user has spare token budget and wants to
  invest it in codebase quality. Sweeps the codebase N times with rotating
  lenses — subtle bugs, duplication, test health, feedback-loop speed — fixing
  what it finds, then makes linters and tests measurably faster. Records every
  discovered pattern to .harness/quality-loop/patterns.md so each run starts
  smarter than the last.
  Trigger phrases: "/quality-loop", "quality loop", "spare tokens", "burn tokens
  on quality", "make tests faster", "speed up the test suite", "clean up tests",
  "토큰 남았어", "토큰 남을 때", "품질 루프", "코드 품질 개선", "테스트 빠르게",
  "테스트 정리", "중복 코드 정리", "린트 느려".
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
  Must contain Phase 0 (Baseline + Pattern Memory), Phase 1 (Sweep Loop with
  rotating lenses and dry-pass exit), Phase 2 (Feedback-Loop Speed via
  references/speed-checklist.md), Phase 3 (Compound — append new patterns to
  .harness/quality-loop/patterns.md and report before/after metrics).
  Every test deletion must cite one of the three proofs. Every speed change
  must be kept only with a measured improvement.
---

# quality-loop

Invest spare token budget into the two properties that let agents run long and
autonomously: **test coverage** (how bold each attempt can be) and **feedback
speed** (how fast the loop turns). Coverage without speed stalls the loop;
speed without coverage makes it reckless. This skill raises both, then records
what it learned so the next run starts where this one ended.

Usage: `/quality-loop [N] [path]` — N sweep passes (default 3), optional scope
(default: whole repo). Runs autonomously; no mid-run questions.

---

## Phase 0: Baseline + Pattern Memory

### 0.1 Load pattern memory

Read `.harness/quality-loop/patterns.md` if it exists. Each entry is a pattern
found in a previous run with a `detect:` command. **Run every detect command
first** — recurrences of known patterns are the cheapest wins and take priority
over fresh exploration. If the file doesn't exist, create the directory
(`mkdir -p .harness/quality-loop`) and start with an empty memory.

### 0.2 Measure the baseline

Record numbers you will compare against in Phase 3 (skip any that don't apply):

```bash
time <full test command>        # wall time + test count
time <lint command>             # lint wall time
time <pre-commit hook>          # what a commit actually costs (if hooks exist)
```

Save results to `.harness/quality-loop/baseline.md` with the date. If a
baseline from a previous run exists, keep it — the history shows drift.

### 0.3 Scope

Parse `N` and `path` from the arguments. Detect the project's test runner,
linter, and hook setup (pytest/jest/cargo/go test; ruff/eslint/clippy;
pre-commit/husky) before sweeping — the lenses need them.

---

## Phase 1: Sweep Loop (N passes)

Each pass sweeps the scope with **one lens**, rotating in this order. A pass
that produces zero verified findings counts as a *dry pass*; **two consecutive
dry passes end Phase 1 early** — don't burn tokens circling a clean codebase.

| Pass | Lens | Looking for |
|------|------|-------------|
| 1 | **Subtle bugs** | off-by-one, unhandled error paths, None/null flows, boundary conditions, race conditions, swallowed exceptions, wrong operator (`<` vs `<=`, `and` vs `or`) |
| 2 | **Duplication** | copy-paste blocks, near-duplicate functions, parallel implementations of the same concept, config values repeated instead of shared |
| 3 | **Test health** | stale tests (asserting behavior that no longer exists), redundant tests (two tests covering the same path — keep the fastest), tests that can never fail, duplicated bootstrapping across test files |
| 4+ | rotate back to the lens that yielded the most last time | |

### Per-pass procedure

1. **Fan out**: split the scope into modules/directories and dispatch parallel
   `Explore`-style subagents, one per chunk, each carrying the current lens
   prompt plus the relevant entries from pattern memory. Subagents report
   findings as `file:line — claim — why it matters`; they do not edit.
2. **Verify adversarially**: for each finding, actively try to refute it before
   touching code (read the surrounding context, check callers, run the code
   path if cheap). Discard anything plausible-but-unproven. False-positive
   fixes are worse than no fixes.
3. **Fix in small batches**: behavior-preserving unless it's a confirmed bug —
   and a confirmed bug gets a **regression test in the same commit**. Run the
   affected tests after each batch. Commit atomically per concern using the
   `git-master` agent conventions.
4. **Log**: append each verified finding to the pass log (in memory) — Phase 3
   turns these into pattern entries.

### Test-deletion rule

A test may only be deleted with one of these three proofs, cited in the commit
message:

1. **Feature gone** — the behavior it asserts no longer exists in the code.
2. **Covered elsewhere** — name the surviving test that covers the same path.
3. **Cannot fail** — demonstrated (e.g., assertion is tautological, or a quick
   mutation of the code under test doesn't break it).

Never delete a test to make the suite faster. Speed comes from Phase 2.

---

## Phase 2: Feedback-Loop Speed

After the sweeps, run the diagnostics in
`${baseDir}/references/speed-checklist.md` — seven failure modes that
accumulate silently in agent-built codebases (stale selection logic, redundant
coverage, over-parallelism, CI-grade hooks, repeated bootstrapping, cold
caches, missing test tiers).

Rules for every speed change:

- **Measure before and after.** A change without a measured improvement is
  reverted, even if it "should" be faster (over-parallelism looks like an
  optimization and measures like a regression).
- **Correctness is not a currency.** Coverage may never decrease to buy speed.
  Restructure (tier, cache, scope, share setup) — don't skip.
- One optimization per commit, with the numbers in the commit message
  (`test suite: 94s → 41s — session-scope DB fixture`).

---

## Phase 3: Compound

### 3.1 Record patterns

Append every *new* verified pattern to `.harness/quality-loop/patterns.md`
(update `hits` and `last-seen` for recurrences instead of duplicating):

```markdown
## <short-pattern-name>
- category: bug | duplication | test-health | speed
- detect: `<grep/command that finds this pattern mechanically>`
- fix: <one-line fix recipe>
- first-seen: <date> · last-seen: <date> · hits: <n>
- example: <file:line from this run>
```

The `detect:` line is the whole point — next run's Phase 0.1 executes it for
free. A pattern without a mechanical detect command should be rewritten until
it has one, or noted as `detect: manual — <what to look at>`.

If a pattern is universal (not project-specific), also suggest it to the user
as a lint rule or pre-commit check — a deterministic guard beats a recorded
pattern.

### 3.2 Report

Update `.harness/quality-loop/baseline.md` with the new measurements and close
with a before/after table:

| Metric | Before | After |
|--------|--------|-------|
| Full test suite | | |
| Lint | | |
| Pre-commit hook | | |
| Test count | | |
| Bugs fixed / dups removed / tests pruned | — | |

Plus: passes run (and whether the dry-pass exit fired), patterns added to
memory, and any suggestions that need a human decision (e.g., "pre-push runs
the full E2E suite — move to CI?").

---

## References

- [Software Engineering at Google, ch. 11–12](https://abseil.io/resources/swe-book/html/ch11.html) — test sizes (small/medium/large) and the 80/15/5 unit/integration/E2E mix; the basis for hook tiering
- [Google Testing Blog: Test Sizes](https://testing.googleblog.com/2010/12/test-sizes.html)
- [Martin Fowler: Eradicating Non-Determinism in Tests](https://martinfowler.com/articles/nonDeterminism.html) — isolation, shared-resource contention, why flaky ≈ useless
- [The Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html) — where redundant coverage comes from
- Mutation testing ([Stryker](https://stryker-mutator.io/), [mutmut](https://mutmut.readthedocs.io/)) — mechanical detection of tests that cannot fail
- Test Impact Analysis ([pytest-testmon](https://testmon.org/), `nx affected`, Bazel) — change-scoped test selection done right
