#!/usr/bin/env bash
# Auto-mode benchmark: does the Rewrite picker show exactly when it should?
# Real model runs, so it costs money (about $3-4) and is not part of CI.
# Run from a session with askright installed (or pass PLUGIN_DIR=. to load this folder):
#   bash tests/auto-bench.sh            # all prompts, 4 at a time
#   JOBS=2 bash tests/auto-bench.sh
# Uses your real settings file, so mode should be auto (the default).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="${JOBS:-4}"
WORK="$(mktemp -d)"
PROJ="$WORK/proj"; OUT="$WORK/out"
mkdir -p "$PROJ" "$OUT"
cp -r "$ROOT/skills/askright/evals/vague-prompt-in-next-project/files/." "$PROJ/"
( cd "$PROJ" && git init -q && git add . && git -c user.email=t@t -c user.name=t commit -qm init ) 2>/dev/null
EXTRA=(); [ -n "${PLUGIN_DIR:-}" ] && EXTRA=(--plugin-dir "$PLUGIN_DIR")
# Measure auto mode whatever your settings file says (the hooks read this variable first).
export ASKRIGHT_FORCE_MODE="${BENCH_MODE:-auto}"

# label|expected (picker or run)|prompt
CASES=(
  "fix-it|picker|fix it"
  "faster|picker|make it faster"
  "design|picker|fix the design issue in header"
  "cleanup|picker|clean up the code"
  "hinglish-vague|picker|login page ka error theek karo"
  "styles|picker|update the styles"
  "add-tests|picker|add tests"
  "perf|picker|improve performance"
  "typo|run|chnage logo widht to w-32 in header"
  "bug|run|TypeError: Cannot read properties of undefined (reading 'map') in src/components/Header.tsx when the nav list is empty. Fix it so an empty list renders no nav; keep the markup otherwise."
  "alt|run|add alt=\"Logo\" to the img in src/components/Header.tsx"
  "rename|run|rename the Header component to SiteHeader in src/components/Header.tsx, keep the default export"
  "hindi-clear|run|src/components/Header.tsx में लोगो की चौड़ाई w-40 से w-32 करो"
  "question|run|what does the Header component render?"
  "gap|run|in src/components/Header.tsx change the nav gap from gap-8 to gap-4"
  # Non-code work: design, writing, data
  "design-vague|picker|make the landing page look better"
  "design-clear|run|in src/components/Header.tsx make the nav links text-sm font-medium text-gray-700 with hover:text-black; change nothing else"
  "writing-vague|picker|write a blog post"
  "writing-clear|run|write a 3-sentence release note for version 2.1 of this site saying the logo now has alt text; plain English, no marketing words; reply in chat, do not create files"
  "data-vague|picker|analyze the sales data"
)
# ONLY=<regex> runs just the matching labels, e.g. ONLY='design|writing|data'
if [ -n "${ONLY:-}" ]; then
  kept=(); for c in "${CASES[@]}"; do [[ "${c%%|*}" =~ $ONLY ]] && kept+=("$c"); done; CASES=("${kept[@]}")
fi

one() { # one <label> <prompt>: a fresh copy of the project per case, so edits don't leak
  local dir="$WORK/run-$1"
  cp -r "$PROJ" "$dir"
  ( cd "$dir" && timeout 300 claude -p "$2" "${EXTRA[@]}" --max-turns 6 --output-format json \
      --allowedTools "Read,Glob,Grep,Edit" --disallowedTools "Bash,Write" > "$OUT/$1.json" 2>/dev/null )
}

i=0
for c in "${CASES[@]}"; do
  IFS='|' read -r label _ prompt <<< "$c"
  one "$label" "$prompt" &
  i=$((i+1)); [ $((i % JOBS)) -eq 0 ] && wait
done
wait

# The follow-up case: a short prompt that is clear only because of the turn before it.
if [ -z "${ONLY:-}" ] || [[ followup =~ $ONLY ]]; then
dir="$WORK/run-followup"; cp -r "$PROJ" "$dir"
( cd "$dir" && timeout 300 claude -p "in src/components/Header.tsx add alt=\"Logo\" to the img" "${EXTRA[@]}" --max-turns 6 \
    --allowedTools "Read,Glob,Grep,Edit" --disallowedTools "Bash,Write" >/dev/null 2>&1 \
  && timeout 300 claude -c -p "now do the same for the nav: add aria-label=\"Main\"" "${EXTRA[@]}" --max-turns 6 --output-format json \
    --allowedTools "Read,Glob,Grep,Edit" --disallowedTools "Bash,Write" > "$OUT/followup.json" 2>/dev/null )
CASES+=("followup|run|now do the same for the nav: add aria-label=\"Main\"")
fi

printf '%s\n' "${CASES[@]}" > "$WORK/cases.txt"
node - "$WORK/cases.txt" "$OUT" <<'EOF'
const fs = require('fs'); const [cases, out] = process.argv.slice(2);
let tp = 0, fp = 0, fn = 0, tn = 0, invented = 0; const pickTimes = [], pickTokens = []; let cost = 0;
const pad = (s, n) => String(s).padEnd(n);
console.log(pad('case', 16) + pad('want', 8) + pad('got', 8) + pad('time', 8) + pad('out tok', 9) + 'cost');
for (const line of fs.readFileSync(cases, 'utf8').split('\n').filter(Boolean)) {
  const [label, want, ...rest] = line.split('|'); const prompt = rest.join('|');
  let j = null; try { j = JSON.parse(fs.readFileSync(`${out}/${label}.json`, 'utf8')) } catch {}
  if (!j) { console.log(pad(label, 16) + pad(want, 8) + 'ERROR (no result)'); continue }
  // In -p mode AskUserQuestion is not available, so the picker comes back as the numbered "Missing: ..." list.
  const got = /Missing:|Best match \(Recommended\)/.test(j.result || '') ? 'picker' : 'run';
  const secs = j.duration_ms / 1000, tok = j.usage?.output_tokens ?? 0; cost += j.total_cost_usd || 0;
  if (got === 'picker') {
    pickTimes.push(secs); pickTokens.push(tok)
    // Quality: a constraint the user never stated must sit inside [brackets]. Drop the
    // bracketed text and the quoted original, then look for constraint wording left in plain text.
    // Allowed: what the user wrote, and keeping behaviour in a refactor or speed-up.
    const plain = (j.result || '').replace(/\[[^\]]*\]/g, '').replace(/Use mine[\s\S]*$/i, '')
    const asked = prompt.toLowerCase()
    const hits = (plain.match(/\b(do not|don't|without changing|keep (the )?(existing|current))\b[^.\n]*/gi) || [])
      .filter(h => !/behaviou?r/i.test(h) && !asked.includes(h.toLowerCase().split(/\s+/).slice(0, 2).join(' ')))
    if (hits.length) { invented++; console.log('  ! stated as fact in ' + label + ': ' + hits.slice(0, 2).join(' | ')) }
  }
  if (want === 'picker') got === 'picker' ? tp++ : fn++; else got === 'picker' ? fp++ : tn++;
  console.log(pad(label, 16) + pad(want, 8) + pad(got === want ? got : got + ' ✗', 8) + pad(secs.toFixed(1) + 's', 8) + pad(tok, 9) + '$' + (j.total_cost_usd || 0).toFixed(3));
}
const med = a => { if (!a.length) return 0; const s = [...a].sort((x, y) => x - y); return s[Math.floor(s.length / 2)] };
const precision = tp / Math.max(1, tp + fp), recall = tp / Math.max(1, tp + fn);
console.log(`\npicker precision ${(precision * 100).toFixed(0)}%  recall ${(recall * 100).toFixed(0)}%  (tp ${tp}, fp ${fp}, fn ${fn}, tn ${tn})`);
console.log(`median picker time ${med(pickTimes).toFixed(1)}s, median picker output ${med(pickTokens)} tokens, total cost $${cost.toFixed(2)}`);
console.log(`pickers stating an unasked constraint as fact: ${invented} of ${pickTimes.length}`);
process.exitCode = precision >= 0.9 && recall >= 0.9 && invented === 0 ? 0 : 1;
EOF
status=$?
echo "work dir: $WORK"
exit $status
