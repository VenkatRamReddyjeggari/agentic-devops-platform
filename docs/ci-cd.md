# CI/CD

Three workflows live in `.github/workflows/`. All jobs run on `ubuntu-24.04` (pinned so
GitHub's `ubuntu-latest` moves don't change the image without a PR).

## `ci.yml`: checks on every change

Triggers: every `pull_request`, and `push` to `main`. Permissions: `contents: read`.

| Job | Steps | Fails when |
|---|---|---|
| **app** | Python 3.12 · `pip install -r app/requirements.txt ruff` · `ruff check app/` · `pytest -q` | Lint errors or any of the 19 tests fail |
| **terraform** (matrix: `envs/dev`, `envs/prod`, `bootstrap`) | `terraform fmt -check -recursive` · `init -backend=false` · `validate` | Unformatted code or invalid configuration |
| **helm** | `helm lint` · render dev and prod · `kubeconform -strict` · `check-manifests.sh` on both renders | Lint errors, schema errors, or HIGH/CRITICAL policy findings |
| **claude-config** | `shellcheck` on hooks and scripts · `tests/test_hooks.sh` (60 cases) · rebuild plugin and `git diff --exit-code plugin/` | Shell issues, a hook regression, or `plugin/` out of sync with `.claude/` |
| **security** | Trivy `config` scan of the repo (`skip-dirs: **/.terraform`), HIGH/CRITICAL, exit code 1 | Any unaccepted HIGH/CRITICAL misconfiguration |

`aquasecurity/trivy-action` is pinned to a commit SHA (v0.36.0): tags can be moved or
deleted, a SHA cannot.

### Team policy checks (`check-manifests.sh`)

The same script runs in CI and in the `k8s-manifest-review` skill, so people and the agent
are held to the same rules.

| Severity | Rule |
|---|---|
| CRITICAL | `runAsNonRoot` not set; privileged container |
| HIGH | Image not pinned or `:latest`; missing `resources.requests` or `limits`; `allowPrivilegeEscalation` not false; the same kind and name rendered twice |
| MEDIUM | Missing readiness/liveness probe; `readOnlyRootFilesystem` not true |

Any HIGH or CRITICAL finding fails the job.

## `release.yml`: build, push, hand to Argo CD

Triggers: pushes to `main` that touch `app/**`, and manual **Run workflow**. Skips itself
until the `AWS_ROLE_ARN` repository variable is set. One release runs at a time.

| Job | Steps |
|---|---|
| **build-push** | Checkout · run the tests · assume `AWS_ROLE_ARN` via GitHub OIDC (`id-token: write`, no stored keys) · ECR login · `docker buildx` for `linux/amd64` · push `orders-api:<first 12 chars of the git SHA>` (the repository's tags are immutable) |
| **bump-dev** | Check out the `env/dev` branch (created as an empty orphan branch on the first run) · write `orders-api/values-dev.yaml` with `image.tag` and `env.APP_VERSION` set to that tag · commit as `github-actions[bot]` (`chore(release): deploy orders-api <tag> to dev`) · push to `env/dev` (3 attempts) |

The tag lives on `env/dev`, not `main`, so `main` can require pull requests with no bypass
for bots ([repository security](repository-security.md)). Pushes made with `GITHUB_TOKEN`
do not trigger other workflows, so the bump commit cannot loop. Argo CD picks it up and deploys. Third-party actions here are pinned by commit SHA.

| Repository variable | Required | Value |
|---|---|---|
| `AWS_ROLE_ARN` | yes | `terraform/bootstrap` output `ci_role_arn` |
| `AWS_REGION` | no | defaults to `us-east-1` |
| `ECR_REPOSITORY` | no | defaults to `orders-api` |

## `claude.yml`: the `@claude` assistant

Comment `@claude <request>` on an issue, PR or PR review. The workflow runs
`anthropics/claude-code-action@v1` with this repo checked out, so it loads `CLAUDE.md`,
skills, subagents and hooks: the same guardrails as on a laptop.

Setup: add an `ANTHROPIC_API_KEY` repository secret. Permissions granted: write to
contents, pull requests and issues (to push commits and comment), and `id-token: write`.

## Reproduce CI locally

```bash
make check          # test + tf-check (dev) + helm-check (dev) + hooks-test
```

| Make target | Runs |
|---|---|
| `make test` | `cd app && pytest -q` |
| `make tf-check` | `terraform fmt -check`, `init -backend=false`, `validate` (dev) |
| `make helm-check` | `helm lint`, render dev, `kubeconform`, `check-manifests.sh` |
| `make hooks-test` | `bash tests/test_hooks.sh` |
| `make plugin` | Rebuild `plugin/` from `.claude/` |

Not covered by `make check` (run them yourself to match CI fully):

```bash
ruff check app/
terraform -chdir=terraform/envs/prod init -backend=false && terraform -chdir=terraform/envs/prod validate
helm template orders-api charts/orders-api -f charts/orders-api/values-prod.yaml > /tmp/prod.yaml \
  && kubeconform -strict -summary /tmp/prod.yaml \
  && bash .claude/skills/k8s-manifest-review/scripts/check-manifests.sh /tmp/prod.yaml
shellcheck .claude/hooks/*.sh .claude/skills/*/scripts/*.sh scripts/*.sh
bash scripts/build-plugin.sh && git diff --exit-code plugin/
trivy config --skip-dirs '**/.terraform' .
```

## Delivery

Dev is delivered by GitOps: merge → `release.yml` builds, pushes and bumps the tag →
Argo CD syncs ([deployment guide](deployment.md#everyday-flow)). Prod has no automated
delivery yet ([deployment guide](deployment.md#production)).
