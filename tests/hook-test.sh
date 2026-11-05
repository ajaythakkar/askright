#!/usr/bin/env bash
# Tests for the hook. Run: bash tests/hook-test.sh
# To test the PowerShell version instead: HOOK_PS=pwsh bash tests/hook-test.sh  (or HOOK_PS=powershell)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/askright-hook.sh"
TMP="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$TMP"
pass=0; fail=0

# Encode a string as JSON (backslashes and quotes), with no external tools.
jstr() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
json() { printf '{"session_id":"t","prompt":%s,"cwd":%s,"hook_event_name":"UserPromptSubmit"}' "$(jstr "$1")" "$(jstr "$2")"; }
hook() {
  if [ -n "${HOOK_PS:-}" ]; then "$HOOK_PS" -NoProfile -ExecutionPolicy Bypass -File "$HERE/../hooks/askright-hook.ps1"
  else bash "$HOOK"; fi
}
run()  { json "$1" "$TMP" | hook; }

expect() { # expect review|skip "<prompt>"
  out="$(run "$2")"
  if [ "$1" = review ]; then got=$([ -n "$out" ] && echo review || echo skip)
  else got=$([ -z "$out" ] || printf '%s' "$out" | grep -q 'Review skipped' && echo skip || echo review); fi
  if [ "$got" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: expected $1, got $got: $2"; fi
}
contains() { # contains "<text>" "<prompt>"
  if run "$2" | grep -qF -- "$1"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: output missing '$1' for: $2"; fi
}

# Replies are skipped
for p in "ok" "ok do it" "Yes please, continue." "looks good, go ahead" "lgtm ship it" "option 2" "2" \
         "apply it" "thanks" "yes do that now" "haan kar do" "theek hai chalo" "ok 👍" "continue" "go ahead and do it"; do
  expect skip "$p"
done
# JSON escapes are decoded
expect review 'fix the "header" in C:\\src\\app.tsx'
expect skip 'ok "do it"'
# Slash commands and raw: are skipped
for p in "/askright off" "/help" "raw: bump version" "RAW: fix it"; do expect skip "$p"; done
# Real tasks are reviewed
for p in "fix this" "fix this design issue" "commit and push" "add dark mode to the header" \
         "ok but make the button blue" "why is the login page slow" "refactor api.ts to use fetch" \
         "yes and also add tests for the parser"; do
  expect review "$p"
done

# Defaults and settings
contains "threshold 80%" "fix the header"
contains "mode full" "fix the header"
printf 'threshold=65\nmode=quick\n' > "$TMP/askright.conf"
contains "threshold 65%" "fix the header"
contains "Use mine (NN%)\"" "fix the header"
printf 'threshold=abc\n' > "$TMP/askright.conf"
contains "threshold 80%" "fix the header"
printf 'enabled=off\n' > "$TMP/askright.conf"
expect skip "fix the header"
rm -f "$TMP/askright.conf"

# Project context
mkdir -p "$TMP/proj"
( cd "$TMP/proj" && git init -q && echo '{"dependencies":{"next":"14","tailwindcss":"3"}}' > package.json \
  && git add . && git -c user.email=t@t -c user.name=t commit -qm "init site" && echo x > new.ts )
ctxrun() { json "fix header" "$TMP/proj" | hook; }
for want in "stack: next tailwindcss" "changed: new.ts" "recent commits: init site"; do
  if ctxrun | grep -qF "$want"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: context missing '$want'"; fi
done

rm -rf "$TMP"
echo "${HOOK_PS:-bash}: passed $pass, failed $fail"
[ "$fail" -eq 0 ]
