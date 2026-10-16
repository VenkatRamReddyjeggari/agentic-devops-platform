# Development guide

## Prerequisites

| Tool | Needed for |
|---|---|
| Python **3.12** | App and tests (the code uses `datetime.UTC`, which needs 3.11+) |
| `jq` | Hooks (they block every call without it) |
| Terraform ≥ 1.6, Helm 3, kubeconform | `make check` |
| Trivy, shellcheck, ruff | Security scan, shell lint, Python lint (as in CI) |
| Claude Code | Working with the agent |

## Set up

```bash
git clone https://github.com/VenkatRamReddyjeggari/agentic-devops-platform
cd agentic-devops-platform
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r app/requirements-dev.txt ruff
make check
```

If your system Python is older, run the tests with uv instead:

```bash
pip install uv
cd app && uv run --no-project --python 3.12 --with-requirements requirements-dev.txt pytest -q
```

## Run the app locally

Tests need no AWS: they mock DynamoDB with moto. To run the server by hand, use
DynamoDB Local:

```bash
docker run -d -p 8000:8000 amazon/dynamodb-local
export AWS_ENDPOINT_URL=http://localhost:8000 AWS_REGION=us-east-1 \
       AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local ORDERS_TABLE=orders
aws dynamodb create-table --table-name orders \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH --billing-mode PAY_PER_REQUEST
cd app && python app.py            # http://localhost:8080
```

## Repository map

| Path | Contents |
|---|---|
| `app/` | `app.py`, `test_app.py`, `requirements.txt` (runtime deps, installed in the image), `requirements-dev.txt` (adds pytest and moto), `Dockerfile` |
| `charts/orders-api/` | `Chart.yaml`, `values.yaml` (defaults), `values-prod.yaml` (prod, protected), `templates/`. Dev's image tag is on the `env/dev` branch, written by CI |
| `terraform/` | `bootstrap/` (once per account), `modules/{vpc,eks,orders-table}`, `envs/{dev,prod}` (dev includes `argocd.tf`) |
| `.github/workflows/` | `ci.yml`, `release.yml`, `claude.yml` |
| `.claude/` | Agent config: `settings.json`, `hooks/`, `skills/`, `agents/`, `commands/` |
| `plugin/` | Generated from `.claude/` by `make plugin`; never edit by hand |
| `scripts/build-plugin.sh` | Plugin generator |
| `tests/test_hooks.sh` | Hook behavior tests |
| `scripts/smoke-test.sh` | Starts the app with the Dockerfile's server command and checks it answers |
| `docs/` | This documentation |

Chart templates: `deployment.yaml` (Deployment), `service.yaml` (Service),
`serviceaccount.yaml` (ServiceAccount with the IRSA annotation), `hpa-pdb.yaml`
(HPA and PDB, when enabled), `_helpers.tpl` (names and labels).

## Chart values

| Key | Default | Meaning |
|---|---|---|
| `replicaCount` | `1` | Replicas when the HPA is off |
| `image.repository` / `image.tag` | placeholder / `"0.1.0"` | Set at deploy; tags are git SHAs, never `latest` |
| `serviceAccount.create` | `true` | Create the ServiceAccount |
| `serviceAccount.annotations` | `{}` | Set `eks.amazonaws.com/role-arn` at deploy |
| `ordersTable.name` | `""` | DynamoDB table; empty keeps pods not-ready |
| `ordersTable.region` | `""` | Optional `AWS_REGION` override |
| `service.type` / `port` / `targetPort` | `ClusterIP` / `80` / `8080` | |
| `resources` | 100m/128Mi → 500m/256Mi | Requests → limits |
| `autoscaling.*` | off; 2–6 at 70 % | HPA (prod: on, 3–12 at 65 %) |
| `podDisruptionBudget.*` | off; `minAvailable: 1` | PDB (prod: on, 2) |
| `env` | `APP_VERSION: "0.1.0"` | Extra environment variables |

## Coding standards

From `CLAUDE.md`:

- **Terraform:** described and typed variables; no hardcoded IDs, regions or ARNs;
  `~>` pins; tags via `default_tags`.
- **Kubernetes:** requests and limits, liveness and readiness probes, `runAsNonRoot`,
  `readOnlyRootFilesystem`.
- **Images:** never `:latest`; tags come from the git SHA.
- **Python:** type hints, `ruff` clean, tests for every endpoint.
- **Bash:** `set -euo pipefail`, shellcheck clean.

## Making a change

1. Branch from `main`: `<type>/<short-name>` (for example `feat/order-status`).
2. Change code with tests. If you edit `.claude/`, run `make plugin` and commit `plugin/` too.
3. Run `make check`, plus the extra CI steps in [CI/CD](ci-cd.md#reproduce-ci-locally)
   if you touched prod files, shell scripts or the chart.
4. Commit as `<type>(<scope>): <summary>`, for example `feat(chart): add HPA`.
   Types: `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`, `test`.
5. Push and open a PR. Prod changes include `terraform plan` output.
6. Merge when CI is green and the PR is reviewed. `main` accepts changes only through
   pull requests with passing checks ([repository security](repository-security.md)).

### Definition of done

1. `make check` passes.
2. Trivy reports no HIGH/CRITICAL findings, or they are documented in the PR.
3. Docs are updated (`README.md` or `docs/`) when behavior changes.
4. The commit message follows the format above.

## Adding an endpoint

1. Add the route in `app/app.py`; put data access on `OrderStore`.
2. If it needs new DynamoDB actions, add them to the role policy in
   `terraform/modules/orders-table/main.tf`, scoped to the table, and apply.
3. Add tests in `app/test_app.py` (the `client` fixture gives a mocked table).
4. Document it in [api.md](api.md).
