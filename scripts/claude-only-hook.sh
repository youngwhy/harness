#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${CODEX_THREAD_ID:-}" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="${1:-}"

case "$HOOK_NAME" in
  ""|*[!A-Za-z0-9._-]*)
    echo "invalid hook name: $HOOK_NAME" >&2
    exit 64
    ;;
esac

HOOK_PATH="$SCRIPT_DIR/$HOOK_NAME"
if [[ ! -x "$HOOK_PATH" ]]; then
  echo "hook is not executable: $HOOK_PATH" >&2
  exit 66
fi

exec "$HOOK_PATH"
