# Deployment guide

From an empty AWS account to a running `orders-api` in dev, then prod.

> **Who runs what.** Claude Code may prepare code, run `plan`, `lint` and `template`,
> and open PRs. Every step that creates, changes or deletes real resources
> (`terraform apply`, `helm upgrade`, `docker push`, AWS CLI writes) is run by a human.
> Hooks block the agent from doing them.

> **Cost.** A running environment costs money every hour (EKS control plane, NAT
> gateways, nodes). See [cost estimate](operations.md#cost-estimate) and
> [tear-down](operations.md#tear-down).

## Prerequisites

- AWS account and CLI v2 with credentials that can create VPC, EKS, IAM, DynamoDB, S3, ECR
- Terraform ≥ 1.6, kubectl, Helm 3, Docker with `buildx`
- A CIDR for your own IP or VPN, for dev's API allow-list (for example `203.0.113.10/32`)

Examples use `us-east-1`. Replace `<account-id>` and the bucket and table names.

## 1. Bootstrap Terraform state

Create once per account (all environments share it; each uses its own key):

```bash
aws s3api create-bucket --bucket <your-org>-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket <your-org>-tfstate \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket <your-org>-tfstate \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket <your-org>-tfstate \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws dynamodb create-table --table-name <your-org>-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

Then replace `REPLACE-ME-tfstate` and `REPLACE-ME-tflock` in
`terraform/envs/dev/backend.tf` (and `prod/backend.tf`, which needs approval) and
commit through a PR.

## 2. Create the dev infrastructure

```bash
TF="terraform -chdir=terraform/envs/dev"
$TF init
$TF plan -var 'api_allowed_cidrs=["203.0.113.10/32"]' -out=dev.plan
# review: VPC, NAT, EKS cluster + node group, KMS key, orders table, IAM role (all "create")
$TF apply dev.plan
```

EKS takes roughly 15–20 minutes. Then configure kubectl:

```bash
$($TF output -raw kubeconfig_command)
kubectl get nodes
```

## 3. Build and push the image

There is no ECR repository in Terraform yet, so create one once:

```bash
aws ecr create-repository --repository-name orders-api \
  --image-scanning-configuration scanOnPush=true --image-tag-mutability IMMUTABLE
```

Build for the nodes' architecture (`t3` is x86_64; this matters on Apple Silicon) and
tag with the git SHA (never `latest`):

```bash
REG=<account-id>.dkr.ecr.us-east-1.amazonaws.com
TAG=$(git rev-parse --short HEAD)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$REG"
docker buildx build --platform linux/amd64 -t "$REG/orders-api:$TAG" --push app/
```

## 4. Deploy orders-api to dev

```bash
TF="terraform -chdir=terraform/envs/dev"
helm upgrade --install orders-api charts/orders-api -n orders-api --create-namespace \
  --set image.repository="$REG/orders-api" \
  --set image.tag="$TAG" \
  --set env.APP_VERSION="$TAG" \
  --set ordersTable.name="$($TF output -raw orders_table_name)" \
  --set-string serviceAccount.annotations.eks\.amazonaws\.com/role-arn="$($TF output -raw orders_api_role_arn)"
kubectl rollout status deploy/orders-api -n orders-api
```

The release name and namespace must both be `orders-api`, or the IRSA trust will not
match (change `orders_api_release` / `orders_api_namespace` in Terraform if you need
others). Before deploying, `/deploy-check orders-api dev` in Claude Code gives a GO/NO-GO.

## 5. Verify

```bash
kubectl port-forward -n orders-api svc/orders-api 8080:80 &
curl -s localhost:8080/readyz
ID=$(curl -s -X POST localhost:8080/orders -H 'Content-Type: application/json' \
  -d '{"item":"widget","quantity":2}' | jq -r .id)
kubectl rollout restart deploy/orders-api -n orders-api
kubectl rollout status deploy/orders-api -n orders-api
curl -s localhost:8080/orders/$ID     # still there after the restart
```

Restart the `port-forward` if it drops during the rollout.

## 6. Production

Same steps against `terraform/envs/prod`, with these differences:

- The prod API endpoint is **private**. Run `terraform apply`, `kubectl` and `helm`
  from inside the VPC (VPN, bastion or a CI runner with network access).
- `terraform plan` output goes into the PR; a human reviews it before `apply`.
- The table name is already set in `values-prod.yaml`; pass only the image and the role:

```bash
TF="terraform -chdir=terraform/envs/prod"
helm upgrade --install orders-api charts/orders-api -n orders-api --create-namespace \
  -f charts/orders-api/values-prod.yaml \
  --set image.repository="$REG/orders-api" --set image.tag="$TAG" --set env.APP_VERSION="$TAG" \
  --set-string serviceAccount.annotations.eks\.amazonaws\.com/role-arn="$($TF output -raw orders_api_role_arn)"
```

Apply the prod Terraform **before** deploying this chart version to prod. Without the
table and role, pods stay not-ready and the rollout stalls (old pods keep serving).

## Rollback

```bash
helm history orders-api -n orders-api
helm rollback orders-api <revision> -n orders-api
```

Data is unaffected by app rollbacks. To restore table data, use DynamoDB point-in-time
recovery (restores into a new table).
