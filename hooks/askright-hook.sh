#!/usr/bin/env bash
# askright: UserPromptSubmit hook.
# When ON, asks Claude to score the prompt and, below the threshold, offer 3 context-aware rewrites.
# Anything printed to stdout is added to Claude's context for this turn.

CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/askright.conf"
conf() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1 | tr -d '[:space:]'; }
enabled="$(conf enabled)";     [ -z "$enabled" ] && enabled=on
threshold="$(conf threshold)"; case "$threshold" in ''|*[!0-9]*) threshold=80 ;; esac
mode="$(conf mode)";           [ "$mode" = quick ] || mode=full
input="$(cat)"
[ "$enabled" = off ] && exit 0

# Read a top-level string field from the hook's JSON with plain sed, so the hook
# needs nothing beyond what ships with macOS, Linux and Git Bash on Windows.
field() {
  printf '%s' "$input" | tr '\n\r' '  ' \
    | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\\\/@@RW_BS@@/g' -e 's/\\"/"/g' -e 's/\\[nrt]/ /g' -e 's/\\\//\//g' \
          -e 's/\\u[0-9a-fA-F]\{4\}/ /g' -e 's/@@RW_BS@@/\\/g'
}
prompt="$(field prompt)"
cwd="$(field cwd)"
[ -d "$cwd" ] || cwd="$(printf '%s' "$cwd" | sed 's/\\/\//g')"   # C:\Users\x -> C:/Users/x
[ -d "$cwd" ] || cwd="$PWD"

trimmed="$(printf '%s' "$prompt" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
lower="$(printf '%s' "$trimmed" | LC_ALL=C tr '[:upper:]' '[:lower:]')"

# ---- Skip rules -------------------------------------------------------------
[ -z "$trimmed" ] && exit 0
case "$trimmed" in /*) exit 0 ;; esac
case "$lower" in
  raw:*) echo "[askright] Review skipped (raw: prefix). Ignore the prefix and do the request as written."; exit 0 ;;
esac

# Short replies made only of reply/approval words ("ok do it", "yes please continue", "haan kar do").
words="$(printf '%s' "$lower" | LC_ALL=C tr -c '[:alnum:]\n' ' ' | tr -s ' ')"
count=0; reply_only=1
for w in $words; do
  count=$((count + 1))
  case "$w" in
    ok|okay|okk|okey|k|kk|alright|yes|yeah|yea|yep|yup|ya|y|no|nope|nah|n|sure|fine|cool|great|nice|perfect|good|awesome|\
    thanks|thank|thx|ty|you|please|pls|plz|go|ahead|on|do|it|that|this|them|those|these|all|both|same|then|now|just|and|so|\
    continue|proceed|next|done|stop|cancel|wait|hold|lgtm|looks|sounds|seems|approve|approved|ship|keep|going|carry|\
    try|again|retry|agreed|agree|right|correct|exactly|first|second|third|one|option|a|b|c|d|[0-9]|[0-9][0-9]|\
    apply|let|lets|s|\
    haan|han|ha|haa|theek|thik|hai|chalo|karo|kardo|kar|bas|accha|acha|achha|sahi|hmm|hm|mm)
      ;;
    *) reply_only=0; break ;;
  esac
done
[ "$reply_only" = 1 ] && [ "$count" -le 8 ] && exit 0

# ---- Project context (cheap, read-only) ------------------------------------
ctx="dir $(basename "$cwd")"
if command -v git >/dev/null 2>&1 && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ctx="$ctx | branch $(git -C "$cwd" branch --show-current 2>/dev/null)"
  changed="$(git -C "$cwd" status --short 2>/dev/null | head -10 | awk '{print $NF}' | tr '\n' ' ')"
  [ -n "$changed" ] && ctx="$ctx | changed: $changed"
  last="$(git -C "$cwd" log -3 --pretty='%s' 2>/dev/null | paste -sd ';' -)"
  [ -n "$last" ] && ctx="$ctx | recent commits: $last"
fi
stack=""
[ -f "$cwd/package.json" ] && stack="$(grep -oE '"(next|react|vue|svelte|@angular/core|tailwindcss|vite|express|@nestjs/core|react-native|expo|electron|typescript)"' "$cwd/package.json" 2>/dev/null | tr -d '"' | sort -u | tr '\n' ' ')"
{ [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/requirements.txt" ]; } && stack="$stack python"
[ -f "$cwd/go.mod" ] && stack="$stack go"
[ -f "$cwd/Cargo.toml" ] && stack="$stack rust"
[ -f "$cwd/pubspec.yaml" ] && stack="$stack flutter"
stack="$(printf '%s' "$stack" | tr -s ' ' | sed 's/^ //;s/ $//')"
[ -n "$stack" ] && ctx="$ctx | stack: $stack"

if [ "$mode" = quick ]; then
  opts='2 options: "Best match (NN%) (Recommended)" and "Use mine (NN%)"'
else
  opts='4 options in order: "Best match (NN%) (Recommended)", "Short (NN%)" (1-2 lines), "Detailed (NN%)" (goal, context, steps, constraints, done-criteria), "Use mine (NN%)"'
fi

# ---- Compact instructions for Claude ----------------------------------------
cat <<EOF
[askright ON | threshold ${threshold}% | mode ${mode}] Review the user's prompt before starting work.
Context: ${ctx}
- Skip entirely if the message is a reply (approving, declining or tweaking what you proposed, answering your question, picking an option).
- Score 0-100 with this rubric, judging against conversation context: Goal 25, Target (file/page/component) 25, Context 20, Done-criteria 20, Constraints 10.
- Score >= ${threshold}: print one line "Prompt score NN% · Goal ✓ Target ✓ ..." and do the task as written. No picker.
- Score < ${threshold}: build rewrites from the conversation, the context line above, and at most 3 quick read-only lookups (Glob, Grep, a short file) so they name real files. Never invent facts; use [placeholders] for unknowns. Write in the user's language. Then call AskUserQuestion once: header "Rewrite", question "Prompt score NN% · <rubric ✓/✗ line> · <what's missing>. Which prompt should I run?", ${opts}; each with a one-line description and the full prompt as preview. The user may add notes (apply them as edits) or pick Other (use their text).
- Then ask once for any [placeholders] you can't fill, show the final prompt in a quote headed "Running:", and do it.
EOF
exit 0
