---
description: Pre-deployment gate for a Helm release - lint, render, policy-check, security-scan, and summarize risk
argument-hint: <chart-name> [dev|prod]
allowed-tools: Bash(helm lint:*), Bash(helm template:*), Bash(kubeconform:*), Bash(trivy:*), Bash(git diff:*), Read, Grep
---

Run a pre-deployment check for chart `$1` targeting environment `$2` (default: dev).

1. `helm lint charts/$1`
2. Render with the right values file (`values.yaml` for dev, add `-f charts/$1/values-prod.yaml` for prod)
   and validate with `kubeconform -strict -summary`.
3. Apply the `k8s-manifest-review` skill to the rendered output.
4. Delegate a security pass to the `security-scanner` subagent.
5. Show `git diff origin/main -- charts/$1` and summarize what changes for users.

Finish with:
```
DEPLOY CHECK: <chart> → <env>
Result:  GO / NO-GO
Risks:   ...
Rollback: helm rollback <release> <previous-revision> -n <namespace>
```
Do not deploy. A human runs the deploy after reading this.
