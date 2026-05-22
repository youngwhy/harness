#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ROOT/fixtures/codex-migration/todo-toggle"
CLI="$ROOT/scripts/cli.sh"

[[ -f "$CLI" ]] || { echo "harness-cli not found at $CLI" >&2; exit 1; }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-codex-smoke.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

SPEC_DIR="$WORKDIR/todo-toggle"
mkdir -p "$SPEC_DIR"
cp "$FIXTURE/requirements.md" "$SPEC_DIR/requirements.md"

bash "$CLI" plan init "$SPEC_DIR" --type feature >/dev/null
bash "$CLI" plan merge "$SPEC_DIR" --patch --json "$(cat "$FIXTURE/plan.patch.json")" >/dev/null
bash "$CLI" plan validate "$SPEC_DIR"
bash "$CLI" plan list "$SPEC_DIR" --json >/dev/null
bash "$CLI" plan task "$SPEC_DIR" --status T1=running --summary "codex smoke claim" >/dev/null
bash "$CLI" plan task "$SPEC_DIR" --status T1=done --summary "codex smoke complete" >/dev/null
bash "$CLI" plan validate "$SPEC_DIR"

echo "codex blueprint smoke passed: $SPEC_DIR"
