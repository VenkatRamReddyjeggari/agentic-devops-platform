#!/usr/bin/env bash
# PreToolUse (Edit|Write): stop edits to production config and secrets.
# Returns structured JSON so prod edits become an "ask" (human approval)
# while secret files are denied outright.
set -euo pipefail

input="$(cat)"
file="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
[[ -z "$file" ]] && exit 0
file="${file//\\//}"

decide() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

case "$file" in
  *.env|*.env.*|*.pem|*.key|*secret*.tfvars)
    decide deny "Refusing to modify secret file '$file'. Use AWS Secrets Manager / External Secrets instead." ;;
  */terraform/envs/prod/*|terraform/envs/prod/*|*values-prod.yaml)
    decide ask "'$file' is PRODUCTION config. A human must approve this edit." ;;
esac

exit 0
