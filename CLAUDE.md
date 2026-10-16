# Agentic DevOps Platform

AWS platform repo: Terraform (VPC + EKS), a Helm-deployed Python service (`orders-api`),
and GitHub Actions CI. Claude Code is configured as a platform-engineering agent with
skills, subagents, hooks, commands and MCP. Architecture diagram: `README.md`.

## Repository structure
- `app/` – orders-api (Flask) + Dockerfile + pytest tests
- `charts/orders-api/` – Helm chart (`values.yaml` = dev, `values-prod.yaml` = prod)
- `terraform/modules/` – reusable modules (`vpc`, `eks`)
- `terraform/bootstrap/` – once-per-account state bucket, ECR, GitHub OIDC CI role (local state)
- `terraform/envs/dev|prod/` – environment roots (remote state, per-env tfvars); dev installs Argo CD
- Branch `env/dev` (file `orders-api/values-dev.yaml`) – dev image tag, written by `release.yml`; Argo CD deploys it. Never edit by hand; `main` is protected and takes PRs only
- `.github/workflows/` – CI (`ci.yml`), image release (`release.yml`) and the `@claude` PR assistant (`claude.yml`)
- `.claude/` – Claude Code config: skills, agents, commands, hooks, settings
- `plugin/` – the same Claude Code setup packaged as an installable plugin

## Build & test commands
- App tests: `cd app && pip install -r requirements-dev.txt && pytest -q`
- Terraform: `terraform -chdir=terraform/envs/dev init -backend=false && terraform -chdir=terraform/envs/dev validate`
- Format: `terraform fmt -recursive terraform/`
- Helm: `helm lint charts/orders-api && helm template charts/orders-api | kubeconform -strict -summary`
- Security: `trivy config --skip-dirs '**/.terraform' terraform/`, `trivy config charts/` and `trivy fs app/` (trivy config takes one directory per run)
- Everything at once: `make check`

## Coding standards
- Terraform: every variable has `description` and `type`; no hardcoded account IDs, regions or ARNs
- Terraform: pin provider and module versions (`~>`); tag all resources via `default_tags`
- Kubernetes: requests/limits, liveness/readiness probes, `runAsNonRoot`, `readOnlyRootFilesystem`
- Images: never `:latest`; tags come from CI (`git sha`)
- Python: type hints, `ruff` clean, tests for every endpoint
- Bash: `set -euo pipefail`, shellcheck clean

## Architecture decisions
- One EKS cluster per environment; workloads deployed by Helm (GitOps-ready for Argo CD)
- Private subnets for nodes, public subnets only for load balancers
- IRSA for pod-level AWS access; no node-level IAM for apps
- State in S3 with DynamoDB locking (configured per env in `backend.tf`)

## Hard rules (also enforced by hooks + permissions)
- NEVER run `terraform apply`, `terraform destroy`, `kubectl delete`, or `helm uninstall`
- NEVER edit `terraform/envs/prod/**` or `charts/**/values-prod.yaml` without explicit approval
- NEVER read or print `.env`, `*.pem`, `*.tfvars` containing secrets
- Prod changes go through a PR; `terraform plan` output is attached to the PR

## Definition of done
1. `make check` passes (tests, server smoke test, fmt, validate, lint, kubeconform)
2. `trivy` reports no HIGH/CRITICAL findings (or they are documented in the PR)
3. Docs updated (`README.md` or `docs/`) when behavior changes
4. Commit message: `<type>(<scope>): <summary>` e.g. `feat(chart): add HPA`
