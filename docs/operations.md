# Operations runbook

Commands assume namespace `orders-api` and release `orders-api`. With Claude Code, the
`incident-triage` skill runs the read-only parts of this runbook for you.

## Reach the API

The Service is `ClusterIP` (no Ingress yet), so use a port-forward:

```bash
kubectl port-forward -n orders-api svc/orders-api 8080:80
curl -s localhost:8080/readyz
```

## Argo CD

```bash
kubectl get applications -n argocd               # SYNC STATUS / HEALTH for orders-api
kubectl describe application orders-api -n argocd
kubectl port-forward -n argocd svc/argocd-server 8443:443   # UI on https://localhost:8443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Argo CD polls GitHub about every 3 minutes. Self-heal reverts manual `kubectl` edits to
orders-api: change git instead.

## Health

```bash
kubectl get pods -n orders-api -o wide
kubectl get events -n orders-api --sort-by=.lastTimestamp | tail -30
kubectl logs -n orders-api deploy/orders-api --tail=100
kubectl rollout history deploy/orders-api -n orders-api
helm history orders-api -n orders-api
kubectl get hpa,pdb -n orders-api           # prod
```

| Probe | Path | Means |
|---|---|---|
| Liveness | `/healthz` (every 10 s after 10 s) | Process is up; failing restarts the container |
| Readiness | `/readyz` (every 5 s) | `ORDERS_TABLE` is set; failing removes the pod from the Service |

Readiness does **not** call DynamoDB. A pod that cannot reach the table is still "ready"
but answers order requests with 503, so watch logs for `DynamoDB call failed`.

## Troubleshooting

| Symptom | Likely cause | Check | Fix |
|---|---|---|---|
| Pods `Running` but `0/1` ready; `/readyz` → 503 `ORDERS_TABLE is not set` | Deployed without `ordersTable.name` | `kubectl describe pod`, look at env | Redeploy with `--set ordersTable.name=…` (dev) or check `values-prod.yaml` |
| `503 storage unavailable`; logs show `AccessDenied` or `WebIdentityErr` | Missing or wrong IRSA annotation, or release/namespace doesn't match the role's trust | `kubectl get sa orders-api -n orders-api -o yaml`; compare with `terraform output orders_api_role_arn` | Fix the annotation; deploy as release `orders-api` in namespace `orders-api`, or change the Terraform variables |
| `503`; logs show `ResourceNotFoundException` | Table name wrong, or Terraform not applied | `aws dynamodb describe-table --table-name <name>` | Apply Terraform; fix `ordersTable.name` |
| `503`; logs show timeouts or `EndpointConnectionError` | No egress (NAT) or wrong region | `AWS_REGION` in the pod; NAT gateway status | Fix routing; set `ordersTable.region` |
| `503`; logs show `ThrottlingException` | Burst above on-demand limits | CloudWatch DynamoDB metrics | Usually transient; retries absorb short bursts |
| Argo CD: `unable to resolve 'env/dev'` | No release has run yet, so the branch doesn't exist | Branches on GitHub | Run the **release** workflow |
| `ImagePullBackOff` | Wrong tag, image built for arm64, or ECR permissions | `kubectl describe pod` events | Re-run **release**; check the tag exists in ECR |
| Argo CD app `OutOfSync` / `Unknown` | Repo unreachable, bad chart change | `kubectl describe application orders-api -n argocd` | Fix the chart in git; check `gitops_repo_url` / `gitops_revision` |
| release workflow skipped | `AWS_ROLE_ARN` variable not set | Actions run log | Set the repository variables |
| release fails at AWS credentials | Role trust doesn't match repo/branch, or OIDC provider missing | Step log (`Not authorized to perform sts:AssumeRoleWithWebIdentity`) | Check `github_repository` / `release_branch` in bootstrap |
| release fails at the bump push | A ruleset on `env/*` blocks pushes (it should only block deletion and force pushes) | Step log | Fix the `protect-env-branches` ruleset ([repository security](repository-security.md#2-ruleset-for-deploy-branches)) |
| `CrashLoopBackOff` | App error at start | `kubectl logs --previous` | Fix and redeploy, or roll back |
| `OOMKilled` | Memory limit too low (2 workers + boto3) | `kubectl describe pod`, `kubectl top pod` | Raise `resources.limits.memory` |
| Pods `Pending` | No node capacity | `kubectl describe pod`, node group size | Raise node group max, or lower requests |
| Rollout stuck | New pods never ready | `kubectl rollout status`, readiness | Fix config, or `helm rollback` |

## Roll back

Dev is managed by Argo CD, so roll back in git: on the `env/dev` branch, revert the
`chore(release): deploy orders-api <tag> to dev` commit and push
(`git switch env/dev && git revert <sha> && git push`). For an immediate
rollback use **History and rollback** in the Argo CD UI, then revert in git so the next
sync doesn't roll forward again. Don't use `helm rollback` on dev: Argo CD would undo it.

App rollbacks do not touch data. For data, DynamoDB point-in-time recovery restores the
table (up to 35 days back) into a **new** table; point the chart at it or copy items back.

## Scale

- **dev:** `replicaCount` in `values.yaml` (default 1).
- **prod:** HPA 3–12 pods at 65 % CPU; PDB keeps at least 2 available during node drains.
- **Nodes:** `node_min_size` / `node_max_size` in the env's Terraform. The node group
  has fixed bounds; no cluster autoscaler is installed.
- **Database:** on-demand mode scales automatically; nothing to size.

## Security notes

- No static AWS credentials: IRSA only, scoped to one table and one ServiceAccount.
- Containers run as UID 10001, non-root, with a read-only root filesystem, no privilege
  escalation, all capabilities dropped and seccomp `RuntimeDefault`.
- The ServiceAccount does not automount a Kubernetes API token.
- Kubernetes secrets are KMS-encrypted; the table is encrypted at rest.
- Nodes are in private subnets. The dev API is allow-listed; the prod API is private.

## Cost estimate

Rough monthly figures for `us-east-1`, always on, before data transfer. Check current
AWS pricing before relying on them.

| Item | dev | prod |
|---|---|---|
| EKS control plane (~$0.10/h) | ~$73 | ~$73 |
| NAT gateways (~$33 each + data) | 1 → ~$33 | 3 → ~$99 |
| Nodes `t3.large` | 2 Spot → ~$40–60 | 3 On-Demand → ~$180 |
| KMS keys (EKS secrets; state bucket, shared) | ~$2 | ~$1 |
| ECR storage (30 images kept) | <$1 | shared |
| DynamoDB on-demand + PITR | ~$0–5 at demo volume | usage-based |
| **Total** | **~$150–175** | **~$355+** |

## Tear down

Teardown is destructive and always run by a human.

1. Nothing to uninstall by hand: Argo CD and the Application are Terraform resources and
   are destroyed first.
2. The orders table has deletion protection on. To delete it deliberately, set
   `deletion_protection = false` on `module.orders_table` in that env's `main.tf`,
   then plan, review and apply that change.
3. `terraform -chdir=terraform/envs/<env> destroy`. Review the plan output first.
4. Last, if you're done with the account: `terraform -chdir=terraform/bootstrap destroy`
   (empty the ECR repository and the versioned state bucket first).
