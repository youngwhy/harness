#!/bin/bash
# skill-session-cleanup.sh — SessionEnd cleanup
#
# Deletes: ~/.harness/{session_id}/ (entire session directory)
# Also GC's orphaned session dirs older than 24 hours.

set -euo pipefail

HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id')

# Guard: prevent rm -rf ~/.harness/ if SESSION_ID is empty or null
if [[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]]; then
  exit 0
fi

SESSION_DIR="$HOME/.harness/$SESSION_ID"

if [[ -d "$SESSION_DIR" ]]; then
  rm -rf "$SESSION_DIR"
fi

# Orphan GC: delete session dirs older than 24 hours
[[ -d "$HOME/.harness" ]] && find "$HOME/.harness" -mindepth 1 -maxdepth 1 -type d -mmin +1440 -exec rm -rf {} \; 2>/dev/null || true

exit 0
