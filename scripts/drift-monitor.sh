#!/bin/bash
# drift-monitor.sh — PostToolUse[Edit|Write] drift & stagnation monitor
#
# Ouroboros-inspired always-on counterpart to /stepback: watches the edit
# stream for mechanical warning signs and nudges via systemMessage.
#
# Signals (priority order, one message per event):
#   OSCILLATION — a file's content hash returned to an earlier state
#                 (edit ↔ revert cycle; likely thrashing between approaches)
#   SPINNING    — same file edited >= SPIN_THRESHOLD times this session
#   DRIFT CHECK — during /execute or /ralph, every DRIFT_EVERY project edits,
#                 remind the agent to re-align with the plan/DoD
#
# Advisory only — never blocks the tool call. Logs to:
#   ~/.harness/{session_id}/files/edit-log.tsv  (path<TAB>cksum lines)

set -uo pipefail   # no -e: monitoring must never break the tool call

SPIN_THRESHOLD=7
DRIFT_EVERY=15

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && exit 0

SESSION_DIR="$HOME/.harness/$SESSION_ID"
STATE_FILE="$SESSION_DIR/state.json"

# Only monitor inside an active harness session (skill session or ralph loop)
[[ -f "$STATE_FILE" ]] || exit 0

# Ignore harness-internal artifacts (qa-log, DoD, specs, session files)
case "$FILE_PATH" in
  *".harness/"* | "$HOME/.harness/"*) exit 0 ;;
esac

mkdir -p "$SESSION_DIR/files"
LOG="$SESSION_DIR/files/edit-log.tsv"
touch "$LOG"

# Content fingerprint after the edit (cheap; skip unreadable files)
HASH=""
[[ -r "$FILE_PATH" ]] && HASH=$(cksum "$FILE_PATH" 2>/dev/null | awk '{print $1}')

# --- Oscillation: current hash matches an EARLIER state of the same file,
#     and the file has changed in between (A -> B -> A) -----------------
oscillated=0
if [[ -n "$HASH" ]]; then
  prev_hashes=$(awk -F'\t' -v p="$FILE_PATH" '$1 == p {print $2}' "$LOG")
  last_hash=$(printf '%s\n' "$prev_hashes" | tail -n 1)
  if [[ -n "$last_hash" && "$last_hash" != "$HASH" ]] \
     && printf '%s\n' "$prev_hashes" | grep -qx "$HASH"; then
    oscillated=1
  fi
fi

# Append AFTER oscillation check so the current edit doesn't match itself
printf '%s\t%s\n' "$FILE_PATH" "$HASH" >> "$LOG"

if [[ "$oscillated" == "1" ]]; then
  jq -n --arg f "$FILE_PATH" \
    '{systemMessage: ("DRIFT MONITOR — OSCILLATION: " + $f + " just returned to an earlier content state (edit-revert cycle). You may be thrashing between two approaches. Stop, state which approach you are committing to and why, then proceed deliberately — do not silently flip again.")}'
  exit 0
fi

# --- Spinning: same file edited too many times -------------------------
file_edits=$(awk -F'\t' -v p="$FILE_PATH" '$1 == p' "$LOG" | wc -l | tr -d ' ')
if [[ "$file_edits" -ge "$SPIN_THRESHOLD" ]] && (( file_edits % SPIN_THRESHOLD == 0 )); then
  jq -n --arg f "$FILE_PATH" --argjson n "$file_edits" \
    '{systemMessage: ("DRIFT MONITOR — SPINNING: " + $f + " has been edited " + ($n|tostring) + " times this session. Repeated edits to one file usually mean the approach is wrong, not the code. Re-read the failing requirement/DoD item, question your current hypothesis, and consider a different strategy before editing this file again.")}'
  exit 0
fi

# --- Periodic drift check (execute / ralph sessions only) ---------------
SKILL=$(jq -r '.skill // empty' "$STATE_FILE")
IN_RALPH=$(jq -r 'if .ralph then "1" else "" end' "$STATE_FILE")
if [[ "$SKILL" == "execute" || "$SKILL" == "ultrawork" || -n "$IN_RALPH" ]]; then
  total_edits=$(wc -l < "$LOG" | tr -d ' ')
  if (( total_edits > 0 && total_edits % DRIFT_EVERY == 0 )); then
    if [[ -n "$IN_RALPH" ]]; then
      target="the original prompt and the DoD checklist"
    else
      spec_dir=$(jq -r '.spec_dir // empty' "$STATE_FILE")
      target="an in-progress task in ${spec_dir:-the spec dir}/plan.json"
    fi
    jq -n --argjson n "$total_edits" --arg t "$target" \
      '{systemMessage: ("DRIFT MONITOR — CHECKPOINT (" + ($n|tostring) + " edits this session): confirm the change you just made serves " + $t + ". If you cannot name which requirement/DoD item it advances, you have drifted — stop expanding scope and re-align before the next edit.")}'
    exit 0
  fi
fi

exit 0
