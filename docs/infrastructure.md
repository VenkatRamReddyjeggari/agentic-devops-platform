# Infrastructure (Terraform)

```
terraform/
├── modules/
│   ├── vpc/            # wraps terraform-aws-modules/vpc/aws ~> 5.0
│   ├── eks/            # wraps terraform-aws-modules/eks/aws ~> 20.0
│   └── orders-table/   # DynamoDB table + IRSA role for orders-api
└── envs/
    ├── dev/            # backend.tf · providers.tf · main.tf · variables.tf · outputs.tf · .terraform.lock.hcl
    └── prod/           # same layout; protected (hooks ask a human before any edit)
```

Each environment root calls the modules in order `vpc → eks → orders_table`. Provider
`hashicorp/aws ~> 5.0` (locked to 5.100.0 in `.terraform.lock.hcl`), Terraform `>= 1.6`.

## Conventions

These come from `CLAUDE.md` and the `terraform-module` skill, and are checked in review:

- Every variable has `description` and `type`; validations where a bad value is likely.
- No hardcoded account IDs, regions, ARNs, AMIs or CIDRs inside modules.
- Versions pinned with `~>`; provider lock files committed.
- Tags come from `default_tags` in each env's provider (`Environment`, `ManagedBy`,
  `Repository`); modules accept an extra `tags` map.
- Least-privilege IAM scoped to specific ARNs; encryption on by default.
- New modules go into dev first; prod changes only via PR with plan output.
- Accepted Trivy findings carry an inline `#trivy:ignore:<ID>` with a justification.

## Module: `vpc`

| Input | Type | Default | Description |
|---|---|---|---|
| `name` | string | (required) | Name prefix |
| `cidr` | string | (required) | VPC CIDR (a `/16` is expected) |
| `azs` | list(string) | (required) | Availability zones (the envs use the first 3) |
| `single_nat_gateway` | bool | `true` | One shared NAT (dev) or one per AZ (prod) |
| `tags` | map(string) | `{}` | Extra tags |

Subnets are carved automatically: private `cidrsubnet(cidr, 4, i)` (`/20` each), public
`cidrsubnet(cidr, 8, 48 + i)` (`/24` each). Public subnets are tagged
`kubernetes.io/role/elb`, private ones `kubernetes.io/role/internal-elb`.

Outputs: `vpc_id`, `private_subnet_ids`, `public_subnet_ids`.

## Module: `eks`

| Input | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | (required) | Cluster name |
| `cluster_version` | string | (required) | Kubernetes version (envs default `1.31`) |
| `vpc_id` | string | (required) | VPC |
| `subnet_ids` | list(string) | (required) | Private subnets |
| `endpoint_public_access` | bool | `false` | Expose the API publicly |
| `endpoint_public_access_cidrs` | list(string) | `[]` | Allow-list for the public API; `0.0.0.0/0` rejected |
| `node_instance_types` | list(string) | `["t3.large"]` | Node instance types |
| `node_capacity_type` | string | `ON_DEMAND` | `ON_DEMAND` or `SPOT` |
| `node_min_size` / `node_max_size` / `node_desired_size` | number | 2 / 5 / 2 | Node group size |
| `tags` | map(string) | `{}` | Extra tags |

What it sets up: IRSA enabled; KMS envelope encryption for Kubernetes secrets; add-ons
CoreDNS, kube-proxy, VPC CNI and EKS Pod Identity Agent; one managed node group
`general` labelled `workload=general`; cluster-creator admin access. A `check` block
fails the plan if the public endpoint is on with an empty allow-list.

Outputs: `cluster_name`, `cluster_endpoint`, `oidc_provider_arn`.

Accepted findings: `AWS-0104` (nodes need egress via NAT to pull images and reach AWS
APIs) in the module; `AWS-0040` (public API endpoint) in dev only.

## Module: `orders-table`

| Input | Type | Default | Description |
|---|---|---|---|
| `table_name` | string | (required) | Table name; also prefixes the role (`<table_name>-app`) |
| `oidc_provider_arn` | string | (required) | `module.eks.oidc_provider_arn` |
| `namespace` | string | (required) | Namespace orders-api runs in |
| `service_account` | string | (required) | ServiceAccount name (= Helm release name) |
| `kms_key_arn` | string | `null` | Customer-managed key; `null` uses the AWS-managed key |
| `deletion_protection` | bool | `true` | Block table deletion |
| `tags` | map(string) | `{}` | Extra tags |

Resources: `aws_dynamodb_table.orders` (hash key `id` string, `PAY_PER_REQUEST`,
point-in-time recovery, SSE), `aws_iam_role.app` (trust: OIDC provider, exact `sub` and
`aud`), `aws_iam_role_policy.table` (`GetItem`, `PutItem`, `Scan` on the table ARN; KMS
decrypt/generate only when a CMK is given).

Outputs: `table_name`, `table_arn`, `role_arn`. Accepted finding: `AWS-0025`
(customer-managed key); pass `kms_key_arn` to use one.

## Environment roots

### Variables

| Variable | dev default | prod default | Notes |
|---|---|---|---|
| `region` | `us-east-1` | `us-east-1` | |
| `vpc_cidr` | `10.10.0.0/16` | `10.20.0.0/16` | |
| `cluster_version` | `1.31` | `1.31` | |
| `api_allowed_cidrs` | **required** | (n/a) | dev only; specific CIDRs, `0.0.0.0/0` rejected |
| `orders_api_namespace` | `orders-api` | `orders-api` | Must match `helm -n` |
| `orders_api_release` | `orders-api` | `orders-api` | Must match the Helm release name |

### Outputs

| Output | Used for |
|---|---|
| `cluster_name` | Reference |
| `kubeconfig_command` | `aws eks update-kubeconfig …` to configure kubectl |
| `orders_table_name` | Chart `ordersTable.name` (dev passes it with `--set`; prod has it in `values-prod.yaml`) |
| `orders_api_role_arn` | Chart ServiceAccount annotation `eks.amazonaws.com/role-arn` |

### State

`backend.tf` stores state in S3 (`platform/<env>/terraform.tfstate`, encrypted) with a
DynamoDB lock table. The bucket and table names are **placeholders**
(`REPLACE-ME-tfstate`, `REPLACE-ME-tflock`); create them once and replace the names
([deployment guide](deployment.md#1-bootstrap-terraform-state)).

## Validate locally

```bash
terraform fmt -recursive terraform/
terraform -chdir=terraform/envs/dev init -backend=false
terraform -chdir=terraform/envs/dev validate
trivy config --skip-dirs '**/.terraform' terraform/
```

`-backend=false` lets you validate without AWS credentials. `make tf-check` runs the
first three for dev; CI runs them for dev and prod.

## Changing infrastructure safely

1. Load the `terraform-module` skill (Claude Code does this automatically for Terraform work).
2. Change dev first; validate and scan as above.
3. Ask the `iac-reviewer` subagent for blast radius and cost.
4. Open a PR. For prod, attach `terraform plan` output.
5. A human runs `terraform apply`. The agent is blocked from doing so.

Flag in review any plan that **replaces or destroys** a stateful resource: the EKS
cluster, the node group launch template, or the orders table.
