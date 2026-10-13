# Demo walkthrough

Four scripted demos that exercise every building block. Good for a screen recording,
a live interview demo, or a blog post. Each lists the prompt, what to watch for,
and which component is responsible.

---

## Demo 1: Guardrails (2 min)

**Prompt**
> The prod cluster needs the latest Terraform changes. Apply them.

**What happens**
1. `SessionStart` hook has already injected the branch and recent commits.
2. Claude reads `CLAUDE.md`, sees "never run terraform apply", and proposes a plan instead.
3. If pushed ("just run it"), the Bash call hits `permissions.deny`; even with permissions
   bypassed, `guard-destructive.sh` exits 2 and returns:
   `BLOCKED by guard-destructive hook ... Propose a 'terraform plan' or a diff instead.`
4. Claude runs `terraform plan` (allowed) and summarizes it using the `terraform-module` skill.

**Talking point:** three layers (instructions, permissions, hooks), and only the last two are guarantees.

---

## Demo 2: Feature end to end (5 min)

**Prompt**
> Enable a PodDisruptionBudget for orders-api in dev, review it, and open a PR.

**What happens**
| Step | Component |
|---|---|
| Reads chart and values | Tools (Read, Grep) |
| Applies team K8s standards | Skill `k8s-manifest-review` (loaded on demand) |
| Edits `values.yaml` | Tool (Edit); `format-on-edit` hook runs helm lint |
| Tries to edit `values-prod.yaml` too | `protect-prod` hook returns **ask**; you approve or decline |
| Security pass | Subagent `security-scanner` (isolated context, returns a verdict only) |
| Creates branch + PR | MCP GitHub server |
| Turn ends | `audit-log` hook writes `.claude/logs/audit.jsonl` |

---

## Demo 3: Pre-deploy gate (2 min)

```
/deploy-check orders-api prod
```
Renders with prod values, validates schemas, runs the policy checker, delegates a
security scan, and prints a GO/NO-GO block with the exact rollback command.

**Talking point:** commands turn a team checklist into a one-liner anyone can run.

---

## Demo 4: Incident triage (3 min)

Break dev on purpose (for example, set an invalid image tag), then:

> orders-api pods are CrashLooping in dev. What's wrong?

The `incident-triage` skill restricts Claude to read-only `kubectl` commands, classifies
the failure (ImagePullBackOff), and proposes `helm rollback` for a human to run.
Follow with `/postmortem` to draft a blameless write-up.

---

## Recording tips
- Run `claude` with the default permission mode so viewers see approval prompts.
- Press `Ctrl+O` to show the transcript view when a hook blocks something.
- Keep `tail -f .claude/logs/audit.jsonl` in a split pane.
