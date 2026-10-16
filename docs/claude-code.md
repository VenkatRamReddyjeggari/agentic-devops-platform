# Claude Code setup

Claude Code is configured as a platform engineer for this repo. It can read the whole
codebase, write Terraform, charts and Python, run checks, and open PRs. Anything that
touches real infrastructure, production config or secrets is blocked or needs a human.

## Layers of control

| Layer | File | Enforced? | Role |
|---|---|---|---|
| 1. Instructions | `CLAUDE.md` | No (guidance) | Repo map, commands, standards, hard rules, definition of done |
| 2. Permissions | `.claude/settings.json` | Yes (by Claude Code) | Allow / ask / deny lists per tool and command |
| 3. Hooks | `.claude/hooks/*.sh` | Yes (scripts run on every tool call) | Block destructive commands; gate prod and secrets, even with permissions bypassed |
| 4. Credentials | your AWS / Kubernetes setup | Yes (by AWS / Kubernetes) | The agent's credentials should not allow destructive actions either |

Only layers 2–4 are guarantees. The hooks exist because permissions can be bypassed
(`--dangerously-skip-permissions`), and layer 4 exists because hooks are pattern matching.

## Permissions (`.claude/settings.json`)

| List | Entries |
|---|---|
| **allow** (no prompt) | `terraform fmt/validate/plan`, `terraform init -backend=false`, `helm lint/template`, `kubeconform`, `kubectl get/describe/logs`, `trivy`, `pytest`, `make check`, `git status/diff/log` |
| **ask** (human approves) | `git push`, `docker push`, edits under `terraform/envs/prod/**`, edits to `charts/**/values-prod.yaml` |
| **deny** | `terraform apply/destroy`, `kubectl delete`, `helm uninstall`, reading `.env*`, `*.pem`, `*.key`, `*secret*.tfvars` |

## Hooks

| Hook | Event | What it does |
|---|---|---|
| `session-context.sh` | SessionStart | Injects branch, uncommitted file count and last 5 commits; warns if on `main` |
| `guard-destructive.sh` | PreToolUse (Bash) | Blocks destructive commands (exit 2) and tells the agent to propose a plan or diff instead |
| `protect-prod.sh` | PreToolUse (Edit, Write, NotebookEdit, Bash) | **Ask** for prod paths; **deny** secret files |
| `format-on-edit.sh` | PostToolUse (Edit, Write) | `terraform fmt`, `ruff format` + `ruff check --fix`, `shellcheck`, or `helm lint` on the edited file |
| `audit-log.sh` | Stop | Appends `{ts, user, branch, session, event}` to `.claude/logs/audit.jsonl` (gitignored) |

### `guard-destructive.sh` blocks

| Area | Blocked |
|---|---|
| Terraform | `apply`, `destroy`, `import`, `taint`, `force-unlock`; `state rm/mv/push/replace-provider` |
| Kubernetes | `kubectl delete`, `kubectl drain`, `kubectl scale … --replicas 0` |
| Helm | `helm uninstall`, `helm delete` |
| AWS CLI | any `delete-*`, `terminate-*`, `deregister-*`; `s3 rm`, `s3 rb`, `s3 sync --delete` |
| Files | recursive `rm` of `/`, `~`, `$HOME`, `.`, `..`, `*`, or a top-level repo directory |
| Git | `push --force` / `-f` / `+refspec`; `reset --hard`; `clean -f` |

Up to 4 flags may sit between the tool and the verb (`terraform -chdir=… apply` is caught).
Matching stays within one command segment, so prose and heredocs rarely trigger it, but
it can: a PR description that *mentions* a blocked command is blocked too. Write such
text to a file first.

### `protect-prod.sh`

- **Edit/Write** to `terraform/envs/prod/*` or `*values-prod.yaml` → **ask**.
- **Bash** commands that mention a prod path and write (`sed -i`, `perl -i`, `tee`, `cp`,
  `mv`, `rm`, `ln`, `dd`, `patch`, `git checkout/restore/apply/rm/mv`, or a `>` redirect
  not into `/dev` or a temp dir) → **ask**. Read-only commands such as
  `terraform -chdir=terraform/envs/prod plan > /tmp/plan.txt` pass.
- Any tool touching `.env`, `.env.*`, `*.pem`, `*.key` or `*secret*.tfvars` → **deny**.

Both guard hooks **fail closed**: a missing `jq` or any internal error blocks the call.

### Limits

Hooks match patterns; they do not parse shell. Indirection (`v=apply; terraform $v`,
`bash -c "$(…)"`) can get past them. That is why the agent's AWS and Kubernetes
credentials should be read-only or plan-only, and why `terraform apply` belongs to a
human or a CI pipeline with its own approvals.

### Tests

`tests/test_hooks.sh` feeds each hook the same JSON Claude Code sends and asserts the
exit code or decision: 60 cases, including fail-closed behavior without `jq` and
false-positive checks. Run `make hooks-test`.

## Skills (`.claude/skills/`)

Loaded on demand when a task matches their description.

| Skill | Use | Highlights |
|---|---|---|
| `terraform-module` | Adding or changing Terraform | Module layout, rules, verify steps, plan-summary format (create / update / **replace** / **destroy**) |
| `k8s-manifest-review` | Editing charts or Kubernetes YAML | Render, run `check-manifests.sh`, kubeconform, Trivy, checklist; verdict APPROVE / APPROVE WITH FIXES / BLOCK |
| `incident-triage` | Outages, crashing pods, alerts | Read-only `kubectl`, symptom → cause table, SEV report; mitigations proposed, never run |

## Subagents (`.claude/agents/`)

Run in their own context and return only a verdict, keeping the main session small.

| Agent | Model | Tools | Returns |
|---|---|---|---|
| `security-scanner` | sonnet | Read, Grep, Glob, Bash (no edit) | Findings table + PASS / PASS WITH WARNINGS / FAIL |
| `iac-reviewer` | sonnet | Read, Grep, Glob, Bash (no edit) | Summary, issues table, blast radius, cost delta, APPROVE / REQUEST CHANGES |
| `docs-writer` | haiku | Read, Grep, Glob, Edit, Write | Updated docs + list of files changed |

## Commands (`.claude/commands/`)

| Command | Does |
|---|---|
| `/deploy-check <chart> [dev\|prod]` | Lint, render, kubeconform, policy review, security subagent, diff vs `main`; prints GO / NO-GO and the rollback command. Never deploys. |
| `/drift-check [dev\|prod]` | `terraform plan -detailed-exitcode`; explains drift in plain language. Never applies. |
| `/postmortem <incident>` | Drafts a blameless postmortem in `docs/postmortems/<date>-<slug>.md` |

## MCP (`.mcp.json`)

The GitHub MCP server (`https://api.githubcopilot.com/mcp/`) lets the agent read issues
and open PRs. It authenticates with `Authorization: Bearer ${GITHUB_PAT}`; export a
fine-grained token as `GITHUB_PAT` before starting `claude`. The token is never stored
in the repo.

## Plugin

`scripts/build-plugin.sh` (`make plugin`) copies skills, agents, commands, hooks and
`.mcp.json` into `plugin/`, and rewrites hook paths to `${CLAUDE_PLUGIN_ROOT}`.
`.claude/` is the source of truth; CI fails if `plugin/` drifts. Install elsewhere with:

```
/plugin marketplace add VenkatRamReddyjeggari/agentic-devops-platform
/plugin install platform-ops@agentic-devops
```

## Typical workflow with the agent

1. Ask for a change ("add a PodDisruptionBudget to dev").
2. The agent reads `CLAUDE.md` and the session context, loads the matching skill, and
   edits on a feature branch; formatting runs automatically.
3. It validates (`make check`), asks `security-scanner` / `iac-reviewer` for a verdict, and
   pushes (you approve the push) and opens a PR.
4. CI runs; you review and merge.
5. You apply infrastructure and deploy. The agent can run `/deploy-check` first.
