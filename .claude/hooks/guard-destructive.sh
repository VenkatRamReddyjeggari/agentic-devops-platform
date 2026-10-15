#!/usr/bin/env bash
# PreToolUse (Bash): block destructive infrastructure commands.
# Exit 2 = block; stderr is fed back to Claude so it can change approach.
# Defense in depth: permissions.deny covers the same verbs, but a hook still
# blocks when someone runs with --dangerously-skip-permissions.
#
# Fails closed: any error inside this script (missing jq, bad input) exits 2.
# Limits: this is pattern matching, not a shell parser. Indirection such as
# `v=apply; terraform $v` or `bash -c "$(...)"` can still get past it, so the
# agent's AWS/Kubernetes credentials must not allow these actions either.
set -euo pipefail
trap 'echo "BLOCKED: guard-destructive hook failed (line $LINENO); refusing to run unchecked." >&2; exit 2' ERR

command -v jq >/dev/null 2>&1 || { echo "BLOCKED: guard-destructive needs jq to inspect commands." >&2; exit 2; }

input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[[ -z "$cmd" ]] && exit 0

s='[[:blank:]]'            # spaces/tabs only: a match never spans lines
end='([[:space:];&|)]|$)'

# Patterns allow up to 4 flags/args between the tool and the verb
# (e.g. `terraform -chdir=envs/prod apply`, `kubectl -n orders delete pod x`).
blocked_patterns=(
  "terraform($s+[^[:space:];&|]+){0,4}$s+(apply|destroy|import|taint|force-unlock)$end"
  "terraform($s+[^[:space:];&|]+){0,4}$s+state$s+(rm|mv|push|replace-provider)$end"
  "kubectl($s+[^[:space:];&|]+){0,4}$s+(delete|drain)$end"
  "kubectl($s+[^[:space:];&|]+){0,4}$s+scale${s}[^;&|[:cntrl:]]*--replicas[= ]0$end"
  "helm($s+[^[:space:];&|]+){0,4}$s+(uninstall|delete)$end"
  "aws$s+[^;&|[:cntrl:]]*$s(delete|terminate|deregister)-"
  "aws$s+s3$s+(rm|rb)$end"
  "aws$s+s3$s+sync${s}[^;&|[:cntrl:]]*--delete"
  # recursive rm of /, ~, $HOME, ., .., * or a top-level repo directory
  "rm$s+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)($s+-[^[:space:]]+)*$s+[\"']?(/|~|\\\$HOME|\\\$\\{HOME\\}|\\.|\\.\\.|\\*|\\./?\\*|(\\./)?(app|charts|terraform|\\.git|\\.claude|\\.github|plugin|scripts|tests|docs))/?[\"']?$end"
  "git$s+push($s+[^[:space:];&|]+){0,4}$s+(--force[^[:space:]]*|-[a-zA-Z]*f[a-zA-Z]*|\\+[^[:space:]]+)$end"
  "git$s+(reset$s+--hard|clean$s+-[a-zA-Z]*f)"
)

for pattern in "${blocked_patterns[@]}"; do
  if [[ "$cmd" =~ $pattern ]]; then
    echo "BLOCKED by guard-destructive hook: '$cmd' matches '$pattern'." >&2
    echo "Destructive changes must go through a PR and be applied by a human. Propose a 'terraform plan' or a diff instead." >&2
    exit 2
  fi
done

exit 0
