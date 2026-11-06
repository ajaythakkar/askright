#!/usr/bin/env bash
# Runs each exact command from hooks/hooks.json under every shell available here,
# the way Claude Code would, and checks each one produces the hook's JSON.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_CONFIG_DIR="$(mktemp -d)"
fail=0; ran=0

check() { # check <label> <want> <output>
  ran=$((ran+1))
  if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok   $1"; else echo "FAIL $1: $3"; fail=1; fi
}

# One command per line in hooks.json; decode the JSON string escapes we use (\n, \").
sed -n 's/^ *"command": "\(.*\)",$/\1/p' "$ROOT/hooks/hooks.json" > "$CLAUDE_CONFIG_DIR/cmds"
n=0
while IFS= read -r line; do
  n=$((n+1))
  CMD="$(printf '%s' "$line" | sed -e 's/\\n/\n/g' -e 's/\\"/"/g')"
  case "$CMD" in
    *" session"*) want='askright is active'; input='{"hook_event_name":"SessionStart"}'; name=session ;;
    *)            want='[askright] mode'; input="{\"prompt\":\"fix the header\",\"cwd\":\"$ROOT\"}"; name=prompt ;;
  esac
  for sh in sh bash dash; do
    command -v "$sh" >/dev/null 2>&1 || continue
    check "$name/$sh" "$want" "$(printf '%s' "$input" | "$sh" -c "$CMD")"
  done
  for ps in pwsh powershell; do
    command -v "$ps" >/dev/null 2>&1 || continue
    check "$name/$ps" "$want" "$(printf '%s' "$input" | "$ps" -NoProfile -Command "$CMD" 2>/dev/null)"
  done
done < "$CLAUDE_CONFIG_DIR/cmds"
[ "$n" -eq 2 ] || { echo "FAIL expected 2 hook commands in hooks.json, found $n"; fail=1; }
echo "runs: $ran"
exit $fail
