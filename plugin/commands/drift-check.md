---
description: Detect Terraform drift for an environment and explain it in plain language
argument-hint: [dev|prod]
allowed-tools: Bash(terraform init:*), Bash(terraform plan:*), Bash(terraform show:*), Read
---

Check environment `$ARGUMENTS` (default `dev`) for drift between code and AWS.

1. `terraform -chdir=terraform/envs/$ARGUMENTS init -input=false`
2. `terraform -chdir=terraform/envs/$ARGUMENTS plan -detailed-exitcode -input=false -out=/tmp/drift.plan`
   - exit 0 → no drift, stop and say so
   - exit 2 → drift exists, continue
3. `terraform -chdir=terraform/envs/$ARGUMENTS show -no-color /tmp/drift.plan`
4. Summarize using the `terraform-module` skill's plan-summary format. For each drifted
   resource, say whether the code or the console change is probably "right".

Never run apply. Recommend either a code change (PR) or `terraform apply` by a human.
