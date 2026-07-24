#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
TARGET="$CODEX_HOME/agents"

mkdir -p "$TARGET"

for file in "$ROOT"/codex/agents/*.toml; do
  dest="$TARGET/$(basename "$file")"
  install -m 0644 "$file" "$dest"

  python3 - "$dest" "$ROOT" <<'PY'
from pathlib import Path
import sys

adapter_path = Path(sys.argv[1])
root = sys.argv[2]

text = adapter_path.read_text()
text = text.replace("__HARNESS_PLUGIN_ROOT__", root)

if "__HARNESS_PLUGIN_ROOT__" in text:
    raise SystemExit(f"{adapter_path}: unresolved root placeholder")

adapter_path.write_text(text)
PY

  echo "installed $dest"
done

echo "Restart Codex before relying on harness-* native agent names."
