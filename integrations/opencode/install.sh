#!/bin/sh
# Install askright for OpenCode: a small plugin that runs the shared hook scripts,
# plus the /askright skill.
#   sh integrations/opencode/install.sh
# Settings are shared with Claude Code: ${CLAUDE_CONFIG_DIR:-~/.claude}/askright.conf
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

mkdir -p "$CFG/askright" "$CFG/plugins" "$CFG/skills/askright"
cp "$ROOT/hooks/askright-hook.sh" "$ROOT/hooks/askright-hook.ps1" "$CFG/askright/"
cp "$ROOT/integrations/opencode/askright.ts" "$CFG/plugins/askright.ts"
cp "$ROOT/skills/askright/SKILL.md" "$CFG/skills/askright/SKILL.md"
echo "Installed: $CFG/plugins/askright.ts, hooks in $CFG/askright, skill in $CFG/skills/askright"
echo "Restart opencode to load the plugin."
