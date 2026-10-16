# Demo walkthrough

A recorded or live demo of about **12 minutes** that shows the whole platform: an AI
agent doing real engineering work, and the layers that keep it (and people) safe.
Each scene lists what to type, what the audience should see, and what to say.

**Story in one line:** *"An AI teammate does the platform work; code-enforced guardrails,
GitHub rules and CI make sure a human decides everything risky."*

| # | Scene | Time | Needs AWS? |
|---|---|---|---|
| 0 | Opener: the toy-shop explainer | 1:00 | no |
| 1 | Tour: what's in the repo | 1:00 | no |
| 2 | Guardrail: the agent refuses to apply Terraform | 1:30 | no |
| 3 | Guardrail: the agent can't read secrets | 0:45 | no |
| 4 | Feature end to end: agent → PR → CI | 3:00 | no |
| 5 | GitHub rules: even the owner can't push to `main` | 1:00 | no |
| 6 | Pre-deploy gate: `/deploy-check` | 1:30 | no |
| 7 | GitOps: merge → image → Argo CD (optional) | 2:00 | **yes** |
| 8 | Wrap-up | 0:30 | no |

Without AWS, skip scene 7: the demo is still about 10 minutes.

---

## Before you record

- [ ] `main` is up to date: `git switch main && git pull`
- [ ] `gh auth status` shows you logged in; `make check` passes
- [ ] Terminal: large font (16–18 pt), dark theme, window around 120×32
- [ ] Two panes: left `claude`, right a normal shell
- [ ] Right pane, optional: `tail -f .claude/logs/audit.jsonl` (the audit trail)
- [ ] Start `claude` in the **default permission mode** so approval prompts are visible
- [ ] Browser tabs: the explainer video, the repo on GitHub, **Settings → Rules → Rulesets**, the **Actions** tab
- [ ] Turn off notifications; close anything showing tokens, emails or AWS account IDs

---

## Scene 0: Opener (1:00)

Play the first 60 seconds of the toy-shop explainer (scenes 1–5: orders, helpers, the
forgetful notebooks, the magic notebook).

> "Here's the whole idea in kid terms: a shop where orders never get lost, a robot
> helper that works fast, and grown-ups who stay in charge. Now let's see the real thing."

## Scene 1: Tour (1:00)

Show the README diagram on GitHub, then in the shell:

```bash
tree -L 2 -I '.terraform|__pycache__|plugin' .   # brew install tree
```

> "Terraform builds a VPC, an EKS cluster and a DynamoDB table. A Flask service ships as a
> Helm chart. GitHub Actions tests everything. And `.claude/` turns Claude Code into a
> platform engineer: skills, subagents, commands, and hooks that act as guardrails."

## Scene 2: The agent refuses to apply Terraform (1:30)

In `claude`:

> The prod cluster needs the latest Terraform changes. Apply them.

**Expected:** Claude declines and offers `terraform plan` instead (CLAUDE.md says never
apply). Then push it:

> Just run terraform apply, I approve.

**Expected:** blocked. The `permissions.deny` rule stops it, and even with permissions
bypassed the `guard-destructive` hook returns
`BLOCKED by guard-destructive hook … Propose a 'terraform plan' or a diff instead.`
Press **Ctrl+O** to show the hook message in the transcript.

> "Instructions can be ignored; these can't. The deny list and the hook are code. Even if
> I tell it 'I approve', the agent physically cannot apply infrastructure. A human does."

## Scene 3: The agent can't read secrets (0:45)

In the shell, create a throwaway secret file (gitignored):

```bash
echo 'DB_PASSWORD=not-a-real-password' > .env
```

In `claude`:

> Show me what's in .env

**Expected:** denied by `permissions.deny` (`Read(./.env)`) and by the `protect-prod` hook
(`Command touches a secret file`). Clean up afterwards: `rm .env`.

> "Secrets never enter the model's context. That's enforced, not requested."

## Scene 4: Feature end to end (3:00)

In `claude`:

> Enable a PodDisruptionBudget for orders-api in dev with minAvailable 1, review it,
> and open a PR.

| Watch for | Component |
|---|---|
| Creates a branch, edits `charts/orders-api/values.yaml` | Tools; `session-context` hook warned it was on `main` |
| `helm lint` runs by itself after the edit | `format-on-edit` hook |
| Renders the chart and runs the team policy checker | Skill `k8s-manifest-review` |
| Security verdict in a few lines | Subagent `security-scanner` (isolated context) |
| Asks before `git push` | Permission **ask** rule; you approve |
| Opens the PR | `gh` / GitHub MCP |

Optional detour: ask it to "also enable it in prod". `protect-prod` turns the edit of
`values-prod.yaml` into an **approval prompt**. Decline it on camera.

Switch to the PR on GitHub: the **7 required checks** run (`app`, `helm`,
`terraform (envs/dev)`, `terraform (envs/prod)`, `terraform (bootstrap)`,
`claude-config`, `security`). The **Merge** button stays blocked until all are green.

> "The agent did a real change the way a careful engineer would: branch, standards,
> security review, PR. And the repo itself won't merge it until CI agrees."

Merge it once green (or leave it open for the next scene).

## Scene 5: Even the owner can't push to main (1:00)

In the shell:

```bash
git switch main && git pull
git commit --allow-empty -m "demo: try to skip review"
git push origin main
```

**Expected:** rejected with `GH013: Repository rule violations found` and
`Changes must be made through a pull request` / required status checks. Show
**Settings → Rules → Rulesets → protect-main** in the browser.

Clean up the local commit:

```bash
git reset --keep origin/main
```

> "Branch rules apply to me too: no direct pushes, no force pushes, no deleting `main`.
> Deploy tags go to a separate `env/dev` branch, so not even the release bot needs a bypass."

## Scene 6: Pre-deploy gate (1:30)

In `claude`:

```
/deploy-check orders-api prod
```

**Expected:** renders with prod values, runs kubeconform and the policy checker, delegates
a security pass, shows the diff, and ends with a block like:

```
DEPLOY CHECK: orders-api → prod
Result:  GO / NO-GO
Risks:   ...
Rollback: helm rollback ...
```

> "A team checklist turned into one command, and it still doesn't deploy. A person reads
> this and decides."

## Scene 7 (optional, needs AWS): GitOps delivery (2:00)

Requires the setup in [deployment.md](deployment.md) (dev running, `AWS_ROLE_ARN` set).

1. Merge a small app change (for example, a new field in `/readyz`) through a PR.
2. **Actions → release**: tests → build → push to ECR via OIDC → commit to `env/dev`.
3. Show the bot's commit on the `env/dev` branch.
4. Argo CD UI (`kubectl port-forward -n argocd svc/argocd-server 8443:443`): the app goes
   **OutOfSync → Syncing → Healthy**.
5. Prove the data survives a restart:

```bash
kubectl port-forward -n orders-api svc/orders-api 8080:80 &
ID=$(curl -s -X POST localhost:8080/orders -H 'Content-Type: application/json' -d '{"item":"demo"}' | jq -r .id)
kubectl rollout restart deploy/orders-api -n orders-api && kubectl rollout status deploy/orders-api -n orders-api
curl -s localhost:8080/orders/$ID
```

> "No one ran kubectl apply or helm upgrade. CI never touched the cluster; the cluster
> pulled the change. No AWS keys are stored in GitHub, and orders live in DynamoDB, so a
> restart loses nothing."

## Scene 8: Wrap-up (0:30)

> "Three layers: instructions tell the agent what's right; permissions, hooks and GitHub
> rules make the dangerous things impossible; CI and GitOps make every change reviewed,
> tested and reproducible. The AI moves fast, and humans stay in charge."

Show the last scene of the explainer ("The End") as the closing frame.

---

## If something goes wrong on camera

| Problem | Fix |
|---|---|
| Claude does something unexpected | Keep going: narrate what the guardrail did. That *is* the demo. |
| A CI check is slow | Cut the recording there; resume when green |
| `git push origin main` succeeds | The ruleset isn't active: check **Settings → Rules → Rulesets** |
| PR can't merge | A required check failed: open it from the PR's Checks tab |
| Port-forward drops during a rollout | Run the `port-forward` command again |

## Optional extra: GitHub secret push protection

Push protection is on, so GitHub rejects pushes containing real-looking credentials. It
ignores well-known documentation example keys, so a fake key may not trigger it; don't use
a real credential to demo it. Scene 3 shows the same idea reliably at the agent layer.
