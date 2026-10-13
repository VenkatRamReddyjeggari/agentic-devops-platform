---
name: k8s-manifest-review
description: Review Kubernetes manifests and Helm charts for security, reliability and team standards. Use when creating or editing anything under charts/ or any Kubernetes YAML, or when asked to review a chart.
---

# Kubernetes manifest review

## Steps
1. Render the chart so you review what actually ships:
   `helm template charts/<chart> -f charts/<chart>/values.yaml > /tmp/rendered.yaml`
   (repeat with `values-prod.yaml` if prod values changed)
2. Run the bundled checker on the rendered output:
   `bash .claude/skills/k8s-manifest-review/scripts/check-manifests.sh /tmp/rendered.yaml`
3. If available, also run `kubeconform -strict -summary /tmp/rendered.yaml`
   and `trivy config charts/<chart>`.
4. Walk the checklist below for anything the script cannot judge.

## Checklist
| Area | Requirement |
|---|---|
| Images | Pinned tag or digest, never `:latest`; `imagePullPolicy: IfNotPresent` |
| Resources | `requests` and `limits` for cpu and memory on every container |
| Probes | `readinessProbe` and `livenessProbe` (plus `startupProbe` for slow starters) |
| Security | `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, drop `ALL` capabilities |
| Availability | `replicas >= 2` in prod, PodDisruptionBudget, HPA with sane min/max |
| Identity | ServiceAccount per app; AWS access via IRSA annotation, never static keys |
| Config | Secrets from External Secrets / Secrets Manager, never plaintext in values |

## Output format
Report findings as a table: `Severity | Resource | Finding | Fix`.
Severities: CRITICAL (security exposure), HIGH (outage risk), MEDIUM (standard violation), LOW (style).
End with a one-line verdict: `APPROVE`, `APPROVE WITH FIXES`, or `BLOCK`.
