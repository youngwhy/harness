#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node "$ROOT/skills/google-search/vendor/web-search.mjs" --check >/tmp/harness-google-search-check.json || true
node "$ROOT/skills/dev-scan/vendor/chromux-search/web-search.mjs" --check >/tmp/harness-dev-scan-web-check.json || true
python3 "$ROOT/skills/dev-scan/vendor/hn-search/hn-search.py" --check >/tmp/harness-hn-check.json || true

# ProductHunt is credential-gated. Its check may fail when PRODUCT_HUNT_TOKEN is
# absent, but the dev-scan skill treats that source as optional.
python3 "$ROOT/skills/dev-scan/vendor/ph-search/ph-search.py" --check >/tmp/harness-ph-check.json || true

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])

skills = (
    "skills/dev-scan/SKILL.md",
    "skills/browser-work/SKILL.md",
    "skills/deep-research/SKILL.md",
    "skills/google-search/SKILL.md",
    "skills/reference-seek/SKILL.md",
)

agents = (
    "agents/browser-explorer.md",
    "agents/docs-researcher.md",
    "agents/external-researcher.md",
)

for canonical in skills:
    text = (root / canonical).read_text()
    if "Runtime Surface" not in text:
        raise SystemExit(f"{canonical}: missing Runtime Surface")
    if "codex/PLUGIN_RUNTIME.md" not in text:
        raise SystemExit(f"{canonical}: missing plugin runtime contract")

for canonical in agents:
    if not (root / canonical).exists():
        raise SystemExit(f"{canonical}: missing canonical prompt")

for path in [
    Path("/tmp/harness-google-search-check.json"),
    Path("/tmp/harness-dev-scan-web-check.json"),
    Path("/tmp/harness-hn-check.json"),
]:
    data = json.loads(path.read_text())
    if not isinstance(data.get("available"), bool):
        raise SystemExit(f"{path}: missing boolean availability result")
    if not data["available"]:
        print(f"optional research dependency unavailable: {data.get('error', path)}")

print("codex research smoke passed")
PY
