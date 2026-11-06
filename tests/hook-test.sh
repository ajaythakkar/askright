#!/usr/bin/env bash
# Tests for the hook. Run: bash tests/hook-test.sh
# Pick the shell that runs the sh hook: HOOK_SH=dash bash tests/hook-test.sh  (default: sh)
# Test the PowerShell version instead: HOOK_PS=pwsh bash tests/hook-test.sh  (or HOOK_PS=powershell)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/askright-hook.sh"
TMP="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$TMP"
pass=0; fail=0

# Encode a string as JSON (backslashes and quotes), with no external tools.
jstr() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
json() { printf '{"session_id":"t","prompt":%s,"cwd":%s,"hook_event_name":"UserPromptSubmit"}' "$(jstr "$1")" "$(jstr "$2")"; }
hook() { # hook [session]
  if [ -n "${HOOK_PS:-}" ]; then "$HOOK_PS" -NoProfile -ExecutionPolicy Bypass -File "$HERE/../hooks/askright-hook.ps1" "$@"
  else "${HOOK_SH:-sh}" "$HOOK" "$@"; fi
}
run()  { json "$1" "$TMP" | hook; }
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $*"; }

# Valid JSON check, when node or python is around (CI runners have both).
valid_json() {
  if command -v node >/dev/null 2>&1; then node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
  else cat >/dev/null; fi
}

expect() { # expect review|skip "<prompt>"
  out="$(run "$2")"
  if [ "$1" = review ]; then got=$([ -n "$out" ] && echo review || echo skip)
  else got=$([ -z "$out" ] || printf '%s' "$out" | grep -q 'Review skipped' && echo skip || echo review); fi
  if [ "$got" = "$1" ]; then ok; else bad "expected $1, got $got: $2"; fi
  if [ -n "$out" ]; then printf '%s' "$out" | valid_json && ok || bad "invalid JSON for: $2"; fi
}
contains() { # contains "<text>" "<prompt>"
  if run "$2" | grep -qF -- "$1"; then ok; else bad "output missing '$1' for: $2"; fi
}
lacks() { # lacks "<text>" "<prompt>"
  if run "$2" | grep -qF -- "$1"; then bad "output has '$1' for: $2"; else ok; fi
}

# Replies are skipped
for p in "ok" "ok do it" "Yes please, continue." "looks good, go ahead" "lgtm ship it" "option 2" "2" \
         "apply it" "thanks" "yes do that now" "haan kar do" "theek hai chalo" "ok 👍" "continue" "go ahead and do it"; do
  expect skip "$p"
done
# JSON escapes are decoded, and the output is valid JSON
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
# Prompts with no ASCII words are tasks, unless they are only a few emoji
for p in "हेडर का डिज़ाइन ठीक करो" "修复登录页面的错误" "ヘッダーを直して"; do expect review "$p"; done
for p in "👍" "👍👍" "🙏"; do expect skip "$p"; done
# Short replies in other languages are skipped; tasks in those languages are not
for p in "oui, merci" "sí, dale" "ja, mach weiter" "tamam devam" "ok obrigado" "va bene, grazie" "tak, dalej" "да" "好的" "はい"; do expect skip "$p"; done
for p in "corrige el error del login" "corrige le bug du header" "behebe den Fehler im Header" "header hatasını düzelt"; do expect review "$p"; done
# A long prompt still gives valid JSON
expect review "fix $(printf 'a%.0s' $(seq 1 3000))"

# Output is hidden context, not terminal text
contains '"hookEventName":"UserPromptSubmit"' "fix the header"
contains '"additionalContext":"[askright]' "fix the header"

# Defaults and settings
contains "[askright] mode auto." "fix the header"
lacks "NN%" "fix the header"
lacks "(threshold" "fix the header"
# The per-prompt note stays small: the rules come once, from SessionStart
n=$(run "fix the header" | wc -c); if [ "$n" -lt 700 ]; then ok; else bad "per-prompt note is $n bytes (want < 700)"; fi
printf 'mode=on\n' > "$TMP/askright.conf"
contains "[askright] mode on." "fix the header"
printf 'mode = auto \n' > "$TMP/askright.conf"
contains "[askright] mode auto." "fix the header"
# Older settings files: threshold and mode=full|quick fall back to auto
printf 'threshold=65\nmode=quick\n' > "$TMP/askright.conf"
contains "[askright] mode auto." "fix the header"
printf 'mode=garbage\n' > "$TMP/askright.conf"
contains "[askright] mode auto." "fix the header"
printf 'enabled=on\nmode=on\n' > "$TMP/askright.conf"
contains "[askright] mode on." "fix the header"
# Case, BOM and CRLF in the settings file (Notepad and PowerShell write these)
printf 'MODE=OFF\n' > "$TMP/askright.conf"
if [ -z "$(run "fix the header")" ]; then ok; else bad "MODE=OFF ignored"; fi
printf '\357\273\277mode=off\r\n' > "$TMP/askright.conf"
if [ -z "$(run "fix the header")" ]; then ok; else bad "BOM + CRLF mode=off ignored"; fi
printf 'Enabled = OFF\n' > "$TMP/askright.conf"
if [ -z "$(run "fix the header")" ]; then ok; else bad "Enabled = OFF ignored"; fi
printf 'mode=On\r\n' > "$TMP/askright.conf"
contains "[askright] mode on." "fix the header"
# Off: no note and no session rules, from the new key or the old one
for conf in 'mode=off\n' 'enabled=off\n' 'enabled=off\nmode=full\n'; do
  printf "$conf" > "$TMP/askright.conf"
  if [ -z "$(run "fix the header")" ]; then ok; else bad "note sent while off ($conf)"; fi
  if [ -z "$(printf '{}' | hook session)" ]; then ok; else bad "session rules loaded while off ($conf)"; fi
done
printf 'enabled=off\nmode=on\n' > "$TMP/askright.conf"
contains "[askright] mode on." "fix the header"
rm -f "$TMP/askright.conf"

# SessionStart loads the rules once
s="$(printf '{"hook_event_name":"SessionStart","source":"startup"}' | hook session)"
for want in '"hookEventName":"SessionStart"' "askright is active" "Goal (" "Done-check (" "Constraints (" \
            "Mode auto:" "Mode on:" "Missing: " "Done when" "Best match (Recommended)" "Skip, use mine" "at most 6 labelled lines" "Goal / Screen / Audience / Style" "Goal / Audience / Tone" "Goal / Data / Question" "no tool calls" "fewest tokens" "AskUserQuestion" "Never print a score"; do
  if printf '%s' "$s" | grep -qF -- "$want"; then ok; else bad "session output missing '$want'"; fi
done
for unwanted in "NN%" "Prompt score" "threshold" "lookups" "Glob"; do
  if printf '%s' "$s" | grep -qF -- "$unwanted"; then bad "session output has '$unwanted'"; else ok; fi
done
printf '%s' "$s" | valid_json && ok || bad "session output is not valid JSON"
# The rules come once per session, but every token still counts
n=$(printf '%s' "$s" | wc -c); if [ "$n" -lt 3000 ]; then ok; else bad "session rules are $n bytes (want < 3000)"; fi

# Project context
mkdir -p "$TMP/proj"
( cd "$TMP/proj" && git init -q \
  && printf '{\n  "scripts": {\n    "dev": "next dev",\n    "lint": "eslint .",\n    "test": "vitest"\n  },\n  "dependencies":{"next":"14","tailwindcss":"3"}\n}\n' > package.json \
  && echo 'lockfileVersion: 9' > pnpm-lock.yaml \
  && git add . && git -c user.email=t@t -c user.name=t commit -qm 'init "site"' && echo x > new.ts \
  && for i in 1 2 3 4 5 6 7; do echo x > "extra$i.ts"; done ) 2>/dev/null
PROJ="$TMP/proj"; command -v cygpath >/dev/null 2>&1 && PROJ="$(cygpath -m "$PROJ")"   # Windows: C:/... like Claude Code sends
ctxrun() { json "fix header" "$PROJ" | hook; }
for want in "stack: next tailwindcss" "changed: extra1.ts" "branch " "checks: pnpm run test, pnpm run lint"; do
  if ctxrun | grep -qF "$want"; then ok; else bad "context missing '$want'"; fi
done
# At most 5 changed files (8 are changed here)
if ctxrun | grep -qF "extra5.ts" && ! ctxrun | grep -qF "extra6.ts"; then ok; else bad "changed files not capped at 5"; fi
# An explicit /askright <prompt> review gets the Context line, without the automatic rules note
out="$(json "/askright fix the header" "$PROJ" | hook)"
if printf '%s' "$out" | grep -qF "explicit /askright review" && printf '%s' "$out" | grep -qF "checks: pnpm run test"; then ok; else bad "explicit review got no context: $out"; fi
printf '%s' "$out" | valid_json && ok || bad "explicit note is not valid JSON"
if printf '%s' "$out" | grep -qF "[askright] mode"; then bad "explicit review got the automatic note"; else ok; fi
for p in "/askright off" "/askright:askright mode on" "/askright status" "/askright" "/help"; do
  if [ -z "$(json "$p" "$PROJ" | hook)" ]; then ok; else bad "settings or other slash command got a note: $p"; fi
done
ctxrun | valid_json && ok || bad "context output is not valid JSON"
if ctxrun | grep -qF "recent commits"; then bad "commit subjects should not be sent"; else ok; fi

# A repo's core.fsmonitor must not run (it would execute on `git status`)
mkdir -p "$TMP/evil"
( cd "$TMP/evil" && git init -q && git config core.fsmonitor "touch '$TMP/pwned'" && echo x > f.txt ) 2>/dev/null
EVIL="$TMP/evil"; command -v cygpath >/dev/null 2>&1 && EVIL="$(cygpath -m "$EVIL")"
json "fix header" "$EVIL" | hook >/dev/null
if [ -e "$TMP/pwned" ]; then bad "core.fsmonitor from the repo config ran"; else ok; fi

rm -rf "$TMP"
echo "${HOOK_PS:-${HOOK_SH:-sh}}: passed $pass, failed $fail"
[ "$fail" -eq 0 ]
