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

# A PATH with the basic tools but no jq, to prove the hooks fail closed.
nojq_bin="$(mktemp -d)"
trap 'rm -rf "$nojq_bin"' EXIT
for t in bash cat grep sed; do ln -s "$(command -v "$t")" "$nojq_bin/$t"; done

expect_exit() { # name, expected_code, json, script, [nojq]
  local path="$PATH"
  [[ "${5:-}" == nojq ]] && path="$nojq_bin"
  PATH="$path" bash "$4" <<<"$3" >/dev/null 2>&1; local code=$?
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
expect_exit "blocks rm -rf ~"               2 "$(bash_cmd 'rm -rf ~')" "$hooks/guard-destructive.sh"
expect_exit "blocks rm -rf ."               2 "$(bash_cmd 'rm -rf .')" "$hooks/guard-destructive.sh"
# shellcheck disable=SC2016 # literal $HOME is the input under test
expect_exit "blocks rm -rf \$HOME"         2 "$(bash_cmd 'rm -rf $HOME')" "$hooks/guard-destructive.sh"
expect_exit "blocks rm -r terraform"        2 "$(bash_cmd 'rm -r terraform')" "$hooks/guard-destructive.sh"
expect_exit "blocks rm -fr ./charts/"       2 "$(bash_cmd 'rm -fr ./charts/')" "$hooks/guard-destructive.sh"
expect_exit "blocks rm -rf /"               2 "$(bash_cmd 'rm -rf /')" "$hooks/guard-destructive.sh"
expect_exit "allows rm -rf .terraform"      0 "$(bash_cmd 'rm -rf terraform/envs/dev/.terraform')" "$hooks/guard-destructive.sh"
expect_exit "allows rm -rf tmp dir"         0 "$(bash_cmd 'rm -rf /tmp/render')" "$hooks/guard-destructive.sh"
expect_exit "blocks git push -f"            2 "$(bash_cmd 'git push -f origin main')" "$hooks/guard-destructive.sh"
expect_exit "blocks git push +refspec"      2 "$(bash_cmd 'git push origin +main')" "$hooks/guard-destructive.sh"
expect_exit "allows git push -u"            0 "$(bash_cmd 'git push -u origin fix/x')" "$hooks/guard-destructive.sh"
expect_exit "allows push to feature branch" 0 "$(bash_cmd 'git push origin feature/fix-thing')" "$hooks/guard-destructive.sh"
expect_exit "blocks aws s3 rm"              2 "$(bash_cmd 'aws s3 rm s3://bucket --recursive')" "$hooks/guard-destructive.sh"
expect_exit "blocks aws s3 sync --delete"   2 "$(bash_cmd 'aws s3 sync . s3://b --delete')" "$hooks/guard-destructive.sh"
expect_exit "allows aws s3 ls"              0 "$(bash_cmd 'aws s3 ls')" "$hooks/guard-destructive.sh"
expect_exit "blocks terraform state rm"     2 "$(bash_cmd 'terraform state rm module.eks')" "$hooks/guard-destructive.sh"
expect_exit "allows terraform state list"   0 "$(bash_cmd 'terraform state list')" "$hooks/guard-destructive.sh"
expect_exit "blocks terraform import"       2 "$(bash_cmd 'terraform -chdir=x import aws_s3_bucket.b b')" "$hooks/guard-destructive.sh"
expect_exit "blocks scale to zero"          2 "$(bash_cmd 'kubectl scale deploy/orders-api --replicas=0')" "$hooks/guard-destructive.sh"
expect_exit "allows scale to 10"            0 "$(bash_cmd 'kubectl scale deploy/orders-api --replicas=10')" "$hooks/guard-destructive.sh"
expect_exit "blocks kubectl drain"          2 "$(bash_cmd 'kubectl drain node-1')" "$hooks/guard-destructive.sh"
expect_exit "blocks git clean -fd"          2 "$(bash_cmd 'git clean -fd')" "$hooks/guard-destructive.sh"
expect_exit "fails closed without jq"       2 "$(bash_cmd 'terraform apply')" "$hooks/guard-destructive.sh" nojq
expect_exit "allows heredoc mentioning tf"  0 "$(bash_cmd $'python3 - <<EOF\nx = "trivy config terraform/"\nimport pathlib\nEOF')" "$hooks/guard-destructive.sh"
expect_exit "allows tf word across lines"   0 "$(bash_cmd $'terraform plan\necho delete me')" "$hooks/guard-destructive.sh"
expect_exit "blocks apply on next line"     2 "$(bash_cmd $'terraform plan\nterraform apply')" "$hooks/guard-destructive.sh"
expect_exit "allows prose about tf/apply"   0 "$(bash_cmd 'echo "terraform changes need review before anyone may apply"')" "$hooks/guard-destructive.sh"
expect_exit "blocks kubectl 4 flags delete" 2 "$(bash_cmd 'kubectl -n orders --context prod delete pod x')" "$hooks/guard-destructive.sh"
expect_exit "blocks apply after ;"         2 "$(bash_cmd 'cd x; terraform -chdir=y apply')" "$hooks/guard-destructive.sh"

echo "protect-prod.sh"
expect_decision "asks for prod tf edit"     ask  "$(edit_file "$root/terraform/envs/prod/main.tf")" "$hooks/protect-prod.sh"
expect_decision "asks for prod values"      ask  "$(edit_file "$root/charts/orders-api/values-prod.yaml")" "$hooks/protect-prod.sh"
expect_decision "denies .env edit"          deny "$(edit_file "$root/.env")" "$hooks/protect-prod.sh"
expect_decision "denies pem edit"           deny "$(edit_file "$root/certs/server.pem")" "$hooks/protect-prod.sh"
expect_decision "no decision for dev edit"  none "$(edit_file "$root/terraform/envs/dev/main.tf")" "$hooks/protect-prod.sh"
expect_decision "asks for prod notebook"    ask  "$(jq -n --arg f "$root/terraform/envs/prod/x.ipynb" '{tool_name:"NotebookEdit",tool_input:{notebook_path:$f}}')" "$hooks/protect-prod.sh"
expect_decision "asks for sed -i on prod"   ask  "$(bash_cmd 'sed -i "" s/3/1/ charts/orders-api/values-prod.yaml')" "$hooks/protect-prod.sh"
expect_decision "asks for redirect to prod" ask  "$(bash_cmd 'echo x > terraform/envs/prod/main.tf')" "$hooks/protect-prod.sh"
expect_decision "asks for cd prod + write"  ask  "$(bash_cmd 'cd terraform/envs/prod && echo x >> main.tf')" "$hooks/protect-prod.sh"
expect_decision "asks for cp over prod"     ask  "$(bash_cmd 'cp /tmp/v.yaml charts/orders-api/values-prod.yaml')" "$hooks/protect-prod.sh"
expect_decision "no decision prod read"     none "$(bash_cmd 'cat charts/orders-api/values-prod.yaml')" "$hooks/protect-prod.sh"
expect_decision "no decision prod plan"     none "$(bash_cmd 'terraform -chdir=terraform/envs/prod plan -no-color > /tmp/plan.txt 2>&1')" "$hooks/protect-prod.sh"
expect_decision "no decision dev sed -i"    none "$(bash_cmd 'sed -i "" s/a/b/ charts/orders-api/values.yaml')" "$hooks/protect-prod.sh"
expect_decision "denies cat .env"           deny "$(bash_cmd 'cat .env')" "$hooks/protect-prod.sh"
expect_decision "denies reading a key"      deny "$(bash_cmd 'head certs/server.key')" "$hooks/protect-prod.sh"
expect_decision "denies secret tfvars"      deny "$(bash_cmd 'cat terraform/envs/prod/secrets.tfvars')" "$hooks/protect-prod.sh"
expect_decision "no decision .venv"         none "$(bash_cmd 'source .venv/bin/activate')" "$hooks/protect-prod.sh"
expect_decision "no decision jq .key"       none "$(bash_cmd "jq -r '.data.key' x.json")" "$hooks/protect-prod.sh"
expect_exit     "fails closed without jq"   2    "$(edit_file "$root/terraform/envs/prod/main.tf")" "$hooks/protect-prod.sh" nojq

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
