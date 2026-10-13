#!/usr/bin/env bash
# SessionStart: stdout is added to Claude's context. Gives the agent live
# repo state (branch, pending changes, recent commits) before it starts.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

echo "## Live repo context (from SessionStart hook)"
echo "- Branch: $(git branch --show-current 2>/dev/null || echo detached)"
echo "- Uncommitted files: $(git status --porcelain | wc -l | tr -d ' ')"
echo "- Recent commits:"
git log --oneline -5 2>/dev/null | sed 's/^/  - /'
if [[ "$(git branch --show-current 2>/dev/null)" == "main" ]]; then
  echo "- WARNING: you are on main. Create a feature branch before editing."
fi
exit 0
