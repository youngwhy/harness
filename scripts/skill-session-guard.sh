#!/bin/bash
# skill-session-guard.sh — Unified PreToolUse[Edit|Write] guard
#
# Reads: ~/.harness/{session_id}/state.json
# Behavior per skill:
#   - specify: DENY writes outside .harness/
#   - execute: WARN on writes outside .harness/ (allow but message)
#   - No session file: allow all

set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Read session state
STATE_FILE="$HOME/.harness/$SESSION_ID/state.json"
[[ ! -f "$STATE_FILE" ]] && exit 0

SKILL=$(jq -r '.skill // empty' "$STATE_FILE")
[[ -z "$SKILL" ]] && exit 0

# .harness/ files always allowed
[[ "$FILE_PATH" == *".harness/"* ]] && exit 0

# Skill-specific behavior for files outside .harness/
case "$SKILL" in
  specify)
    cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny"
  },
  "systemMessage": "PLAN MODE: Code modification not allowed. During specify phase, only .harness/ paths are writable. Implementation happens after plan approval."
}
EOF
    ;;
  execute)
    cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  },
  "systemMessage": "ORCHESTRATOR WARNING: Do not modify code directly. Delegate to worker agent using Agent(subagent_type=\"worker\")."
}
EOF
    ;;
esac

exit 0
