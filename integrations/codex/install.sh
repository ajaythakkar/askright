#!/bin/sh
# Install askright for OpenAI Codex CLI: the same two hook scripts as the Claude Code
# plugin (Codex has SessionStart and UserPromptSubmit hooks that read the same JSON)
# plus the /askright skill.
#   sh integrations/codex/install.sh
# Codex asks you to review and trust new hooks once, in its /hooks screen.
# Settings are shared with Claude Code: ${CLAUDE_CONFIG_DIR:-~/.claude}/askright.conf
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CODEX="${CODEX_HOME:-$HOME/.codex}"
DEST="$CODEX/askright"
SKILL="$HOME/.agents/skills/askright"

mkdir -p "$DEST" "$SKILL"
cp "$ROOT/hooks/askright-hook.sh" "$ROOT/hooks/askright-hook.ps1" "$DEST/"
cp "$ROOT/skills/askright/SKILL.md" "$SKILL/SKILL.md"

# Codex on Windows runs native paths: C:/Users/... works for both sh and PowerShell.
P="$DEST"; command -v cygpath >/dev/null 2>&1 && P="$(cygpath -m "$DEST")"
hook() { # hook <event> <arg>
  printf '      {"hooks": [{"type": "command", "timeout": 30,\n'
  printf '        "command": "sh \\"%s/askright-hook.sh\\"%s",\n' "$P" "$2"
  printf '        "commandWindows": "powershell -NoProfile -ExecutionPolicy Bypass -File \\"%s/askright-hook.ps1\\"%s"}]}' "$P" "$2"
}
JSON="$(printf '{\n  "hooks": {\n    "SessionStart": [\n%s\n    ],\n    "UserPromptSubmit": [\n%s\n    ]\n  }\n}\n' \
  "$(hook SessionStart ' session')" "$(hook UserPromptSubmit '')")"

if [ -e "$CODEX/hooks.json" ]; then
  echo "$CODEX/hooks.json already exists; add these two entries to its \"hooks\" object by hand:"
  echo
  printf '%s\n' "$JSON"
else
  printf '%s\n' "$JSON" > "$CODEX/hooks.json"
  echo "Wrote $CODEX/hooks.json"
fi
echo "Copied hooks to $DEST and the skill to $SKILL"
echo "Next: start codex, open /hooks, review and trust the two askright hooks."
