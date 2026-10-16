# Deployment guide

From an empty AWS account to `orders-api` running in **dev**, delivered by GitOps:

```
merge to main ─► release.yml: test → build image → push to ECR (OIDC, no keys)
                              └─► commit new tag to charts/orders-api/values-dev.yaml
                                                │
EKS dev:  Argo CD ◄──── pulls chart + values from GitHub ┘
            └─► syncs orders-api (Helm), prunes and self-heals drift
```

Nothing outside the cluster needs network access to the Kubernetes API, so dev's API
stays limited to your IP.

> **Who runs what.** Claude Code prepares code and runs `plan`, `lint` and `template`.
> A human runs every `terraform apply` and sets GitHub repository variables. Hooks block
> the agent from applying.

> **Cost.** About $150–175/month while dev runs (see the
> [cost estimate](operations.md#cost-estimate)). [Tear it down](operations.md#tear-down)
> when you're done.

## Prerequisites (on your Mac)

```bash
brew install awscli kubectl        # Terraform and Helm are already installed
aws configure                      # an IAM user/role that can create VPC, EKS, IAM, S3, KMS, DynamoDB, ECR
aws sts get-caller-identity        # confirm the account
curl -s https://checkip.amazonaws.com   # your public IP, for api_allowed_cidrs
```

Docker is **not** needed: images are built by GitHub Actions.

## 1. Bootstrap the account (once)

`terraform/bootstrap` creates the state bucket (KMS-encrypted, versioned, TLS-only), the
lock table, the ECR repository, and the GitHub OIDC provider plus the role CI uses to push
images. It may push only to that one repository, and only from workflows on `main` of
this GitHub repo.

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan -out=bootstrap.plan
terraform -chdir=terraform/bootstrap apply bootstrap.plan
terraform -chdir=terraform/bootstrap output
```

If the account already has a GitHub OIDC provider, add
`-var create_github_oidc_provider=false` to `plan`. This root keeps **local** state in
`terraform/bootstrap/terraform.tfstate` (gitignored); keep that file safe.

## 2. Point dev at the state bucket

Edit `terraform/envs/dev/backend.tf`: replace `REPLACE-ME-tfstate` with the
`state_bucket` output and `REPLACE-ME-tflock` with the `lock_table` output. Commit it
through a PR. Bucket and table names are not secret, but the bucket name contains your
account ID; if the repo is public and that matters to you, pass them at init time instead:

```bash
terraform -chdir=terraform/envs/dev init \
  -backend-config="bucket=<state_bucket>" -backend-config="dynamodb_table=<lock_table>"
```

## 3. Tell GitHub where to push

GitHub → repository → **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value |
|---|---|
| `AWS_ROLE_ARN` | `ci_role_arn` output from step 1 |
| `AWS_REGION` | `us-east-1` (or your region) |
| `ECR_REPOSITORY` | optional; defaults to `orders-api` |

These are variables, not secrets: the role can only be assumed by this repo's `main`
branch through OIDC, so the ARN is useless to anyone else.

## 4. Build the first image

GitHub → **Actions → release → Run workflow** (branch `main`). It runs the tests, builds
a `linux/amd64` image, pushes `orders-api:<12-char git sha>` to ECR, and commits that tag
to `charts/orders-api/values-dev.yaml`. After this, every merge that touches `app/` does
the same automatically.

Until this first run, `values-dev.yaml` holds the placeholder tag `bootstrap`; if dev is
created before the first image exists, the pods sit in `ImagePullBackOff` until the
release workflow runs, then recover on their own.

## 5. Create dev

```bash
TF="terraform -chdir=terraform/envs/dev"
$TF init                                   # or with -backend-config, see step 2
$TF plan -var 'api_allowed_cidrs=["<your-ip>/32"]' -out=dev.plan
$TF apply dev.plan
```

One apply creates the VPC, the EKS cluster and nodes, the orders table and its IRSA role,
**Argo CD**, and the Argo CD Application for orders-api. EKS takes roughly 15–20 minutes.
Terraform reaches the new cluster with a token from your AWS credentials, so your IP must
be in `api_allowed_cidrs`.

The Application points Argo CD at `charts/orders-api` on `main` with `values.yaml` +
`values-dev.yaml`, and injects the ECR repository URL, the IRSA role ARN and the table
name (so the account ID never lands in git). Sync is automated, with prune and self-heal.

## 6. Verify

```bash
$($TF output -raw kubeconfig_command)
kubectl get pods -n argocd
kubectl get pods -n orders-api
kubectl port-forward -n orders-api svc/orders-api 8080:80 &
curl -s localhost:8080/readyz
ID=$(curl -s -X POST localhost:8080/orders -H 'Content-Type: application/json' \
  -d '{"item":"widget","quantity":2}' | jq -r .id)
kubectl rollout restart deploy/orders-api -n orders-api
kubectl rollout status deploy/orders-api -n orders-api
curl -s localhost:8080/orders/$ID          # still there after the restart: DynamoDB works
```

Restart the `port-forward` if it drops during the rollout.

Argo CD UI: run `$TF output -raw argocd_ui_command`, open https://localhost:8443, and log
in as `admin` with the password from `$TF output -raw argocd_password_command`.

## Everyday flow

1. Open a PR that changes `app/`; CI runs.
2. Merge. `release.yml` builds and pushes the image and commits the new tag to
   `values-dev.yaml` as `github-actions[bot]`.
3. Argo CD sees the commit (it polls every ~3 minutes) and rolls it out.

Chart changes (templates, `values.yaml`, `values-dev.yaml`) also deploy to dev as soon as
they reach `main`, because Argo CD tracks the branch.

If you enable branch protection on `main`, allow `github-actions[bot]` to push, or switch
the bump step to open a PR instead.

## Rollback

Revert the tag commit and Argo CD rolls back:

```bash
git revert <sha of "chore(release): deploy orders-api …">   # via a PR
```

For an immediate rollback, use the Argo CD UI (**History and rollback**). Automated sync
will move forward again on the next commit, so follow up with the revert. App rollbacks
never touch data; for data, use DynamoDB point-in-time recovery (restores into a new table).

## Production

Prod stays **code-only** for now: its Terraform and `values-prod.yaml` are ready, but
there is no Argo CD wiring, and its API endpoint is private (applies and syncs must run
from inside the VPC). Mirror `terraform/envs/dev/argocd.tf` into prod with a
`values-prod.yaml`-based Application, pin `gitops_revision` to a release tag rather than
`main`, and promote by changing that tag through a reviewed PR.
