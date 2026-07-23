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

# Escalation flag (set by the agent when ralph-strategist returns
# escalate_to_user=true) -> end the loop and hand the decision to the user
ESCALATE_FLAG="$SESSION_DIR/files/ralph-escalate"
if [ -f "$ESCALATE_FLAG" ]; then
    jq 'del(.ralph)' "$STATE_FILE" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"
    rm -f "$DOD_FILE" "$VERIFY_FLAG" "$ESCALATE_FLAG"
    jq -n \
      '{decision: "block", reason: "RALPH LOOP: Escalated to user by strategist verdict. The loop has ended. Present to the user: the escalation reason, the remaining unchecked DoD items, and the strategy ledger summary (ralph-strategy.md in the session files directory). Then await their decision — do not resume work on this task without new user input.", systemMessage: "Ralph loop ended via user escalation. State cleaned up; strategy ledger preserved."}'
    exit 0
fi

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
      --arg strategy_file "$SESSION_DIR/files/ralph-strategy.md" \
      '{decision: "block", reason: ("RALPH LOOP: Stagnation circuit breaker fired — " + ($unchecked|tostring) + " of " + ($total|tostring) + " DoD items unresolved and no progress across 4 consecutive iterations despite strategy revision. Force-stopping. Read the strategy ledger at " + $strategy_file + " (if present) and summarize for the user: which items keep failing, which strategies/lenses were attempted with what outcome, and what decision or scope change you recommend."), systemMessage: "Ralph loop terminated by stagnation circuit breaker (4 iterations without DoD progress). State cleaned up; strategy ledger preserved for the post-mortem."}'
    exit 0
fi

# One full cycle with zero progress -> forced strategy revision (self-correcting)
# A fresh-context ralph-strategist produces a NEW strategy through an untried
# lens; the strategy ledger (ralph-strategy.md) makes "keep grinding without a
# new strategy" mechanically detectable.
stagnation_directive=""
if [ "$stagnant" -ge 2 ]; then
    STRATEGY_FILE="$SESSION_DIR/files/ralph-strategy.md"
    strat_count=$(grep -c '^## Strategy' "$STRATEGY_FILE" 2>/dev/null || true)
    [ -z "$strat_count" ] && strat_count=0
    last_strat=$(jq -r '.ralph.strategy_count // 0' "$STATE_FILE")
    jq --argjson sc "$strat_count" '.ralph.strategy_count = $sc' \
       "$STATE_FILE" > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"

    if [ "$strat_count" -gt "$last_strat" ]; then
        # A new strategy was adopted since the last stagnation check — hold the line.
        stagnation_directive="

🔄 STAGNATION (${stagnant} iterations without DoD progress) — Strategy #${strat_count} is already on file at ${STRATEGY_FILE}. Follow ITS steps exactly this iteration. Its banned_moves are forbidden — do not drift back to the pre-revision approach. If this strategy also fails a full cycle, the next stagnation check will require a new one."
    else
        stagnation_directive="

🔄 STAGNATION DETECTED (${stagnant} iterations without DoD progress). Your context is part of the problem — you keep regenerating the same failing approach. Before ANY further fix attempt:
1. Spawn the strategist: Agent tool, subagent_type=\"ralph-strategist\", FOREGROUND (run_in_background=false). Pass: the original task, the DoD file path (${DOD_FILE}), the strategy ledger path (${STRATEGY_FILE}), and your best evidence of the failure.
2. Append its result to ${STRATEGY_FILE} as:
   ## Strategy $((strat_count + 1)) — <lens> (iteration ${iteration})
   diagnosis / banned moves / steps from the JSON, then 'outcome: pending'
3. Execute the new strategy's steps. banned_moves are FORBIDDEN this iteration.
4. If the strategist returned escalate_to_user=true: record its escalation_reason in the ledger, run \`touch ${SESSION_DIR}/files/ralph-escalate\`, then stop — the loop will end and hand the decision to the user.
Continuing to grind without a new ledger entry is a protocol violation — the loop checks."
    fi
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
