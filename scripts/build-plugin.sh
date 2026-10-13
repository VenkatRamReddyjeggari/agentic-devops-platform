#!/usr/bin/env bash
# Package this repo's .claude/ setup as an installable Claude Code plugin.
# Source of truth stays in .claude/; plugin/ is generated (CI checks it is in sync).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/plugin"

rm -rf "$out/skills" "$out/agents" "$out/commands" "$out/hooks"
mkdir -p "$out/hooks/scripts"

cp -R "$root/.claude/skills"   "$out/skills"
cp -R "$root/.claude/agents"   "$out/agents"
cp -R "$root/.claude/commands" "$out/commands"
cp "$root/.claude/hooks/"*.sh  "$out/hooks/scripts/"
cp "$root/.mcp.json"           "$out/.mcp.json"

# Plugin hooks reference scripts via ${CLAUDE_PLUGIN_ROOT}
jq '{hooks: (.hooks | walk(
      if type == "object" and has("command")
      then .command |= sub("\"\\$CLAUDE_PROJECT_DIR\"/.claude/hooks/"; "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/")
      else . end))}' \
  "$root/.claude/settings.json" > "$out/hooks/hooks.json"

echo "plugin/ rebuilt from .claude/"
