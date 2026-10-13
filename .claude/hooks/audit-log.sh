#!/usr/bin/env bash
# Stop: append one JSON line per finished turn to an audit log, so every
# agent session leaves a trail (who, when, which session, which branch).
set -uo pipefail

input="$(cat)"
log_dir="${CLAUDE_PROJECT_DIR:-.}/.claude/logs"
mkdir -p "$log_dir"

branch="$(git -C "${CLAUDE_PROJECT_DIR:-.}" branch --show-current 2>/dev/null || echo unknown)"
jq -c --arg ts "$(date -u +%FT%TZ)" --arg user "${USER:-unknown}" --arg branch "$branch" \
  '{ts: $ts, user: $user, branch: $branch, session: .session_id, event: .hook_event_name}' \
  <<<"$input" >>"$log_dir/audit.jsonl"

exit 0
