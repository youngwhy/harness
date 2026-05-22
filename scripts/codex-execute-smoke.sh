#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ROOT/fixtures/codex-migration/todo-toggle"
CLI="$ROOT/scripts/cli.sh"

[[ -f "$CLI" ]] || { echo "harness-cli not found at $CLI" >&2; exit 1; }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-codex-execute.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

SPEC_DIR="$WORKDIR/todo-toggle"
EVIDENCE_DIR="$SPEC_DIR/context/codex-execute-smoke"
mkdir -p "$SPEC_DIR" "$EVIDENCE_DIR"
cp "$FIXTURE/requirements.md" "$SPEC_DIR/requirements.md"

bash "$CLI" plan init "$SPEC_DIR" --type feature >/dev/null
bash "$CLI" plan merge "$SPEC_DIR" --patch --json "$(cat "$FIXTURE/plan.patch.json")" >/dev/null
bash "$CLI" plan validate "$SPEC_DIR"

# Codex v1 single-worker execution smoke:
# - claim one task
# - write worker evidence outside plan.json
# - complete the task through bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" only
# - validate the plan after completion
bash "$CLI" plan task "$SPEC_DIR" --status T1=running --summary "codex single-worker smoke claimed T1" >/dev/null

cat > "$EVIDENCE_DIR/T1.md" <<'EOF'
# T1 Worker Evidence

Task: Add a todo completion toggle and wire visible completed state.

Smoke evidence:
- The Codex v1 runtime used Bash-first `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" plan task` state changes.
- `plan.json` was not edited directly.
- This file stands in for worker-produced evidence in the single-worker smoke.

Result: PASS
EOF

test -s "$EVIDENCE_DIR/T1.md"
bash "$CLI" plan task "$SPEC_DIR" --status T1=done --summary "codex single-worker smoke evidence recorded" >/dev/null
bash "$CLI" plan validate "$SPEC_DIR"
bash "$CLI" plan get "$SPEC_DIR" --path tasks[0].status | grep -qx 'done'

echo "codex execute smoke passed: $SPEC_DIR"
