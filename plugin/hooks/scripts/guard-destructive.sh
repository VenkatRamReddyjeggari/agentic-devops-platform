#!/usr/bin/env bash
# PreToolUse (Bash): block destructive infrastructure commands.
# Exit 2 = block; stderr is fed back to Claude so it can change approach.
# Defense in depth: permissions.deny covers the same verbs, but a hook still
# blocks when someone runs with --dangerously-skip-permissions.
set -euo pipefail

input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[[ -z "$cmd" ]] && exit 0

# Patterns allow flags between the tool and the verb
# (e.g. `terraform -chdir=envs/prod apply`, `kubectl -n orders delete pod x`).
blocked_patterns=(
  'terraform([[:space:]]+[^[:space:]]+)*[[:space:]]+(apply|destroy)([[:space:]]|$)'
  'kubectl([[:space:]]+[^[:space:]]+)*[[:space:]]+delete([[:space:]]|$)'
  'helm([[:space:]]+[^[:space:]]+)*[[:space:]]+(uninstall|delete)([[:space:]]|$)'
  'aws[[:space:]]+.*[[:space:]](delete|terminate|deregister)-'
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f?[[:space:]]+/'
  'git[[:space:]]+push[[:space:]].*--force'
)

for pattern in "${blocked_patterns[@]}"; do
  if [[ "$cmd" =~ $pattern ]]; then
    echo "BLOCKED by guard-destructive hook: '$cmd' matches '$pattern'." >&2
    echo "Destructive changes must go through a PR and be applied by a human. Propose a 'terraform plan' or a diff instead." >&2
    exit 2
  fi
done

exit 0
