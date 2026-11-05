#!/usr/bin/env bash
# Runs the exact command from hooks/hooks.json under every shell available here,
# the way Claude Code would, and checks each one produces the review text.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$(sed -n 's/^ *"command": "\(.*\)",$/\1/p' "$ROOT/hooks/hooks.json" | sed -e 's/\\n/\n/g' -e 's/\\"/"/g')"
INPUT="{\"prompt\":\"fix the header\",\"cwd\":\"$ROOT\"}"
export CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_CONFIG_DIR="$(mktemp -d)"
fail=0; ran=0
check() { # check <shell> <output>
  ran=$((ran+1))
  if printf '%s' "$2" | grep -q '^\[askright ON'; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi
}
check bash "$(printf '%s' "$INPUT" | bash -c "$CMD")"
for ps in pwsh powershell; do
  command -v "$ps" >/dev/null 2>&1 || continue
  check "$ps" "$(printf '%s' "$INPUT" | "$ps" -NoProfile -Command "$CMD" 2>/dev/null)"
done
echo "shells tested: $ran"
exit $fail
