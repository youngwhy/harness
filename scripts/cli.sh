#!/usr/bin/env bash
# harness-cli — the plugin's CLI, implemented in pure bash + jq (no npm dependency).
#
# Downstream skills/agents/hooks call it by path via
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/cli.sh" <group> <sub> ...
#
# Groups: req | plan | session | learning | issue
# Requires: bash 3.2+, jq 1.6+

set -uo pipefail

die() { printf '%s\n' "$*" >&2; exit 1; }
need_jq() { command -v jq >/dev/null 2>&1 || die "Error: jq is required but not installed"; }
need_jq

# ---------------------------------------------------------------------------
# arg parsing — mirrors cli/src/lib/args.js
#
# Sets associative-array-like globals via eval-friendly variable names:
#   ARG__<key>   for --key value or --flag
#   ARG_POS[]    positional args
# ---------------------------------------------------------------------------

ARG_POS=()
declare -a ARG_KEYS=()

reset_args() {
  ARG_POS=()
  for k in "${ARG_KEYS[@]:-}"; do unset "ARG__$k" 2>/dev/null || true; done
  ARG_KEYS=()
}

set_arg() {
  local key="$1" val="$2"
  local sanitized="${key//[^a-zA-Z0-9_]/_}"
  printf -v "ARG__$sanitized" '%s' "$val"
  ARG_KEYS+=("$sanitized")
}

get_arg() {
  local key="$1" sanitized
  sanitized="${key//[^a-zA-Z0-9_]/_}"
  local var="ARG__$sanitized"
  printf '%s' "${!var:-}"
}

has_arg() {
  local key="$1" sanitized
  sanitized="${key//[^a-zA-Z0-9_]/_}"
  local var="ARG__$sanitized"
  [[ -n "${!var+x}" ]]
}

parse_args() {
  reset_args
  while [[ $# -gt 0 ]]; do
    local a="$1"
    if [[ "$a" == "--" ]]; then
      shift; ARG_POS+=("$@"); break
    elif [[ "$a" == --* ]]; then
      local key="${a#--}"
      if [[ $# -gt 1 && "${2:0:2}" != "--" ]]; then
        set_arg "$key" "$2"; shift 2
      else
        set_arg "$key" "true"; shift
      fi
    else
      ARG_POS+=("$a"); shift
    fi
  done
}

# ---------------------------------------------------------------------------
# spec dir helpers
# ---------------------------------------------------------------------------

spec_plan_path() { printf '%s/plan.json' "$1"; }
spec_req_path()  { printf '%s/requirements.md' "$1"; }

write_json_atomic() {
  local path="$1" tmp="$1.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$path"
}

# ---------------------------------------------------------------------------
# req group
# ---------------------------------------------------------------------------

req_help() {
  cat <<'EOF'
Usage:
  cli.sh req init <spec_dir> --type <greenfield|feature|refactor|bugfix> [--goal "<text>"]
EOF
}

req_init() {
  parse_args "$@"
  local spec_dir="${ARG_POS[0]:-}"
  local type goal
  type="$(get_arg type)"
  goal="$(get_arg goal)"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> required"
  [[ -z "$type" ]] && die "Error: --type required (greenfield|feature|refactor|bugfix)"
  case "$type" in greenfield|feature|refactor|bugfix) ;; *) die "Error: --type must be greenfield|feature|refactor|bugfix" ;; esac

  mkdir -p "$spec_dir"
  local md
  md="$(spec_req_path "$spec_dir")"
  [[ -e "$md" ]] && die "Error: $md already exists"

  local goal_text="${goal:-<WRITE YOUR GOAL HERE>}"
  [[ "$goal_text" == "true" ]] && goal_text="<WRITE YOUR GOAL HERE>"

  cat > "$md" <<EOF
---
type: $type
goal: "$goal_text"
non_goals: []
---

# Requirements

<!-- /specify fills this in. Parent reqs use '## R-X<num>:' and sub-reqs use '#### R-X.Y:' with given/when/then fields. -->
EOF
  printf 'Wrote %s\n' "$md"
}

cmd_req() {
  local sub="${1:-}"
  case "$sub" in
    ""|--help|-h) req_help ;;
    init) shift; req_init "$@" ;;
    *) die "Error: unknown req command '$sub'" ;;
  esac
}

# ---------------------------------------------------------------------------
# plan group
# ---------------------------------------------------------------------------

plan_help() {
  cat <<'EOF'
Usage:
  cli.sh plan init <spec_dir> --type <t> [--force]
  cli.sh plan merge <spec_dir> --json '<payload>' [--patch|--append]
  cli.sh plan get <spec_dir> --path <dotted.path>
  cli.sh plan list <spec_dir> [--status <s>] [--json]
  cli.sh plan task <spec_dir> --status <T#>=<state> [--summary '...']
  cli.sh plan validate <spec_dir>
EOF
}

plan_init() {
  parse_args "$@"
  local spec_dir="${ARG_POS[0]:-}"
  local type force
  type="$(get_arg type)"
  force="$(get_arg force)"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> required"
  [[ -z "$type" ]] && die "Error: --type required (greenfield|feature|refactor|bugfix)"

  local path; path="$(spec_plan_path "$spec_dir")"
  if [[ -e "$path" && "$force" != "true" ]]; then
    die "Error: $path already exists (use --force to overwrite)"
  fi
  mkdir -p "$spec_dir"
  jq -n --arg type "$type" '{
    schema: "plan/v1",
    meta: { type: $type, goal: "<TBD>", non_goals: [] },
    contracts: { artifact: null, interfaces: [], invariants: [] },
    tasks: [],
    journeys: [],
    verify_plan: []
  }' | write_json_atomic "$path"
  printf 'Wrote %s\n' "$path"
}

# Plan validation — schema-light check + cross-reference integrity.
# We don't run full JSON Schema (no ajv); we enforce the load-bearing rules.
plan_validate_obj() {
  local plan="$1"
  local errs=()

  # Required top-level keys
  for k in schema meta tasks verify_plan; do
    if ! jq -e --arg k "$k" 'has($k)' <<<"$plan" >/dev/null; then
      errs+=("schema: missing required field '$k'")
    fi
  done

  # meta.type enum
  local mtype
  mtype="$(jq -r '.meta.type // empty' <<<"$plan")"
  if [[ -n "$mtype" ]]; then
    case "$mtype" in greenfield|feature|refactor|bugfix) ;;
      *) errs+=("schema: meta.type '$mtype' not in [greenfield,feature,refactor,bugfix]") ;;
    esac
  fi

  # tasks[].id pattern + status enum
  local bad
  bad="$(jq -r '[.tasks[]? | select(.id == null or (.id | test("^T[0-9]+$") | not))] | length' <<<"$plan")"
  [[ "$bad" -gt 0 ]] && errs+=("schema: $bad task(s) with invalid id (must match /^T[0-9]+\$/)")

  bad="$(jq -r '[.tasks[]? | select(.status != null and (.status as $s | ["pending","running","done","failed","blocked"] | index($s) == null))] | length' <<<"$plan")"
  [[ "$bad" -gt 0 ]] && errs+=("schema: $bad task(s) with invalid status")

  # journeys[].id pattern
  bad="$(jq -r '[.journeys[]? | select(.id == null or (.id | test("^J[0-9]+$") | not))] | length' <<<"$plan")"
  [[ "$bad" -gt 0 ]] && errs+=("schema: $bad journey(s) with invalid id (must match /^J[0-9]+\$/)")

  # verify_plan[].type enum
  bad="$(jq -r '[.verify_plan[]? | select(.type != null and .type != "sub_req" and .type != "journey")] | length' <<<"$plan")"
  [[ "$bad" -gt 0 ]] && errs+=("schema: $bad verify_plan entries with invalid type (must be sub_req|journey)")

  # Cross-ref: tasks.fulfills ⊆ verify_plan sub_req targets
  while IFS= read -r line; do
    [[ -n "$line" ]] && errs+=("$line")
  done < <(jq -r '
    (.verify_plan // []) as $vp
    | ([$vp[] | select(.type=="sub_req") | .target] | unique) as $sub_targets
    | (.tasks // [])[] as $t
    | ($t.fulfills // [])[] as $f
    | select($sub_targets | index($f) | not)
    | "task \($t.id) fulfills \"\($f)\" but no verify_plan entry of type=sub_req targets it"
  ' <<<"$plan")

  # Cross-ref: journeys.composes ⊆ sub_req targets
  while IFS= read -r line; do
    [[ -n "$line" ]] && errs+=("$line")
  done < <(jq -r '
    (.verify_plan // []) as $vp
    | ([$vp[] | select(.type=="sub_req") | .target] | unique) as $sub_targets
    | (.journeys // [])[] as $j
    | ($j.composes // [])[] as $c
    | select($sub_targets | index($c) | not)
    | "journey \($j.id) composes \"\($c)\" but no verify_plan entry of type=sub_req targets it"
  ' <<<"$plan")

  # Cross-ref: every journey.id has matching verify_plan journey entry
  while IFS= read -r line; do
    [[ -n "$line" ]] && errs+=("$line")
  done < <(jq -r '
    (.verify_plan // []) as $vp
    | ([$vp[] | select(.type=="journey") | .target] | unique) as $jt
    | (.journeys // [])[] as $j
    | select($jt | index($j.id) | not)
    | "journey \($j.id) declared but no verify_plan entry of type=journey targets it"
  ' <<<"$plan")

  # Cross-ref: verify_plan journey targets ⊆ journeys.id
  while IFS= read -r line; do
    [[ -n "$line" ]] && errs+=("$line")
  done < <(jq -r '
    ([(.journeys // [])[].id] | unique) as $jids
    | (.verify_plan // [])[] | select(.type=="journey") | .target as $t
    | select($jids | index($t) | not)
    | "verify_plan targets journey \"\($t)\" but no matching journey declaration exists"
  ' <<<"$plan")

  # Cross-ref: tasks.depends_on ⊆ tasks.id
  while IFS= read -r line; do
    [[ -n "$line" ]] && errs+=("$line")
  done < <(jq -r '
    ([(.tasks // [])[].id] | unique) as $ids
    | (.tasks // [])[] as $t
    | ($t.depends_on // [])[] as $d
    | select($ids | index($d) | not)
    | "task \($t.id) depends_on unknown task \"\($d)\""
  ' <<<"$plan")

  if [[ ${#errs[@]} -gt 0 ]]; then
    for e in "${errs[@]}"; do printf '✗ %s\n' "$e" >&2; done
    printf '\n%d error(s)\n' "${#errs[@]}" >&2
    return 1
  fi
  return 0
}

plan_merge() {
  parse_args "$@"
  local spec_dir="${ARG_POS[0]:-}"
  local payload patch append mode
  payload="$(get_arg json)"
  patch="$(get_arg patch)"
  append="$(get_arg append)"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> required"
  [[ -z "$payload" || "$payload" == "true" ]] && die "Error: --json <payload> required"

  if ! jq -e . >/dev/null 2>&1 <<<"$payload"; then
    die "Error: invalid --json payload"
  fi

  if   [[ "$patch" == "true" ]];  then mode="patch"
  elif [[ "$append" == "true" ]]; then mode="append"
  else                                  mode="replace"
  fi

  local path; path="$(spec_plan_path "$spec_dir")"
  local existing="{}"
  [[ -f "$path" ]] && existing="$(cat "$path")"

  local next
  case "$mode" in
    replace)
      next="$(jq -n --argjson b "$existing" --argjson p "$payload" '$b + $p')"
      ;;
    append)
      next="$(jq -n --argjson b "$existing" --argjson p "$payload" '
        reduce ($p | to_entries[]) as $e ($b;
          if ($e.value | type) == "array" and (.[$e.key] // null | type) == "array"
          then .[$e.key] = (.[$e.key] + $e.value)
          else .[$e.key] = $e.value
          end)
      ')"
      ;;
    patch)
      # Deep merge with array-merge-by-id behaviour matching json-io.js patchMerge.
      next="$(jq -n --argjson b "$existing" --argjson p "$payload" '
        def merge_by_id($a; $b):
          ($a + $b) as $all
          | if ([$all[] | objects | has("id")] | all) and (($a | length) > 0) and (($b | length) > 0)
            then
              ([$a[].id] + [$b[].id]) | unique as $ids
              | [ $ids[] as $id
                  | ( ([$a[] | select(.id == $id)] | first) // {} ) as $av
                  | ( ([$b[] | select(.id == $id)] | first) // {} ) as $bv
                  | $av + $bv ]
            else $b
            end;
        def patch($base; $payload):
          reduce ($payload | to_entries[]) as $e ($base;
            ($e.value) as $v
            | (.[$e.key]) as $cur
            | if ($v | type) == "array" and ($cur | type) == "array"
                then .[$e.key] = merge_by_id($cur; $v)
              elif ($v | type) == "object" and ($cur | type) == "object"
                then .[$e.key] = patch($cur; $v)
              else .[$e.key] = $v
              end);
        patch($b; $p)
      ')"
      ;;
  esac

  if ! plan_validate_obj "$next"; then
    printf 'Schema validation failed.\n' >&2
    exit 1
  fi

  printf '%s\n' "$next" | write_json_atomic "$path"
  printf 'Wrote %s (mode=%s)\n' "$path" "$mode"
}

plan_get() {
  parse_args "$@"
  local spec_dir="${ARG_POS[0]:-}"
  local path; path="$(get_arg path)"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> required"
  [[ -z "$path" || "$path" == "true" ]] && die "Error: --path required"

  local plan_path; plan_path="$(spec_plan_path "$spec_dir")"
  [[ -f "$plan_path" ]] || die "Error: plan.json not found in $spec_dir"

  # Convert dotted path with [N] into a jq path:  meta.type → .meta.type
  #                                               tasks[0].id → .tasks[0].id
  local jq_expr=".${path}"
  local val
  val="$(jq -e "$jq_expr" "$plan_path" 2>/dev/null)" || { printf 'path not found: %s\n' "$path" >&2; exit 1; }
  if [[ "$(jq -r 'type' <<<"$val")" == "string" ]]; then
    jq -r '.' <<<"$val"
  else
    printf '%s\n' "$val"
  fi
}

plan_list() {
  parse_args "$@"
  local spec_dir="${ARG_POS[0]:-}"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> required"

  # tolerate the call style `plan list <plan-path>` used by ultrawork-stop-hook.sh
  local plan_path
  if [[ -f "$spec_dir" ]]; then
    plan_path="$spec_dir"
  else
    plan_path="$(spec_plan_path "$spec_dir")"
  fi
  [[ -f "$plan_path" ]] || die "Error: plan.json not found ($plan_path)"

  local status as_json
  status="$(get_arg status)"
  as_json="$(get_arg json)"

  local tasks total
  total="$(jq '(.tasks // []) | length' "$plan_path")"
  if [[ -n "$status" && "$status" != "true" ]]; then
    tasks="$(jq --arg s "$status" '[(.tasks // [])[] | select(.status == $s)]' "$plan_path")"
  else
    tasks="$(jq '.tasks // []' "$plan_path")"
  fi

  local count; count="$(jq 'length' <<<"$tasks")"

  if [[ "$as_json" == "true" ]]; then
    jq -n --argjson t "$tasks" --argjson total "$total" --argjson filtered "$count" \
      '{tasks: $t, total: $total, filtered: $filtered}'
    return 0
  fi

  if [[ "$count" -eq 0 ]]; then
    if [[ -n "$status" && "$status" != "true" ]]; then
      printf "No tasks with status '%s'\n" "$status"
    else
      printf 'No tasks\n'
    fi
    return 0
  fi

  printf '%-6s%-14s%-6sACTION\n' "ID" "STATUS" "LAYER"
  printf -- '-%.0s' {1..60}; printf '\n'
  jq -r '.[] | [(.id // "-"), (.status // "pending"), (.layer // "-"), (.action // "")] | @tsv' <<<"$tasks" \
    | while IFS=$'\t' read -r id st layer act; do
        local trimmed="$act"
        if [[ ${#trimmed} -gt 50 ]]; then trimmed="${trimmed:0:47}..."; fi
        printf '%-6s%-14s%-6s%s\n' "$id" "$st" "$layer" "$trimmed"
      done
  printf '\n%d/%d tasks shown\n' "$count" "$total"
}

plan_task() {
  parse_args "$@"
  local spec_dir="${ARG_POS[0]:-}"
  local status_arg summary
  status_arg="$(get_arg status)"
  summary="$(get_arg summary)"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> required"
  [[ -z "$status_arg" || "$status_arg" == "true" ]] && die "Error: --status <task_id>=<state> required"

  if [[ "$status_arg" != *=* ]]; then
    die "Error: --status must be '<task_id>=<state>' (got '$status_arg')"
  fi
  local task_id="${status_arg%%=*}"
  local next_state="${status_arg#*=}"

  [[ "$task_id" =~ ^T[0-9]+$ ]] || die "Error: invalid task ID format '$task_id' (must match /^T[0-9]+\$/)"
  case "$next_state" in pending|running|done|failed|blocked) ;;
    *) die "Error: invalid state '$next_state'. Must be one of: pending, running, done, failed, blocked" ;;
  esac

  local plan_path; plan_path="$(spec_plan_path "$spec_dir")"
  [[ -f "$plan_path" ]] || die "Error: plan.json not found in $spec_dir"

  local plan; plan="$(cat "$plan_path")"
  local task; task="$(jq --arg id "$task_id" '.tasks // [] | map(select(.id == $id)) | first // null' <<<"$plan")"
  [[ "$task" == "null" ]] && die "Error: task '$task_id' not found in plan.json"

  local current_state
  current_state="$(jq -r '.status // "pending"' <<<"$task")"

  if [[ "$current_state" == "$next_state" ]]; then
    printf '%s: %s (no change)\n' "$task_id" "$next_state"
    return 0
  fi

  if [[ "$current_state" == "done" ]]; then
    printf "Error: task '%s' is already 'done' — INV-9 forbids re-transition to '%s'\n" "$task_id" "$next_state" >&2
    exit 1
  fi

  local next
  if [[ -n "$summary" && "$summary" != "true" ]]; then
    next="$(jq --arg id "$task_id" --arg s "$next_state" --arg sm "$summary" \
      '.tasks = ((.tasks // []) | map(if .id == $id then .status = $s | .summary = $sm else . end))' <<<"$plan")"
  else
    next="$(jq --arg id "$task_id" --arg s "$next_state" \
      '.tasks = ((.tasks // []) | map(if .id == $id then .status = $s else . end))' <<<"$plan")"
  fi

  if ! plan_validate_obj "$next"; then
    printf 'Schema validation failed.\n' >&2
    exit 1
  fi

  printf '%s\n' "$next" | write_json_atomic "$plan_path"
  if [[ -n "$summary" && "$summary" != "true" ]]; then
    printf '%s: %s → %s — %s\n' "$task_id" "$current_state" "$next_state" "$summary"
  else
    printf '%s: %s → %s\n' "$task_id" "$current_state" "$next_state"
  fi
}

plan_validate() {
  parse_args "$@"
  local spec_dir="${ARG_POS[0]:-}"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> required"
  local plan_path; plan_path="$(spec_plan_path "$spec_dir")"
  [[ -f "$plan_path" ]] || die "Error: plan.json not found in $spec_dir"

  local plan; plan="$(cat "$plan_path")"
  if plan_validate_obj "$plan"; then
    local nt nj nv
    nt="$(jq '(.tasks // []) | length' <<<"$plan")"
    nj="$(jq '(.journeys // []) | length' <<<"$plan")"
    nv="$(jq '(.verify_plan // []) | length' <<<"$plan")"
    printf '✓ plan.json valid — %s tasks, %s journeys, %s verify entries\n' "$nt" "$nj" "$nv"
  else
    exit 1
  fi
}

cmd_plan() {
  local sub="${1:-}"
  case "$sub" in
    ""|--help|-h) plan_help ;;
    init)     shift; plan_init "$@" ;;
    merge)    shift; plan_merge "$@" ;;
    get)      shift; plan_get "$@" ;;
    list)     shift; plan_list "$@" ;;
    task)     shift; plan_task "$@" ;;
    validate) shift; plan_validate "$@" ;;
    *) die "Error: unknown plan command '$sub'" ;;
  esac
}

# ---------------------------------------------------------------------------
# session group — state at $HOME/.harness/<sid>/state.json
# ---------------------------------------------------------------------------

session_state_path() {
  printf '%s/.harness/%s/state.json' "$HOME" "$1"
}

session_set() {
  parse_args "$@"
  local sid; sid="$(get_arg sid)"
  [[ -z "$sid" || "$sid" == "true" ]] && die "Error: --sid is required"

  local key val payload
  key="$(get_arg key)"
  val="$(get_arg value)"
  payload="$(get_arg json)"

  local path; path="$(session_state_path "$sid")"
  mkdir -p "$(dirname "$path")"
  local state="{}"
  [[ -f "$path" ]] && state="$(cat "$path")"

  local updates=()
  if [[ -n "$key" && "$key" != "true" ]]; then
    [[ -z "$val" || "$val" == "true" ]] && die "Error: --value is required when using --key"
    state="$(jq --arg k "$key" --arg v "$val" '.[$k] = $v' <<<"$state")"
    updates+=("$key=$val")
  fi

  if [[ -n "$payload" && "$payload" != "true" ]]; then
    if ! jq -e . >/dev/null 2>&1 <<<"$payload"; then
      die "Error: invalid JSON payload"
    fi
    state="$(jq -n --argjson b "$state" --argjson p "$payload" '
      def deep($a; $b):
        reduce ($b | to_entries[]) as $e ($a;
          if ($e.value | type) == "object" and (.[$e.key] // null | type) == "object"
            then .[$e.key] = deep(.[$e.key]; $e.value)
            else .[$e.key] = $e.value
          end);
      deep($b; $p)
    ')"
    updates+=("json merged")
  fi

  printf '%s\n' "$state" | write_json_atomic "$path"
  printf 'Session updated: %s\n' "$(IFS=, ; printf '%s' "${updates[*]:-}")"
}

session_get() {
  parse_args "$@"
  local sid; sid="$(get_arg sid)"
  [[ -z "$sid" || "$sid" == "true" ]] && die "Error: --sid is required"
  local path; path="$(session_state_path "$sid")"
  [[ -f "$path" ]] || die "Error: no session state found for $sid"
  cat "$path"
}

cmd_session() {
  local sub="${1:-}"
  case "$sub" in
    ""|--help|-h) printf 'Usage: cli.sh session set --sid <id> [--key k --value v] [--json ...]\n       cli.sh session get --sid <id>\n' ;;
    set) shift; session_set "$@" ;;
    get) shift; session_get "$@" ;;
    *) die "Error: unknown session command '$sub'" ;;
  esac
}

# ---------------------------------------------------------------------------
# learning + issue (context appenders)
# ---------------------------------------------------------------------------

read_json_input() {
  local payload="$1" use_stdin="$2"
  if [[ "$use_stdin" == "true" ]]; then
    payload="$(cat)"
  fi
  [[ -z "$payload" || "$payload" == "true" ]] && die "Error: --json or --stdin is required"
  if ! jq -e . >/dev/null 2>&1 <<<"$payload"; then
    die "Error: invalid JSON"
  fi
  printf '%s' "$payload"
}

context_append() {
  # $1=kind (learning|issue) $2=spec_dir $3=task_id $4=data_json
  local kind="$1" spec_dir="$2" task_id="$3" data="$4"

  local prefix file
  case "$kind" in
    learning) prefix="L"; file="learnings.json" ;;
    issue)    prefix="I"; file="issues.json"    ;;
  esac

  # Validate task against plan.json if it exists
  local plan_path validated="false" req_ids='[]'
  plan_path="$(spec_plan_path "$spec_dir")"
  if [[ -f "$plan_path" ]]; then
    local task
    task="$(jq --arg id "$task_id" '(.tasks // []) | map(select(.id == $id)) | first // null' "$plan_path")"
    if [[ "$task" == "null" ]]; then
      local available
      available="$(jq -r '[(.tasks // [])[].id] | join(", ") // "(none)"' "$plan_path")"
      die "Error: task not found: $task_id (available: $available)"
    fi
    validated="true"
    req_ids="$(jq '.fulfills // [] | unique' <<<"$task")"
  fi

  local ctx_dir="$spec_dir/context"
  mkdir -p "$ctx_dir"
  local out="$ctx_dir/$file"
  local arr='[]'
  [[ -f "$out" ]] && arr="$(cat "$out" 2>/dev/null || echo '[]')"
  if ! jq -e . >/dev/null 2>&1 <<<"$arr"; then arr='[]'; fi

  local max
  max="$(jq --arg p "$prefix" '[.[] | .id // "" | capture("^" + $p + "(?<n>[0-9]+)$") | .n | tonumber] | (max // 0)' <<<"$arr")"
  local new_id="${prefix}$((max + 1))"

  local entry
  if [[ "$kind" == "learning" ]]; then
    entry="$(jq -n --arg id "$new_id" --arg task "$task_id" --argjson v "$validated" --argjson reqs "$req_ids" --argjson d "$data" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      { id: $id, task: $task, task_id_validated: $v, requirements: $reqs,
        problem: ($d.problem // ""), cause: ($d.cause // ""), rule: ($d.rule // ""),
        tags: ($d.tags // []), created_at: $ts }
    ')"
  else
    local data_type
    data_type="$(jq -r '.type // ""' <<<"$data")"
    if [[ -n "$data_type" ]]; then
      case "$data_type" in failed_approach|out_of_scope|blocker) ;;
        *) die "Error: type must be one of: failed_approach, out_of_scope, blocker" ;;
      esac
    fi
    entry="$(jq -n --arg id "$new_id" --arg task "$task_id" --argjson v "$validated" --argjson d "$data" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      { id: $id, task: $task, task_id_validated: $v,
        type: ($d.type // ""), description: ($d.description // ""), created_at: $ts }
    ')"
  fi

  jq --argjson e "$entry" '. + [$e]' <<<"$arr" | write_json_atomic "$out"

  if [[ "$kind" == "learning" ]]; then
    local req_str; req_str="$(jq -r 'join(", ")' <<<"$req_ids")"
    printf "Added learning '%s' for task '%s' → requirements: [%s]\n" "$new_id" "$task_id" "$req_str"
  else
    printf "Added issue '%s' for task '%s'\n" "$new_id" "$task_id"
  fi
  printf '%s\n' "$entry"
}

cmd_learning() {
  if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: cli.sh learning --task <id> --json '{...}' <spec_dir>
       cli.sh learning --task <id> --stdin <spec_dir> << 'EOF'
EOF
    return 0
  fi
  parse_args "$@"
  local task_id spec_dir use_stdin payload
  task_id="$(get_arg task)"
  use_stdin="$(get_arg stdin)"
  payload="$(get_arg json)"
  spec_dir="${ARG_POS[0]:-}"
  [[ -z "$task_id" || "$task_id" == "true" ]] && die "Error: --task <task-id> is required"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> is required"
  local data; data="$(read_json_input "$payload" "$use_stdin")"
  context_append learning "$spec_dir" "$task_id" "$data"
}

cmd_issue() {
  if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: cli.sh issue --task <id> --json '{...}' <spec_dir>
       cli.sh issue --task <id> --stdin <spec_dir> << 'EOF'
EOF
    return 0
  fi
  parse_args "$@"
  local task_id spec_dir use_stdin payload
  task_id="$(get_arg task)"
  use_stdin="$(get_arg stdin)"
  payload="$(get_arg json)"
  spec_dir="${ARG_POS[0]:-}"
  [[ -z "$task_id" || "$task_id" == "true" ]] && die "Error: --task <task-id> is required"
  [[ -z "$spec_dir" ]] && die "Error: <spec_dir> is required"
  local data; data="$(read_json_input "$payload" "$use_stdin")"
  context_append issue "$spec_dir" "$task_id" "$data"
}

# ---------------------------------------------------------------------------
# top-level dispatch
# ---------------------------------------------------------------------------

main() {
  if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
Usage: cli.sh <group> <subcommand> [options]
Groups: req | plan | session | learning | issue
EOF
    return 0
  fi
  if [[ "$1" == "--version" ]]; then
    local ver
    ver="$(jq -r .version "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")"/..; pwd)}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")"
    printf '%s\n' "$ver"
    return 0
  fi

  local group="$1"; shift
  case "$group" in
    req)      cmd_req "$@" ;;
    plan)     cmd_plan "$@" ;;
    session)  cmd_session "$@" ;;
    learning) cmd_learning "$@" ;;
    issue)    cmd_issue "$@" ;;
    *) die "Error: unknown group '$group'" ;;
  esac
}

main "$@"
