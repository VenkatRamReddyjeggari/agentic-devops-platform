# CI/CD

Two workflows live in `.github/workflows/`. All jobs run on `ubuntu-24.04` (pinned so
GitHub's `ubuntu-latest` moves don't change the image without a PR).

## `ci.yml`: checks on every change

Triggers: every `pull_request`, and `push` to `main`. Permissions: `contents: read`.

| Job | Steps | Fails when |
|---|---|---|
| **app** | Python 3.12 · `pip install -r app/requirements.txt ruff` · `ruff check app/` · `pytest -q` | Lint errors or any of the 19 tests fail |
| **terraform** (matrix: `dev`, `prod`) | `terraform fmt -check -recursive` · `init -backend=false` · `validate` | Unformatted code or invalid configuration |
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

## Delivery (not automated yet)

CI verifies code but does not build images or deploy. Today:

1. Merge to `main` after CI is green.
2. A human builds and pushes the image tagged with the git SHA
   ([deployment guide §3](deployment.md#3-build-and-push-the-image)).
3. A human runs `helm upgrade` ([§4](deployment.md#4-deploy-orders-api-to-dev)).

The chart is GitOps-ready: an Argo CD `Application` pointing at `charts/orders-api` with
per-environment values is the intended next step, together with a CI job that builds and
pushes the image and bumps `image.tag`.
