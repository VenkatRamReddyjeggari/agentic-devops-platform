---
name: terraform-module
description: Create or modify Terraform modules and environment roots following this repo's conventions. Use when adding AWS infrastructure, writing a new module under terraform/modules, or changing terraform/envs.
---

# Terraform module workflow

## Layout for a new module
```
terraform/modules/<name>/
  main.tf        # resources
  variables.tf   # every variable: description + type (+ validation where useful)
  outputs.tf     # every output: description
  versions.tf    # required_version + required_providers with ~> pins
  README.md      # purpose, inputs, outputs, example
```

## Rules
1. No hardcoded account IDs, regions, ARNs, AMIs or CIDRs inside modules; take them as variables.
2. Prefer well-maintained community modules (`terraform-aws-modules/*`) pinned with `~>`.
3. Tags come from the provider `default_tags` in the env root; modules accept an extra `tags` map.
4. Least-privilege IAM: scope `Resource` to specific ARNs; no `"*"` actions.
5. Encryption on by default (KMS for EKS secrets, S3 SSE, EBS encryption).
6. Wire the module into `terraform/envs/dev` first. Prod only via PR with plan output.

## Verify (definition of done)
```bash
terraform fmt -recursive terraform/
terraform -chdir=terraform/envs/dev init -backend=false
terraform -chdir=terraform/envs/dev validate
trivy config --skip-dirs '**/.terraform' terraform/
```
Never run `apply` or `destroy`. Hooks will block it; ask the human to apply after review.

## Plan summaries
When asked to summarize a plan, group changes as `create / update in-place / replace / destroy`,
call out any `replace` or `destroy` on stateful resources (RDS, EBS, S3, EKS cluster) in bold,
and state the blast radius in one sentence.
