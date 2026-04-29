#!/bin/bash
# session-compact-hook.sh - Unified SessionStart[compact] hook
#
# Purpose: After compaction, tell Claude which skill was running and where
#          to find the session state. The skill itself handles the rest.
# Activation: SessionStart with matcher "compact"
#
# Reads: ~/.hoyeon/{session_id}/state.json
#
# Output: skill name + state.json path → Claude reads state and resumes

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id')

# ── Read session state ──

STATE_FILE="$HOME/.hoyeon/$SESSION_ID/state.json"
[[ ! -f "$STATE_FILE" ]] && exit 0

SKILL=$(jq -r '.skill // empty' "$STATE_FILE")
[[ -z "$SKILL" ]] && exit 0

# ── Output minimal recovery context ──

cat <<EOF

[session recovery] Compaction detected.
skill: $SKILL
state: $STATE_FILE

Resume the /$SKILL workflow. Read $STATE_FILE for all context paths and session state.
EOF

exit 0
