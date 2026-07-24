#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
contract = root / "codex" / "PLUGIN_RUNTIME.md"
if not contract.is_file():
    raise SystemExit("missing codex/PLUGIN_RUNTIME.md")

manifest = json.loads((root / ".codex-plugin" / "plugin.json").read_text())
if manifest.get("skills") != "./skills/":
    raise SystemExit("Codex manifest must expose canonical skills/")

legacy_files = [
    *root.glob("codex/agents/*.toml"),
    *root.glob("codex/skills/*/SKILL.md"),
]
if legacy_files:
    raise SystemExit(f"legacy Codex adapters remain: {legacy_files}")

for name in (
    "install-codex-agent-adapters.sh",
    "install-codex-skill-adapters.sh",
    "codex-adapters-smoke.sh",
):
    if (root / "scripts" / name).exists():
        raise SystemExit(f"legacy installer remains: scripts/{name}")

runtime_skills = (
    "agent",
    "blueprint",
    "browser-work",
    "bugfix",
    "check",
    "clarify",
    "council",
    "deep-research",
    "dev-scan",
    "discuss",
    "execute",
    "google-search",
    "ralph",
    "reference-seek",
    "scaffold",
    "specify",
)
for name in runtime_skills:
    path = root / "skills" / name / "SKILL.md"
    text = path.read_text()
    if "codex/PLUGIN_RUNTIME.md" not in text:
        raise SystemExit(f"{path.relative_to(root)}: missing plugin runtime contract")

roles = sorted(
    path for path in (root / "agents").glob("*.md") if not path.name.startswith("_")
)
if len(roles) != 27:
    raise SystemExit(f"expected 27 canonical roles, found {len(roles)}")

contract_text = contract.read_text()
for role in roles:
    if not role.read_text().strip():
        raise SystemExit(f"{role.relative_to(root)}: empty role prompt")
if "spawn_agent(agent_type=" in contract_text:
    raise SystemExit("plugin runtime must not assume spawn_agent agent_type")

print(f"codex plugin runtime smoke passed ({len(roles)} canonical roles)")
PY
