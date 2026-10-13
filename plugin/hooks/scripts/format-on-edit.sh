#!/usr/bin/env bash
# PostToolUse (Edit|Write): auto-format the file Claude just changed.
# Missing formatters are skipped silently so the hook never breaks a session.
set -uo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
[[ -z "$file" || ! -f "$file" ]] && exit 0

have() { command -v "$1" >/dev/null 2>&1; }

case "$file" in
  *.tf|*.tfvars)  have terraform && terraform fmt "$file" >/dev/null ;;
  *.py)           have ruff && ruff format -q "$file" && ruff check -q --fix "$file" ;;
  *.sh)           have shellcheck && { shellcheck "$file" >&2 || echo "shellcheck findings in $file (see above)" >&2; } ;;
  */charts/*)     have helm && { helm lint "${file%%/templates/*}" >/dev/null 2>&1 || echo "helm lint failed after editing $file" >&2; } ;;
esac

exit 0
