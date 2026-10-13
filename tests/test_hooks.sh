#!/usr/bin/env bash
# Behavior tests for the guardrail hooks: feed them the same JSON Claude Code
# sends on stdin and assert the exit code / decision.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hooks="$root/.claude/hooks"
pass=0 fail=0

ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; fail=$((fail + 1)); }

bash_cmd() { jq -n --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
edit_file() { jq -n --arg f "$1" '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$f}}'; }

expect_exit() { # name, expected_code, json, script
  bash "$4" <<<"$3" >/dev/null 2>&1; local code=$?
  [[ $code -eq $2 ]] && ok "$1" || bad "$1 (exit $code, want $2)"
}

expect_decision() { # name, expected_decision, json, script
  local got
  got="$(bash "$4" <<<"$3")"
  got="$(jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"${got:-{\}}" 2>/dev/null)"
  [[ "$got" == "$2" ]] && ok "$1" || bad "$1 (got $got, want $2)"
}

echo "guard-destructive.sh"
expect_exit "blocks terraform apply"        2 "$(bash_cmd 'terraform -chdir=terraform/envs/prod apply -auto-approve')" "$hooks/guard-destructive.sh"
expect_exit "blocks terraform destroy"      2 "$(bash_cmd 'terraform destroy')" "$hooks/guard-destructive.sh"
expect_exit "blocks kubectl delete"         2 "$(bash_cmd 'kubectl delete ns orders')" "$hooks/guard-destructive.sh"
expect_exit "blocks helm uninstall"         2 "$(bash_cmd 'helm uninstall orders-api -n orders')" "$hooks/guard-destructive.sh"
expect_exit "blocks aws terminate"          2 "$(bash_cmd 'aws ec2 terminate-instances --instance-ids i-123')" "$hooks/guard-destructive.sh"
expect_exit "blocks force push"             2 "$(bash_cmd 'git push origin main --force')" "$hooks/guard-destructive.sh"
expect_exit "blocks kubectl -n x delete"    2 "$(bash_cmd 'kubectl -n orders delete pod orders-1')" "$hooks/guard-destructive.sh"
expect_exit "blocks chained apply"          2 "$(bash_cmd 'terraform plan && terraform apply')" "$hooks/guard-destructive.sh"
expect_exit "allows terraform plan"         0 "$(bash_cmd 'terraform plan')" "$hooks/guard-destructive.sh"
expect_exit "allows plan -out apply.plan"   0 "$(bash_cmd 'terraform -chdir=terraform/envs/dev plan -out=apply.plan')" "$hooks/guard-destructive.sh"
expect_exit "allows kubectl get"            0 "$(bash_cmd 'kubectl get pods -A')" "$hooks/guard-destructive.sh"
expect_exit "allows helm template"          0 "$(bash_cmd 'helm template charts/orders-api')" "$hooks/guard-destructive.sh"

echo "protect-prod.sh"
expect_decision "asks for prod tf edit"     ask  "$(edit_file "$root/terraform/envs/prod/main.tf")" "$hooks/protect-prod.sh"
expect_decision "asks for prod values"      ask  "$(edit_file "$root/charts/orders-api/values-prod.yaml")" "$hooks/protect-prod.sh"
expect_decision "denies .env edit"          deny "$(edit_file "$root/.env")" "$hooks/protect-prod.sh"
expect_decision "denies pem edit"           deny "$(edit_file "$root/certs/server.pem")" "$hooks/protect-prod.sh"
expect_decision "no decision for dev edit"  none "$(edit_file "$root/terraform/envs/dev/main.tf")" "$hooks/protect-prod.sh"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
