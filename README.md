# Agentic DevOps Platform

**An AWS/EKS platform repo with a guardrailed AI platform engineer built in.**

This repo is two things at once:

1. **A real platform**: Terraform (VPC + EKS), a containerized Python service deployed with Helm, and GitHub Actions CI with security scanning.
2. **A production-style [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) setup** that turns an AI coding agent into a platform engineer that knows the team's conventions, delegates reviews to specialist subagents, connects to GitHub, and **cannot** run destructive commands, because deterministic hooks block them.

The goal: show how to give an AI agent real autonomy on infrastructure **without** giving up safety, the same way you'd onboard a new engineer with runbooks, least privilege, and review gates.

---

## Architecture

```mermaid
flowchart LR
    U([Engineer / @claude in PR]) --> CC

    subgraph KNOW[Know it]
      MD[CLAUDE.md<br/>conventions, commands,<br/>definition of done]
      SK[Skills<br/>k8s-manifest-review<br/>terraform-module<br/>incident-triage]
    end

    subgraph CC[Claude Code: agentic loop]
      direction LR
      G[Gather context] --> A[Take action] --> V[Verify results]
      V -. retry .-> G
    end

    subgraph DO[Do it]
      T[Built-in tools<br/>Read · Edit · Bash · Grep]
      SA[Subagents<br/>security-scanner<br/>iac-reviewer<br/>docs-writer]
      MCP[MCP<br/>GitHub server]
    end

    subgraph CONTROL[Control it]
      H[Hooks<br/>guard-destructive · protect-prod<br/>format-on-edit · session-context · audit-log]
      P[Permissions<br/>allow / ask / deny]
      CMD[Commands<br/>/deploy-check · /drift-check · /postmortem]
      PL[Plugin<br/>platform-ops]
    end

    MD --> CC
    SK --> CC
    CC <--> T
    CC --> SA
    CC <--> MCP
    MCP <--> GH[(GitHub<br/>PRs · Issues · Actions)]
    H -. gates every tool call .-> CC
    P -. gates every tool call .-> CC
    CMD --> CC
    PL -. packages all of the above .-> KNOW

    T --> INFRA
    subgraph INFRA[Platform]
      TF[Terraform<br/>VPC + EKS] --> EKS[(EKS cluster)]
      HELM[Helm chart<br/>orders-api] --> EKS
      EKS -- IRSA --> DDB[(DynamoDB<br/>orders table)]
      CI[GitHub Actions<br/>tests · fmt · kubeconform · trivy]
    end
```

### How each building block is used here

| Building block | File(s) | What it does in this repo |
|---|---|---|
| **Context** | [`CLAUDE.md`](CLAUDE.md) | Repo map, build/test commands, coding standards, hard rules, definition of done |
| **Skills** | [`.claude/skills/`](.claude/skills) | `k8s-manifest-review` (with a runnable policy checker), `terraform-module`, `incident-triage` |
| **Subagents** | [`.claude/agents/`](.claude/agents) | `security-scanner` (read-only, Trivy/Checkov), `iac-reviewer` (blast radius + cost), `docs-writer` (cheap model) |
| **Tools + Permissions** | [`.claude/settings.json`](.claude/settings.json) | Plan/lint/read freely; ask before push or prod edits; deny apply/destroy/delete and secret reads |
| **MCP** | [`.mcp.json`](.mcp.json) | GitHub MCP server for PRs, issues and Actions (token from `$GITHUB_PAT`, never committed) |
| **Hooks** | [`.claude/hooks/`](.claude/hooks) | Block destructive infra commands, require approval for prod edits, auto-format, inject live git context, audit every turn |
| **Commands** | [`.claude/commands/`](.claude/commands) | `/deploy-check <chart> <env>`, `/drift-check <env>`, `/postmortem <incident>` |
| **Plugin** | [`plugin/`](plugin) + [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) | The whole setup packaged so any team can install it in one command |
| **CI agent** | [`.github/workflows/claude.yml`](.github/workflows/claude.yml) | `@claude` in a PR runs the same agent, with the same guardrails, in GitHub Actions |

---

## Guardrails: defense in depth

An agent with shell access to infrastructure needs layered controls. This repo uses three, from soft to hard:

| Layer | Mechanism | Strength | Example |
|---|---|---|---|
| 1. Instructions | `CLAUDE.md`, skills | Advisory (model judgment) | "Never run terraform apply" |
| 2. Permissions | `settings.json` allow/ask/deny | Enforced by the harness | `deny: Bash(terraform apply:*)` |
| 3. Hooks | `PreToolUse` scripts | Enforced, even with `--dangerously-skip-permissions` | `guard-destructive.sh` exits 2 and tells the agent why |

Hooks are tested like any other code ([`tests/test_hooks.sh`](tests/test_hooks.sh)):

```
guard-destructive.sh
  PASS  blocks terraform apply
  PASS  blocks kubectl -n x delete
  PASS  blocks chained apply
  PASS  allows terraform plan
  ...
protect-prod.sh
  PASS  asks for prod tf edit
  PASS  denies .env edit
60 passed, 0 failed
```

Both PreToolUse hooks **fail closed**: if `jq` is missing or the script errors, the tool call is blocked (exit 2) rather than allowed. `protect-prod.sh` also inspects Bash commands, so `sed -i`, `cp` or `>` into `terraform/envs/prod/` or `values-prod.yaml` needs the same human approval as an Edit, and commands that touch `.env`, `*.pem`, `*.key` or `*secret*.tfvars` are denied.

**Limits.** The hooks match patterns; they are not a shell parser. Indirection such as `v=apply; terraform $v` can still get past them, so the last line of defense is credentials: the identity the agent runs as should not have rights to apply Terraform or delete cluster resources.

The Kubernetes policy checker used by the skill also runs in CI, so the agent and the pipeline enforce **the same standard**:

```
CRITICAL | Deployment/bad:web | runAsNonRoot not set
HIGH     | Deployment/bad:web | image not pinned (nginx:latest)
CRITICAL | Deployment/bad:web | privileged container
1 documents checked, 6 HIGH/CRITICAL findings
```

---

## Repository layout

```
.
├── CLAUDE.md                     # agent's project memory
├── .claude/
│   ├── settings.json             # permissions + hook wiring
│   ├── hooks/                    # guardrail + automation scripts
│   ├── skills/                   # on-demand expertise (+ bundled scripts)
│   ├── agents/                   # specialist subagents
│   └── commands/                 # /deploy-check, /drift-check, /postmortem
├── .mcp.json                     # GitHub MCP server
├── plugin/                       # generated plugin package (scripts/build-plugin.sh)
├── .claude-plugin/marketplace.json
├── app/                          # orders-api (Flask) + Dockerfile + tests
├── charts/orders-api/            # Helm chart, dev + prod values
├── terraform/
│   ├── bootstrap/                # once per account: state, ECR, GitHub OIDC role
│   ├── modules/{vpc,eks}/        # wrappers over terraform-aws-modules
│   ├── modules/orders-table/     # DynamoDB table + IRSA role for orders-api
│   └── envs/{dev,prod}/          # env roots, S3 backend, default_tags
├── .github/workflows/            # ci.yml, release.yml, claude.yml
├── tests/test_hooks.sh
└── docs/
```

---

## Documentation

Security reports: see [`SECURITY.md`](SECURITY.md). Full docs live in [`docs/`](docs/README.md): [architecture](docs/architecture.md) · [API](docs/api.md) · [infrastructure](docs/infrastructure.md) · [deployment](docs/deployment.md) · [CI/CD](docs/ci-cd.md) · [Claude Code setup](docs/claude-code.md) · [operations](docs/operations.md) · [development](docs/development.md).

---

## Try it

### Prerequisites
Claude Code, `jq`, Python 3.12, and (for full checks) Terraform ≥ 1.6, Helm 3, kubeconform, Trivy.

```bash
git clone https://github.com/VenkatRamReddyjeggari/agentic-devops-platform && cd agentic-devops-platform
export GITHUB_PAT=<fine-grained token>   # for the GitHub MCP server
make check                               # tests, fmt, validate, lint, policy, hook tests
# dev's public Kubernetes API is restricted to an allow-list; plan with e.g.
#   terraform -chdir=terraform/envs/dev plan -var 'api_allowed_cidrs=["203.0.113.10/32"]'
claude                                   # start the agent in this repo
```

### Deploy to dev (GitOps)
Dev is delivered by Argo CD: a human runs `terraform/bootstrap` once, sets two GitHub
repository variables, and applies `terraform/envs/dev` (which installs Argo CD). From then
on, every merge that touches `app/` builds an image in GitHub Actions, pushes it to ECR
through OIDC (no stored keys) and commits the new tag to the `env/dev` branch; Argo CD
deploys it. Step by step:
[`docs/deployment.md`](docs/deployment.md).

### Demo scenarios
See [`docs/demo-walkthrough.md`](docs/demo-walkthrough.md) for scripted demos:

1. **Guardrail demo**: ask the agent to "apply the prod Terraform" and watch the hook block it and the agent fall back to a plan.
2. **Feature with review**: "Add a PodDisruptionBudget to dev and open a PR". Uses a skill, a subagent and the GitHub MCP server.
3. **Pre-deploy gate**: `/deploy-check orders-api prod`.
4. **Incident triage**: "orders-api pods are CrashLooping in dev" with the read-only triage skill.

### Install the plugin in another repo
```bash
/plugin marketplace add VenkatRamReddyjeggari/agentic-devops-platform
/plugin install platform-ops@agentic-devops
```

---

## Design decisions

- **Hooks over instructions for safety.** Anything that must never happen is enforced in code. Instructions explain *why*; hooks guarantee *that*.
- **Read-only subagents.** Reviewers get `Read, Grep, Glob, Bash` but no `Edit`, so a review can't silently change code. Their context stays isolated, and only the verdict returns to the main session.
- **One policy, two enforcers.** `check-manifests.sh` runs in the skill *and* in CI, so humans and the agent are held to the same bar.
- **Plugin generated, not hand-maintained.** `.claude/` is the source of truth; `scripts/build-plugin.sh` produces `plugin/` and CI fails if it drifts.
- **Secrets never in the repo.** MCP token via env var; hooks deny edits to `.env`, `*.pem`; permissions deny reading them.

- **orders-api stores orders in DynamoDB.** On-demand billing (~$0 idle), point-in-time recovery and deletion protection on. Pods reach it through IRSA (no keys, no passwords), and the role may only `GetItem`/`PutItem`/`Scan` that one table. Pods are stateless, so replicas and gunicorn workers scale freely. Order IDs are UUIDs. `GET /orders` scans the whole table, which is fine at demo scale; add pagination and a GSI on `created_at` before real volume. Locally, tests run against a mocked DynamoDB (moto); point `AWS_ENDPOINT_URL` at DynamoDB Local to run the app by hand.
- **Prod has its own table** (`platform-prod-orders`), set in `values-prod.yaml`. Prod has no GitOps wiring yet and its API is private; deploy it from inside the VPC with `-f charts/orders-api/values-prod.yaml` and the role ARN from `terraform/envs/prod` output `orders_api_role_arn` (the table name is already in the values file). Apply the prod Terraform before deploying the app, or the pods stay not-ready.

## Tech stack
AWS (VPC, EKS, IRSA, DynamoDB, KMS, ECR) · Terraform · Kubernetes · Helm · Docker · Python/Flask · GitHub Actions · Trivy · kubeconform · Claude Code (skills, subagents, hooks, MCP, plugins)

## Author
**Venkat Ram Reddy** · DevOps / Platform Engineer · AWS Certified DevOps Engineer – Professional · CKA

[GitHub](https://github.com/VenkatRamReddyjeggari) · [LinkedIn](https://www.linkedin.com/in/venkatreddyj)
