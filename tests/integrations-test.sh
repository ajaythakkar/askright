#!/usr/bin/env bash
# Checks the Codex and OpenCode installers in throwaway home folders:
# the files land where each agent looks, the Codex hooks.json is valid JSON,
# and its hook command runs and prints askright's output.
# Run: bash tests/integrations-test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

# ---- Codex ----
H="$(mktemp -d)"
HOME="$H" CODEX_HOME="$H/.codex" sh "$ROOT/integrations/codex/install.sh" >/dev/null || bad "codex install exited non-zero"
for f in .codex/hooks.json .codex/askright/askright-hook.sh .codex/askright/askright-hook.ps1 .agents/skills/askright/SKILL.md; do
  [ -s "$H/$f" ] && ok "codex: $f" || bad "codex: missing $f"
done
if command -v node >/dev/null 2>&1; then
  cmd="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    for (const ev of ["SessionStart", "UserPromptSubmit"]) {
      const h = j.hooks[ev][0].hooks[0];
      if (h.type !== "command" || !h.command || !h.commandWindows) throw new Error(ev);
    }
    console.log(j.hooks.UserPromptSubmit[0].hooks[0].command)' "$H/.codex/hooks.json" 2>/dev/null)" \
    && ok "codex: hooks.json is valid" || bad "codex: hooks.json is not valid"
  out="$(printf '{"prompt":"fix the header","cwd":"%s","hook_event_name":"UserPromptSubmit","turn_id":"t"}' "$ROOT" | CLAUDE_CONFIG_DIR="$H" sh -c "$cmd")"
  case "$out" in *'[askright] mode auto'*) ok "codex: hook command runs" ;; *) bad "codex: hook command output: $out" ;; esac
fi
# A second run must not overwrite an existing hooks.json
echo '{"hooks":{}}' > "$H/.codex/hooks.json"
HOME="$H" CODEX_HOME="$H/.codex" sh "$ROOT/integrations/codex/install.sh" >/dev/null
[ "$(cat "$H/.codex/hooks.json")" = '{"hooks":{}}' ] && ok "codex: keeps an existing hooks.json" || bad "codex: overwrote hooks.json"

# ---- OpenCode ----
H="$(mktemp -d)"
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$ROOT/integrations/opencode/install.sh" >/dev/null || bad "opencode install exited non-zero"
for f in plugins/askright.ts askright/askright-hook.sh askright/askright-hook.ps1 skills/askright/SKILL.md; do
  [ -s "$H/.config/opencode/$f" ] && ok "opencode: $f" || bad "opencode: missing $f"
done

exit $fail
