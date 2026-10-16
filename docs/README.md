# Documentation

Complete documentation for **agentic-devops-platform**: an AWS platform (VPC, EKS,
DynamoDB) running the `orders-api` service, plus a Claude Code setup that does the
engineering work behind code-enforced guardrails.

| Document | Read it when you want to… |
|---|---|
| [Architecture](architecture.md) | Understand the whole system, how a request flows, and why it is built this way |
| [orders-api reference](api.md) | Call the API, or change the service |
| [Infrastructure](infrastructure.md) | Understand or change the Terraform (VPC, EKS, DynamoDB, IAM) |
| [Deployment guide](deployment.md) | Stand the platform up in AWS and deploy the app, from an empty account |
| [CI/CD](ci-cd.md) | Know what runs on every PR and how to reproduce it locally |
| [Claude Code setup](claude-code.md) | Understand the agent: guardrails, skills, subagents, commands, plugin |
| [Operations runbook](operations.md) | Check health, troubleshoot, roll back, estimate cost, tear down |
| [Development guide](development.md) | Set up a laptop, run tests, follow repo conventions, open a PR |
| [Demo walkthrough](demo-walkthrough.md) | Show the agent and its guardrails in a 10-minute demo |

## The project in one minute

- **orders-api** is a small Flask service: create, list and fetch orders.
- Orders are stored in **DynamoDB**. Pods reach it with **IRSA** (short-lived AWS
  credentials bound to one Kubernetes ServiceAccount): no keys, no passwords.
- It runs on **EKS** in private subnets of a dedicated **VPC**, one cluster per
  environment (`dev`, `prod`), all defined in **Terraform**.
- **Helm** deploys it; `values.yaml` is dev, `values-prod.yaml` is prod.
- **GitHub Actions** runs 6 checks on every PR: tests, Terraform (dev + prod), Helm
  and policy checks, hook tests, and a Trivy security scan.
- **Claude Code** is configured as a platform engineer. Hooks and permissions stop it
  from applying Terraform, deleting resources, reading secrets or editing prod without
  a human.

## Status and known gaps

The code is complete and CI is green, but some pieces a live deployment needs are
not in the repo yet. [deployment.md](deployment.md) shows how to fill each gap.

| Gap | Effect | Workaround |
|---|---|---|
| Terraform state bucket and lock table are placeholders (`REPLACE-ME` in `backend.tf`) | `terraform init` fails until replaced | [Bootstrap state](deployment.md#1-bootstrap-terraform-state) |
| No ECR repository in Terraform; chart points at a placeholder account | Image pull fails | [Create ECR and push the image](deployment.md#3-build-and-push-the-image) |
| CI tests but does not build or push images | Images are built by hand | Same as above |
| No Ingress / AWS Load Balancer Controller; the Service is `ClusterIP` | Not reachable from outside the cluster | `kubectl port-forward` ([operations](operations.md#reach-the-api)) |
| `GET /orders` scans the whole table | Slow and costly at large volume | Add pagination and a GSI before real traffic |
