# Feedback-Loop Speed Checklist

Seven failure modes that accumulate silently as a codebase grows under agent
autonomy. For each: how to detect it, how to fix it. Work top-down — the early
items are usually the biggest wins. Every fix must show a measured before/after
improvement or be reverted (SKILL.md Phase 2 rules).

---

## 1. Stale tests — valid once, not anymore

**Symptom**: tests assert behavior that was removed or changed; they pass only
because they test a shim, a mock of a dead interface, or nothing at all.

**Detect**:
- Cross-reference test names against the current public API — tests referencing
  deleted modules/functions via mocks won't error, they just test the mock.
- Spot-check with mutation: break the code a test claims to cover; if the test
  still passes, it covers nothing. (Tools: Stryker, mutmut — or a manual
  5-minute mutation of the hottest module.)
- `git log --diff-filter=D --name-only -- src/` vs surviving tests that mention
  those names.

**Fix**: delete, citing one of the three proofs in SKILL.md's test-deletion rule.

## 2. Redundant coverage — two tests, one path

**Symptom**: an E2E test re-walks a path a unit test already covers; several
tests differ only in setup noise.

**Detect**: run coverage per test file on the slowest tests
(`pytest --cov ... <one file>`) and diff the covered lines against faster
tests. Slow test whose coverage is a subset of faster ones → redundant.

**Fix**: keep the fastest test that covers the path (test pyramid: push
coverage down a tier). Cite "covered elsewhere" proof when deleting.

## 3. Broken change-scoping — small edit, full suite

**Symptom**: the affected-test selection logic (testmon, `nx affected`, Bazel
deps, a homegrown script) over-selects, so a one-line change runs everything.

**Detect**: make a trivial change in a leaf module, run the selection command,
count selected tests. If it selects far beyond the dependency cone, the
scoping is buggy — common causes: a catch-all glob, a config file listed as a
dependency of everything, stale dependency graph.

**Fix**: fix the selection logic itself; verify with the same trivial-change
probe. Also verify the inverse — a change in a *core* module must still select
its dependents (under-selection silently drops coverage).

## 4. Over-parallelism — contention masquerading as speed

**Symptom**: `-n auto` / high worker counts made the suite *slower* — workers
fight over DB, ports, temp dirs, or CPU; startup cost per worker exceeds the
win on small suites.

**Detect**: time the suite at 1, 2, 4, 8 workers. If the curve flattens or
reverses early, there's contention. Watch for shared-state flakiness appearing
only at high worker counts (Fowler: lack of isolation).

**Fix**: pick the measured-best worker count; isolate shared resources
(per-worker DB schema / unique temp dirs / dynamic ports) before raising
parallelism further.

## 5. CI-grade hooks — pre-commit running the world

**Symptom**: pre-commit or pre-push runs the full test suite or E2E tests, so
every commit costs minutes and agents (or humans) start skipping hooks.

**Detect**: read `.pre-commit-config.yaml` / `.husky/` / git hooks; time an
empty commit.

**Fix**: tier by test size (Software Engineering at Google, ch. 11):
- **pre-commit** (seconds): format + lint on *changed files only*
- **pre-push** (tens of seconds): affected unit tests
- **CI** (minutes): full suite, integration, E2E

## 6. Repeated bootstrapping — every test builds the world

**Symptom**: many test files independently spin up the same app/DB/fixture;
setup dominates wall time.

**Detect**: profile setup vs test-body time (`pytest --durations=20` includes
setup; look for the same expensive setup name repeating).

**Fix**: hoist to session/module-scoped fixtures or a shared bootstrap —
**but keep mutable state function-scoped** (share the expensive-to-build,
isolate the mutable; otherwise you trade speed for flakiness, the worse deal).

## 7. Cold starts — cache exists, nobody uses it

**Symptom**: every run recompiles, re-lints unchanged files, re-downloads, or
re-seeds from scratch.

**Detect**: run the same command twice back-to-back; if the second run isn't
dramatically faster, caching is off or broken.

**Fix**: enable the tool's native cache (ruff/eslint `--cache`, pytest
`--lf/--ff` + testmon, incremental compilation, Turborepo/nx remote cache,
docker layer ordering for test images) and make sure CI persists it.
