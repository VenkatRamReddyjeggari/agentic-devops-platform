# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub: **Security → Report a vulnerability** on this repository
(private vulnerability reporting). Include what you found, how to reproduce it, and the
impact you expect. You should get a reply within 7 days.

In scope: the Terraform, Helm chart, application code, GitHub Actions workflows, and the
Claude Code configuration (hooks, permissions, skills) in this repository.

## Supported versions

Only the `main` branch is maintained.

## How this repository protects itself

- `main` is protected by a ruleset: pull requests and green CI are required, and force pushes
  and deletion are blocked. Deploy tags are written to the separate `env/dev` branch, so no
  bot needs to bypass these rules.
- GitHub Actions reach AWS through OIDC with a role limited to pushing one ECR repository
  from `main`; no AWS keys are stored in GitHub.
- Third-party actions in the release path are pinned to commit SHAs; Dependabot proposes
  updates weekly.
- Secret scanning with push protection is enabled.
- The `@claude` workflow runs only for the owner and collaborators.
- Claude Code itself runs behind hooks that block destructive commands, deny secret files,
  and require a human for production changes (see `docs/claude-code.md`).

Repository settings are listed in [`docs/repository-security.md`](docs/repository-security.md).
