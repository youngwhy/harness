#!/bin/bash
# Ralph Loop Stop hook - DoD verification with prompt re-injection
# Blocks Claude from stopping if unchecked DoD items remain.
# Re-injects original prompt via "reason" field (like official ralph-wiggum).
# Verification status goes in "systemMessage" (separated concerns).

# Read JSON from stdin
input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')

if [ -z "$session_id" ]; then
    exit 0
fi

SESSION_DIR="$HOME/.harness/$session_id"
STATE_FILE="$SESSION_DIR/state.json"
DOD_FILE="$SESSION_DIR/files/ralph-dod.md"
VERIFY_FLAG="$SESSION_DIR/files/ralph-verify"

# No state file or no .ralph namespace = not in Ralph Loop
if [[ ! -f "$STATE_FILE" ]] || ! jq -e '.ralph' "$STATE_FILE" >/dev/null 2>&1; then
    exit 0
fi

# Read state
iteration=$(jq -r '.ralph.iteration // 0' "$STATE_FILE")
max_iterations=$(jq -r '.ralph.max_iterations // 10' "$STATE_FILE")
original_prompt=$(jq -r '.ralph.prompt // ""' "$STATE_FILE")
iteration=$((iteration + 1))

# Update iteration count (atomic write)
jq --argjson iter "$iteration" '.ralph.iteration = $iter' "$STATE_FILE" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"

# Safety: max iterations exceeded -> force cleanup and allow exit
if [ "$iteration" -gt "$max_iterations" ]; then
    jq 'del(.ralph)' "$STATE_FILE" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"
    rm -f "$DOD_FILE" "$VERIFY_FLAG"
    jq -n \
      --argjson iter "$max_iterations" \
      '{decision: "block", reason: ("RALPH LOOP: Circuit breaker fired — max iterations (" + ($iter|tostring) + ") exceeded. Force-stopping. Please review the task manually."), systemMessage: "Ralph loop terminated by circuit breaker. State cleaned up."}'
    exit 0
fi

# Check if DoD file exists
if [ ! -f "$DOD_FILE" ]; then
    jq -n \
      --arg prompt "$original_prompt" \
      --argjson iter "$iteration" \
      --argjson max "$max_iterations" \
      '{decision: "block", reason: $prompt, systemMessage: ("Ralph iteration " + ($iter|tostring) + "/" + ($max|tostring) + ". DoD file not found! Create the Definition of Done checklist first.")}'
    exit 0
fi

# Count unchecked and checked items
unchecked=$(grep -c '^[[:space:]]*[-*] \[ \]' "$DOD_FILE" 2>/dev/null || true)
[ -z "$unchecked" ] && unchecked=0
checked=$(grep -c '^[[:space:]]*[-*] \[[xX]\]' "$DOD_FILE" 2>/dev/null || true)
[ -z "$checked" ] && checked=0
total=$((unchecked + checked))

# No checklist items found
if [ "$total" -eq 0 ]; then
    jq -n \
      --arg prompt "$original_prompt" \
      --argjson iter "$iteration" \
      --argjson max "$max_iterations" \
      '{decision: "block", reason: $prompt, systemMessage: ("Ralph iteration " + ($iter|tostring) + "/" + ($max|tostring) + ". DoD file exists but has no checklist items. Write proper criteria as - [ ] items.")}'
    exit 0
fi

# --- Stagnation tracking (ouroboros-inspired circuit breaker) ---------------
# Healthy loops alternate verify-iterations (unchecked drops) with
# fix-iterations (unchecked holds), so equal counts across 2 stops are normal.
# stagnant_rounds >= 2 means a full fix+verify cycle produced zero progress.
prev_unchecked=$(jq -r '.ralph.prev_unchecked // -1' "$STATE_FILE")
stagnant=$(jq -r '.ralph.stagnant_rounds // 0' "$STATE_FILE")
if [ "$prev_unchecked" -ge 0 ] && [ "$unchecked" -ge "$prev_unchecked" ] && [ "$unchecked" -gt 0 ]; then
    stagnant=$((stagnant + 1))
else
    stagnant=0
fi
jq --argjson pu "$unchecked" --argjson st "$stagnant" \
   '.ralph.prev_unchecked = $pu | .ralph.stagnant_rounds = $st' \
   "$STATE_FILE" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"

# Two full cycles with zero progress -> stagnation circuit breaker (early exit)
if [ "$stagnant" -ge 4 ]; then
    jq 'del(.ralph)' "$STATE_FILE" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"
    rm -f "$DOD_FILE" "$VERIFY_FLAG"
    jq -n \
      --argjson unchecked "$unchecked" \
      --argjson total "$total" \
      '{decision: "block", reason: ("RALPH LOOP: Stagnation circuit breaker fired — " + ($unchecked|tostring) + " of " + ($total|tostring) + " DoD items unresolved and no progress across 4 consecutive iterations. The current approach is not converging. Force-stopping. Summarize for the user: which items keep failing, what was tried, and what different approach (or scope change) you recommend."), systemMessage: "Ralph loop terminated by stagnation circuit breaker (4 iterations without DoD progress). State cleaned up."}'
    exit 0
fi

# One full cycle with zero progress -> demand an approach change this iteration
stagnation_directive=""
if [ "$stagnant" -ge 2 ]; then
    stagnation_directive="

🔄 STAGNATION DETECTED (${stagnant} iterations without DoD progress). Diagnose the pattern before acting:
- SPINNING: retrying the same fix on the same file → your hypothesis about the cause is wrong. Re-read the failing item's actual error output from scratch.
- OSCILLATION: flipping between two approaches → commit to one, state why, and see it through.
- DIMINISHING RETURNS: shrinking tweaks with no verdict change → the fix is in the wrong layer. Widen the search (config, environment, test itself).
You MUST take a visibly different approach this iteration — same-approach retry is forbidden. If an item's premise now looks wrong, say so to the user instead of grinding."
fi

# Unchecked items remain -> set verify flag + block with verifier agent instruction
if [ "$unchecked" -gt 0 ]; then
    # Create verify flag so ralph-dod-guard.sh allows DoD edits during verification
    touch "$VERIFY_FLAG"

    remaining=$(grep '^[[:space:]]*[-*] \[ \]' "$DOD_FILE" | sed 's/^[[:space:]]*[-*] \[ \] /  - /')

    jq -n \
      --arg prompt "$original_prompt" \
      --argjson iter "$iteration" \
      --argjson max "$max_iterations" \
      --argjson unchecked "$unchecked" \
      --argjson total "$total" \
      --arg items "$remaining" \
      --arg dod_file "$DOD_FILE" \
      --arg stagnation "$stagnation_directive" \
      '{
        decision: "block",
        reason: $prompt,
        systemMessage: ("Ralph iteration " + ($iter|tostring) + "/" + ($max|tostring) + ". " + ($unchecked|tostring) + " of " + ($total|tostring) + " DoD items NOT verified.\n\n⚡ SPAWN VERIFIER AGENT: Use the Agent tool with subagent_type=\"ralph-verifier\" to independently verify DoD items.\n⚠️ MUST use FOREGROUND (run_in_background=false). Background spawn causes the main agent to stop early, triggering the Stop hook and breaking the loop.\n\nPass this prompt to the agent:\n  \"Verify the DoD checklist at: " + $dod_file + "\nOriginal task: " + $prompt + "\"\n\nAfter the verifier returns:\n1. Parse the JSON results\n2. For each PASS item → change - [ ] to - [x] in the DoD file\n3. For each FAIL item → fix the issue, then let the next iteration re-verify\n\nRemaining items:\n" + $items + $stagnation)
      }'
    exit 0
fi

# All items checked -> cleanup and allow stop
jq 'del(.ralph)' "$STATE_FILE" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"
rm -f "$DOD_FILE" "$VERIFY_FLAG"
exit 0
