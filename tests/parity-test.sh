#!/usr/bin/env bash
# Checks that askright-hook.sh and askright-hook.ps1 produce the same text, and that
# SKILL.md uses the same rubric. Run: bash tests/parity-test.sh  (HOOK_PS=pwsh to pick the PowerShell)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; export CLAUDE_CONFIG_DIR="$TMP"
PS="${HOOK_PS:-}"
[ -z "$PS" ] && for p in pwsh powershell; do command -v "$p" >/dev/null 2>&1 && { PS="$p"; break; }; done
fail=0

# Normalise JSON-string escapes that differ between the two writers (PowerShell 5.1 writes ' for ').
norm() {
  sed -e 's/\\u0027/'"'"'/g' -e 's/\\u003c/</g' -e 's/\\u003e/>/g' -e 's/\\u0026/\&/g' \
      -e 's/\\u2713/✓/g' -e 's/\\u2717/✗/g' -e 's/\\u00b7/·/g' -e 's/\\u00B7/·/g' | tr -d '\r'
}
same() { # same <label> <arg> <input>
  a="$(printf '%s' "$3" | sh "$ROOT/hooks/askright-hook.sh" $2 | norm)"
  b="$(printf '%s' "$3" | "$PS" -NoProfile -ExecutionPolicy Bypass -File "$ROOT/hooks/askright-hook.ps1" $2 | norm)"
  if [ "$a" = "$b" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  sh: $a"; echo "  ps: $b"; fail=1; fi
}

if [ -n "$PS" ]; then
  mkdir -p "$TMP/p" && ( cd "$TMP/p" && git init -q \
    && printf '{\n  "scripts": {\n    "dev": "vite",\n    "test": "vitest",\n    "build": "vite build"\n  },\n  "dependencies":{"react":"18","vite":"5"}\n}\n' > package.json \
    && echo 'lockfileVersion: 9' > pnpm-lock.yaml && printf 'all:\n\ttrue\ntest:\n\ttrue\n' > Makefile && : > yarn.lock \
    && git add . && git -c user.email=t@t -c user.name=t commit -qm "first" && echo x > a.ts ) 2>/dev/null
  P="$TMP/p"; command -v cygpath >/dev/null 2>&1 && P="$(cygpath -m "$P")"   # Windows: C:/... like Claude Code sends
  same session session '{}'
  same prompt "" "{\"prompt\":\"fix the header\",\"cwd\":\"$P\"}"
  same raw "" '{"prompt":"raw: bump it","cwd":"."}'
  same explicit "" "{\"prompt\":\"/askright fix the header\",\"cwd\":\"$P\"}"
  same explicit-settings "" "{\"prompt\":\"/askright:askright mode on\",\"cwd\":\"$P\"}"
  same hindi "" "{\"prompt\":\"हेडर का डिज़ाइन ठीक करो\",\"cwd\":\"$P\"}"
  printf 'mode=on\n' > "$TMP/askright.conf"
  same mode-on "" "{\"prompt\":\"fix the header\",\"cwd\":\"$P\"}"
  printf 'enabled=off\n' > "$TMP/askright.conf"
  same legacy-off "" "{\"prompt\":\"fix the header\",\"cwd\":\"$P\"}"
  printf 'threshold=70\nmode=quick\n' > "$TMP/askright.conf"
  same legacy-quick "" "{\"prompt\":\"fix the header\",\"cwd\":\"$P\"}"
else
  echo "skip hook parity: no PowerShell found"
fi

# The checklist parts and option names in SKILL.md match the hooks.
for part in "Goal" "Target" "Context" "Done-check" "Constraints"; do
  grep -qF "| $part |" "$ROOT/skills/askright/SKILL.md" || { echo "FAIL SKILL.md checklist missing '$part'"; fail=1; }
  for f in askright-hook.sh askright-hook.ps1; do
    grep -qF "$part (" "$ROOT/hooks/$f" || { echo "FAIL $f checklist missing '$part ('"; fail=1; }
  done
done
for f in hooks/askright-hook.sh hooks/askright-hook.ps1 skills/askright/SKILL.md; do
  for text in "Best match (Recommended)" "Skip, use mine" "Goal / Files / Current behaviour / Steps / Constraints / Done when" "Missing: "; do
    grep -qF "$text" "$ROOT/$f" || { echo "FAIL $f missing '$text'"; fail=1; }
  done
  grep -qF "NN%" "$ROOT/$f" && { echo "FAIL $f still shows a score (NN%)"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "checklist ok"

# One reply-word list, in three copies: the sh awk, the PowerShell $replyWords and the band's REPLY.
words_sh="$(sed -n '/n = split("ok okay/,/", list, " ")/p' "$ROOT/hooks/askright-hook.sh" | grep -o '"[^"]*"' | tr -d '"' | tr ' ' '\n' | grep -v '^$' | sort -u)"
words_ps="$(sed -n '/^\$replyWords = @(/,/^)/p' "$ROOT/hooks/askright-hook.ps1" | grep -o "'[^']*'" | tr -d "'" | sort -u)"
words_ts="$(sed -n '/^const REPLY = new Set(/,/^)/p' "$ROOT/hooks/band/register.tsx" | grep -o "'[^']*'" | tr -d "'" | tr ' ' '\n' | grep -v '^$' | sort -u)"
n_sh=$(printf '%s\n' "$words_sh" | wc -l)
if [ "$n_sh" -gt 100 ] && [ "$words_sh" = "$words_ps" ] && [ "$words_sh" = "$words_ts" ]; then echo "reply words ok ($n_sh)"
else
  echo "FAIL reply-word lists differ (sh $n_sh, ps $(printf '%s\n' "$words_ps" | wc -l), band $(printf '%s\n' "$words_ts" | wc -l))"
  diff <(printf '%s\n' "$words_sh") <(printf '%s\n' "$words_ps") | head -5
  diff <(printf '%s\n' "$words_sh") <(printf '%s\n' "$words_ts") | head -5
  fail=1
fi
rm -rf "$TMP"
exit $fail
