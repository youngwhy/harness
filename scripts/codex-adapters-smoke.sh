#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_CODEX_HOME="$(mktemp -d "${TMPDIR:-/tmp}/harness-codex-adapters.XXXXXX")"
trap 'rm -rf "$TMP_CODEX_HOME"' EXIT

PYTHON_BIN=""
for candidate in python3 python3.13 python3.12 python3.11; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import tomllib' >/dev/null 2>&1; then
    PYTHON_BIN="$candidate"
    break
  fi
done

if [[ -z "$PYTHON_BIN" ]]; then
  echo "codex adapter smoke requires Python 3.11+ with tomllib" >&2
  exit 1
fi

"$PYTHON_BIN" - "$ROOT" <<'PY'
from pathlib import Path
import sys
import tomllib

root = Path(sys.argv[1])
canonical_names = {
    path.stem
    for path in (root / "agents").glob("*.md")
    if path.stem != "_karpathy"
}
adapter_paths = sorted((root / "codex" / "agents").glob("harness-*.toml"))
adapter_names = {
    path.stem.removeprefix("harness-")
    for path in adapter_paths
}

if adapter_names != canonical_names:
    missing = sorted(canonical_names - adapter_names)
    extra = sorted(adapter_names - canonical_names)
    raise SystemExit(f"adapter coverage mismatch: missing={missing}, extra={extra}")

for path in adapter_paths:
    data = tomllib.loads(path.read_text())
    logical_name = path.stem.removeprefix("harness-")
    expected_name = f"harness-{logical_name}"
    expected_prompt = f"__HARNESS_PLUGIN_ROOT__/agents/{logical_name}.md"

    if data.get("name") != expected_name:
        raise SystemExit(f"{path}: expected name {expected_name}")
    if not data.get("description"):
        raise SystemExit(f"{path}: missing description")
    if expected_prompt not in data.get("developer_instructions", ""):
        raise SystemExit(f"{path}: missing canonical prompt {expected_prompt}")
    if "model" in data or "model_reasoning_effort" in data:
        raise SystemExit(f"{path}: model settings must inherit from Codex")
PY

CODEX_HOME="$TMP_CODEX_HOME" bash "$ROOT/scripts/install-codex-agent-adapters.sh" >/dev/null

"$PYTHON_BIN" - "$ROOT" "$TMP_CODEX_HOME" <<'PY'
from pathlib import Path
import sys
import tomllib

root = Path(sys.argv[1])
codex_home = Path(sys.argv[2])
installed = sorted((codex_home / "agents").glob("harness-*.toml"))

if not installed:
    raise SystemExit("no Codex adapters were installed")

for path in installed:
    text = path.read_text()
    if "__HARNESS_PLUGIN_ROOT__" in text:
        raise SystemExit(f"{path}: unresolved plugin root")

    data = tomllib.loads(text)
    logical_name = data["name"].removeprefix("harness-")
    canonical_prompt = root / "agents" / f"{logical_name}.md"
    if str(canonical_prompt) not in data["developer_instructions"]:
        raise SystemExit(f"{path}: missing resolved canonical prompt")
    if not canonical_prompt.exists():
        raise SystemExit(f"{canonical_prompt}: canonical prompt missing")

print(f"codex adapter smoke passed: {len(installed)} adapters")
PY
