#!/usr/bin/env bash
# PreToolUse (Edit|Write|NotebookEdit|Bash): stop changes to production config
# and access to secrets. Returns structured JSON so prod edits become an "ask"
# (human approval) while secret files are denied outright.
# Bash is checked too, so `sed -i` / `cat >` can't route around the Edit rules.
# Fails closed: any error inside this script exits 2 (block).
set -euo pipefail
trap 'echo "BLOCKED: protect-prod hook failed (line $LINENO); refusing to run unchecked." >&2; exit 2' ERR

command -v jq >/dev/null 2>&1 || { echo "BLOCKED: protect-prod needs jq to inspect tool input." >&2; exit 2; }

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"

decide() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

secret_msg="Use AWS Secrets Manager / External Secrets instead."
prod_msg="is PRODUCTION config. A human must approve this change."

if [[ "$tool" == "Bash" ]]; then
  cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
  [[ -z "$cmd" ]] && exit 0

  b='(^|[[:space:]/"'"'"'=<>|;&(])'   # start of a path token
  e='([[:space:]"'"'"';&|)>]|$)'      # end of a path token
  # File names only (`cert.pem`, `dir/x.key`), not jq paths like `.data.key`.
  secret_re="$b(\\.env(\\.[[:alnum:]_.-]+)?|([^[:space:]]*/)?[[:alnum:]_-][[:alnum:]_.-]*\\.(pem|key)|([^[:space:]]*/)?[[:alnum:]_.-]*secret[[:alnum:]_.-]*\\.tfvars)$e"
  if [[ "$cmd" =~ $secret_re ]]; then
    decide deny "Command touches a secret file ('${BASH_REMATCH[0]}'). $secret_msg"
  fi

  prod_re='(terraform/envs/prod|values-prod\.yaml)'
  # Commands that write to the paths they are given.
  write_re='(^|[[:space:];&|(])(sed[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i|perl[[:space:]]+-[a-zA-Z]*i|tee|cp|mv|rm|rmdir|truncate|install|ln|dd|patch|git[[:space:]]+(checkout|restore|apply|rm|mv))([[:space:]]|$)'
  # Redirects into files ask too, except into /dev/* and temp dirs
  # (e.g. `terraform -chdir=terraform/envs/prod plan > /tmp/plan.txt`).
  safe_target_re='^(/dev/|/tmp/|/private/tmp/|/var/folders/)'

  if [[ "$cmd" =~ $prod_re ]]; then
    [[ "$cmd" =~ $write_re ]] && decide ask "This command may modify PRODUCTION config (terraform/envs/prod or values-prod.yaml). A human must approve it."
    while read -r target; do
      [[ -z "$target" || "$target" =~ $safe_target_re ]] && continue
      decide ask "This command redirects output to '$target' while touching PRODUCTION config. A human must approve it."
    done < <(grep -oE '(^|[^<>&0-9])>>?[[:space:]]*[^[:space:]&;|]+' <<<"$cmd" | sed -E 's/^[^>]*>>?[[:space:]]*//' || true)
  fi
  exit 0
fi

file="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[[ -z "$file" ]] && exit 0
file="${file//\\//}"

case "$file" in
  *.env|*.env.*|*.pem|*.key|*secret*.tfvars)
    decide deny "Refusing to modify secret file '$file'. $secret_msg" ;;
  */terraform/envs/prod/*|terraform/envs/prod/*|*values-prod.yaml)
    decide ask "'$file' $prod_msg" ;;
esac

exit 0
