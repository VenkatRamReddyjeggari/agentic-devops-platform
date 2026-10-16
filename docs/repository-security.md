# Repository security settings

The repository is **public**. Files in the repo (`SECURITY.md`, `.github/CODEOWNERS`,
`.github/dependabot.yml`, the `@claude` author check, the `env/dev` deploy branch) only
work together with these GitHub settings, which a repository admin applies by hand.

## 1. Ruleset for `main`

**Settings → Rules → Rulesets → New ruleset → New branch ruleset**

| Field | Value |
|---|---|
| Name | `protect-main` |
| Enforcement status | Active |
| Bypass list | *empty*: nothing, including bots, may bypass |
| Target branches | Include default branch |

Rules to turn on:

| Rule | Setting |
|---|---|
| Restrict deletions | on |
| Block force pushes | on |
| Require linear history | optional (on if you prefer squash/rebase merges) |
| Require a pull request before merging | on; **Required approvals: 0** while you are the only maintainer (you cannot approve your own PR); "Require review from Code Owners" off until there is a second maintainer |
| Require status checks to pass | on; "Require branches to be up to date" on; add `app`, `helm`, `terraform (envs/dev)`, `terraform (envs/prod)`, `terraform (bootstrap)`, `claude-config`, `security` |

Status checks only appear in the picker after they have run once on the repository.

## 2. Ruleset for deploy branches

The release workflow writes the dev image tag to `env/dev` with normal (non-force) pushes.

| Field | Value |
|---|---|
| Name | `protect-env-branches` |
| Bypass list | empty |
| Target branches | Include by pattern: `env/*` |
| Rules | Restrict deletions: on · Block force pushes: on · nothing else (CI must be able to push) |

## 3. Code security

**Settings → Advanced Security** (or **Code security**):

| Feature | Setting |
|---|---|
| Private vulnerability reporting | Enable (used by `SECURITY.md`) |
| Dependency graph | Enable |
| Dependabot alerts | Enable |
| Dependabot security updates | Enable |
| Secret scanning | Enable |
| Push protection | Enable: blocks pushes that contain keys or tokens |
| Code scanning (CodeQL) | Optional: "Default setup" scans the Python app |

Version updates are configured in `.github/dependabot.yml` (pip, Docker, GitHub Actions,
Terraform; weekly, minor and patch bumps grouped).

## 4. GitHub Actions

**Settings → Actions → General**:

| Setting | Value |
|---|---|
| Actions permissions | Allow all actions, or "Allow enterprise, and select non-enterprise, actions" with `actions/*`, `aws-actions/*`, `docker/*`, `hashicorp/*`, `azure/*`, `aquasecurity/*`, `anthropics/*` |
| Fork pull request workflows from outside collaborators | **Require approval for all external contributors** |
| Workflow permissions | **Read repository contents and packages permissions** (workflows that need more request it per job) |
| Allow GitHub Actions to create and approve pull requests | **Off** |

**Settings → Secrets and variables → Actions**: `ANTHROPIC_API_KEY` is the only
secret. `AWS_ROLE_ARN`, `AWS_REGION` and `ECR_REPOSITORY` are variables; the AWS role
trusts only this repository's `main` branch through OIDC.

## 5. Your account

- Two-factor authentication on (a passkey or security key is best).
- Prefer fine-grained personal access tokens scoped to this repository, with an expiry,
  for example the `GITHUB_PAT` the MCP server uses.
- Review **Settings → Applications** and remove OAuth apps and tokens you no longer use.

## Verify

```bash
curl -s https://api.github.com/repos/VenkatRamReddyjeggari/agentic-devops-platform/branches/main | jq .protected
# true once the main ruleset is active
```

Then try `git push origin main` from a clone: it should be rejected.
