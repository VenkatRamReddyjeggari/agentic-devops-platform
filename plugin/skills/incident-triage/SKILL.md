---
name: incident-triage
description: Triage a production incident on the EKS platform - gather signals with read-only kubectl, find the likely cause, propose a mitigation. Use when a service is down, pods are crashing, latency spikes, or an alert fires.
---

# Incident triage (read-only)

You may only run read-only commands (`kubectl get/describe/logs/top`, `aws ... describe-*`).
Mitigations are PROPOSED, never executed.

## 1. Scope (2 minutes)
```bash
kubectl get pods -n <ns> -o wide
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30
kubectl rollout history deploy/<app> -n <ns>
```
Answer: what is broken, since when, what changed last (deploy, config, node, dependency)?

## 2. Classify
| Symptom | Usual cause | Check |
|---|---|---|
| CrashLoopBackOff | bad config/secret, app bug | `kubectl logs --previous` |
| OOMKilled | memory limit too low / leak | `kubectl describe pod`, `kubectl top pod` |
| ImagePullBackOff | wrong tag, ECR auth | `describe pod` events |
| Pending | no capacity, PVC, affinity | `describe pod`, node group size |
| 5xx, pods healthy | downstream dependency, readiness | service endpoints, app logs |

## 3. Report
```
SEVERITY: SEV1/2/3
IMPACT:   who/what is affected
CAUSE:    most likely cause + evidence (log line / event)
MITIGATE: exact command for a human to run (e.g. `helm rollback orders-api <rev> -n orders-api`)
FOLLOW-UP: preventive fix (alert, limit change, test)
```
After resolution, offer to draft a postmortem with `/postmortem`.
