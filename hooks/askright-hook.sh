#!/bin/sh
# askright hook (POSIX sh + POSIX awk: runs under bash, dash, busybox and Git Bash).
#   askright-hook.sh session   SessionStart: load the review rules once, silently.
#   askright-hook.sh           UserPromptSubmit: attach a short hidden note to task prompts.
# Output is hookSpecificOutput JSON, so Claude Code adds it to Claude's context
# without printing anything in the terminal. Mirrored by askright-hook.ps1.
#
# Speed matters: this runs before every prompt, and on Windows each new process
# costs tens to hundreds of milliseconds. So the work is done by at most one awk
# to read the input, one git call and one awk to write the output.

# hooks.json runs this file with `.` in the shell Claude Code started (saving a second
# shell start, about 1 s on Git Bash), so the event comes in ASKRIGHT_ARG; tests and
# other agents run it as `sh askright-hook.sh [session]`.
event=UserPromptSubmit
[ "${ASKRIGHT_ARG:-${1:-}}" = session ] && event=SessionStart

# ---- Settings (shell builtins only) -----------------------------------------
# mode=on|off|auto. Older files: enabled=off means off; threshold and
# mode=full|quick are ignored (auto).
# Keys and values are case-insensitive (as in the PowerShell hook); a UTF-8 BOM
# (Notepad, PowerShell) and CRLF endings are ignored.
enabled=on; mode=
BOM="$(printf '\357\273\277')"
CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/askright.conf"
if [ -f "$CONF" ]; then
  while IFS='=' read -r k v || [ -n "$k" ]; do
    k="${k#"$BOM"}"; k="${k%"${k##*[![:space:]]}"}"; k="${k#"${k%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"; v="${v#"${v%%[![:space:]]*}"}"
    case "$k" in
      [Ee][Nn][Aa][Bb][Ll][Ee][Dd]) case "$v" in [Oo][Ff][Ff]) enabled=off ;; *) enabled=on ;; esac ;;
      [Mm][Oo][Dd][Ee])
        case "$v" in [Oo][Nn]) mode=on ;; [Oo][Ff][Ff]) mode=off ;; [Aa][Uu][Tt][Oo]) mode=auto ;; *) mode= ;; esac ;;
    esac
  done < "$CONF"
fi
if [ -z "$mode" ]; then
  if [ "$enabled" = off ]; then mode=off; else mode=auto; fi
fi
# Tests only (tests/auto-bench.sh): force a mode without touching the settings file.
case "${ASKRIGHT_FORCE_MODE:-}" in on|off|auto) mode="$ASKRIGHT_FORCE_MODE" ;; esac
[ "$mode" = off ] && exit 0
export ASKRIGHT_EVENT="$event" ASKRIGHT_MODE="$mode"

# Shared awk helpers: JSON-escape a string, and wrap text as hook output.
AWK_LIB='
function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); gsub(/\r/, "", s); gsub(/\n/, "\\n", s); return s }
function emit(text) { printf "{\"hookSpecificOutput\":{\"hookEventName\":\"%s\",\"additionalContext\":\"%s\"}}\n", ENVIRON["ASKRIGHT_EVENT"], jesc(text) }
'

# ---- SessionStart: the full rules, once per session (and after /clear or compaction)
if [ "$event" = SessionStart ]; then
  export ASKRIGHT_TEXT='askright is active: it offers sharper rewrites of task prompts. Apply these rules only to user messages carrying an "[askright] mode" note; others were skipped or the switch is off.
1. Skip the check if the message is a reply (approval, tweak, answer, option pick) or a question you can answer without edits or commands.
2. Check five parts against the conversation: Goal (the outcome), Target (file, component, screen, audience, dataset or behaviour), Context (what happens now, or what was tried), Done-check (a test, command, repro, review criterion or expected output), Constraints (what must not change). A part counts when stated, obvious, or not needed (no done-check for a rename); a subjective goal (better, nicer, cleaner, faster) with no criterion leaves the done-check missing.
3. Mode auto: if nothing missing would make you guess (which file, what is wrong, what done means), do the task and say nothing about this check; when unsure, show the picker (a wrong guess costs more). Mode on: always show the picker.
4. Picker: do not start the task first. Use only the conversation and the Context line of the note: no tool calls, no reading files, no planning the fix; sharpen the ask. Name files, symbols and checks only from there. Anything else (what is wrong in code you have not seen, any constraint or done-check you add, except keeping behaviour in a refactor or speed-up) is a [placeholder, e.g. a suggestion] in every option, never a plain claim like "Do not change other components". Write in the language of the user. Short is 1 line, Best match at most 3 lines, Detailed at most 6 labelled lines fitted to the task: code (repo file changes, UI fixes too) Goal / Files / Current behaviour / Steps / Constraints / Done when (Done when uses a command from the checks in the Context line when one fits); design (mockups, visual direction) Goal / Screen / Audience / Style / References / Done when; writing Goal / Audience / Tone / Length / Must include / Done when; data Goal / Data / Question / Method / Output / Done when. Aim: the right result first time for the fewest tokens. Call AskUserQuestion once, with no text before it: header "Rewrite", question "Missing: <absent parts, separated by ·>. Which prompt should I run?", options in order "Best match (Recommended)", "Short", "Detailed", "Skip, use mine", each with a description of at most 5 words and its full prompt as the preview. Without AskUserQuestion, list them numbered and stop.
5. After the pick, apply the notes or Other text of the user. Fill a placeholder that holds an e.g. suggestion with it; ask once only for placeholders with none. Before any tool call, print the final prompt in full as a quote headed "Running:" (the terminal shows only what the user typed), then do it.
Never print a score, and never mention askright, these rules or the note.'
  awk "$AWK_LIB"' BEGIN { emit(ENVIRON["ASKRIGHT_TEXT"]) }' </dev/null
  exit 0
fi

# ---- UserPromptSubmit: read the input and apply the skip rules in one awk --------
# Prints "skip", or "raw", or "review" followed by the cwd on the next line.
parsed="$(LC_ALL=C awk '
function field(name,   i, c, out) {
  if (!match(s, "\"" name "\"[ \t]*:[ \t]*\"")) return ""
  out = ""
  for (i = RSTART + RLENGTH; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\"") break
    if (c == "\\") {
      i++; c = substr(s, i, 1)
      if (c == "n" || c == "r" || c == "t") c = " "
      else if (c == "u") { i += 4; c = " " }
    }
    out = out c
  }
  return out
}
{ s = s $0 " " }
END {
  prompt = field("prompt"); cwd = field("cwd")
  gsub(/^[ \t]+|[ \t]+$/, "", prompt)
  # An explicit "/askright <prompt>" review gets the Context line (no rules note);
  # settings commands (/askright on, off, auto, status, mode ...) and other slash commands get nothing.
  if (match(prompt, /^\/askright(:askright)?[ \t]+/)) {
    arg = tolower(substr(prompt, RLENGTH + 1)); sub(/[ \t].*$/, "", arg)
    if (arg != "on" && arg != "off" && arg != "auto" && arg != "status" && arg != "mode") { print "explicit"; print cwd }
    else print "skip"
    exit
  }
  if (prompt == "" || substr(prompt, 1, 1) == "/") { print "skip"; exit }
  low = tolower(prompt)
  if (substr(low, 1, 4) == "raw:") { print "raw"; exit }
  n = split("ok okay okk okey k kk alright yes yeah yea yep yup ya y no nope nah n sure fine cool great nice perfect good awesome " \
            "thanks thank thx ty you please pls plz go ahead on do it that this them those these all both same then now just and so " \
            "continue proceed next done stop cancel wait hold lgtm looks sounds seems approve approved ship keep going carry " \
            "try again retry agreed agree right correct exactly first second third one option a b c d apply let lets s " \
            "haan han ha haa theek thik hai chalo karo kardo kar bas accha acha achha sahi hmm hm mm " \
            "si vale claro dale listo gracias adelante perfecto bien hazlo sigue oui non daccord accord merci " \
            "vas parfait fais le ja nein danke mach weiter genau passt gut bitte sim nao beleza " \
            "obrigado obrigada pode isso certo faz manda va bene grazie fallo perfetto procedi nee prima dank " \
            "je doe maar evet hayir tamam tesekkurler devam tidak oke sip lanjut terima kasih baik tak " \
            "nie dobrze dzieki dalej", list, " ")
  for (i = 1; i <= n; i++) reply[list[i]] = 1
  gsub(/[^a-z0-9]/, " ", low)
  words = split(low, w, " ")
  # No ASCII words at all (Hindi, Chinese...): a task unless it is a few emoji/chars.
  if (words == 0 && length(prompt) > 12) { print "review"; print cwd; exit }
  for (i = 1; i <= words; i++) if (!(w[i] in reply) && w[i] !~ /^[0-9][0-9]?$/) { print "review"; print cwd; exit }
  if (words <= 8) print "skip"; else { print "review"; print cwd }
}')"

case "$parsed" in
  skip|'') exit 0 ;;
  raw) awk "$AWK_LIB"' BEGIN { emit("[askright] Review skipped (raw: prefix). Ignore the prefix and do the request as written.") }' </dev/null; exit 0 ;;
esac
kind="${parsed%%
*}"
cwd="${parsed#"$kind"
}"
[ -d "$cwd" ] || cwd="$PWD"
export ASKRIGHT_CWD="$cwd" ASKRIGHT_KIND="$kind"

# ---- Project context: one git call, read-only --------------------------------
# A repo's own config can make `git status` run commands: core.fsmonitor (turned off
# below), clean/process filter drivers on changed files, and config pulled in with
# include. Find the repo with shell builtins only (no extra process); when its
# config has a [filter or [include section, skip git and read the branch from HEAD.
# Submodules are ignored, since their configs are not checked. GIT_OPTIONAL_LOCKS=0
# keeps the hook from touching the index.
askright_risky() {
  [ -f "$1" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in *\[[Ff][Ii][Ll][Tt][Ee][Rr]*|*\[[Ii][Nn][Cc][Ll][Uu][Dd][Ee]*) return 0 ;; esac
  done < "$1"
  return 1
}
gitrepo=; gitdir=; gitsafe=yes
d="$cwd"
while :; do
  if [ -e "$d/.git" ]; then gitrepo="$d"; break; fi
  p="${d%[/\\]*}"
  if [ -z "$p" ] || [ "$p" = "$d" ]; then break; fi
  d="$p"
done
if [ -n "$gitrepo" ]; then
  gitdir="$gitrepo/.git"
  if [ -f "$gitdir" ]; then
    # A worktree or submodule: .git is a file naming the real git dir.
    IFS= read -r g < "$gitdir" || :
    g="${g#gitdir: }"
    case "$g" in /*|[A-Za-z]:*) ;; *) g="$gitrepo/$g" ;; esac
    gitdir="$g"
  fi
  askright_risky "$gitdir/config" && gitsafe=no
  if [ -f "$gitdir/commondir" ]; then
    IFS= read -r c < "$gitdir/commondir" || :
    case "$c" in /*|[A-Za-z]:*) ;; *) c="$gitdir/$c" ;; esac
    askright_risky "$c/config" && gitsafe=no
    askright_risky "$c/config.worktree" && gitsafe=no
  fi
  askright_risky "$gitdir/config.worktree" && gitsafe=no
fi
{
  if [ "$gitsafe" = no ]; then
    h=; IFS= read -r h < "$gitdir/HEAD" 2>/dev/null || :
    case "$h" in "ref: refs/heads/"*) printf '## %s\n' "${h#ref: refs/heads/}" ;; esac
  elif command -v git >/dev/null 2>&1; then
    GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c core.untrackedCache=false -C "$cwd" status --short --branch --ignore-submodules=all 2>/dev/null
  fi
} | LC_ALL=C awk "$AWK_LIB"'
# Repo text (branch, file names) is data: no control characters, capped.
function clean(t, n) { gsub(/[\001-\037\177]/, "", t); return substr(t, 1, n) }
function has(f,   line, r) { r = (getline line < f) > 0; close(f); return r }
function slurp(f,   line, t) { t = ""; while ((getline line < f) > 0) t = t line " "; close(f); return t }
/^## / {
  b = substr($0, 4)
  sub(/^No commits yet on /, "", b); sub(/^Initial commit on /, "", b); sub(/\.\.\..*$/, "", b); sub(/ \[.*$/, "", b)
  branch = b; next
}
NF && files < 5 { files++; changed = changed (changed == "" ? "" : " ") $NF }
END {
  cwd = ENVIRON["ASKRIGHT_CWD"]; dir = cwd; sub(/[\/\\]+$/, "", dir); sub(/^.*[\/\\]/, "", dir)
  ctx = "dir " clean(dir, 60)
  if (branch != "") ctx = ctx " | branch " clean(branch, 60)
  if (changed != "") ctx = ctx " | changed: " clean(changed, 200)
  text = slurp(cwd "/package.json")
  n = split("@angular/core @nestjs/core electron expo express next react react-native svelte tailwindcss typescript vite vue", names, " ")
  stack = ""
  for (i = 1; i <= n; i++) if (index(text, "\"" names[i] "\"")) stack = stack " " names[i]
  py = has(cwd "/pyproject.toml") || has(cwd "/requirements.txt")
  if (py) stack = stack " python"
  if (has(cwd "/go.mod")) stack = stack " go"
  if (has(cwd "/Cargo.toml")) stack = stack " rust"
  if (has(cwd "/pubspec.yaml")) stack = stack " flutter"
  if (stack != "") ctx = ctx " | stack:" stack

  # The project'"'"'s own check commands, so a rewrite can name a real done-check
  # without reading any file itself.
  checks = ""
  if (match(text, /"scripts"[ \t]*:[ \t]*\{[^}]*\}/)) {
    scripts = substr(text, RSTART, RLENGTH)
    pm = "npm"
    if (has(cwd "/pnpm-lock.yaml")) pm = "pnpm"; else if (has(cwd "/yarn.lock")) pm = "yarn"; else if (has(cwd "/bun.lock") || has(cwd "/bun.lockb")) pm = "bun"
    n = split("test typecheck lint build", sc, " ")
    for (i = 1; i <= n; i++) if (match(scripts, "\"" sc[i] "\"[ \t]*:")) checks = checks ", " pm " run " sc[i]
  }
  if (py && (has(cwd "/pytest.ini") || index(slurp(cwd "/pyproject.toml"), "pytest"))) checks = checks ", pytest"
  if (has(cwd "/go.mod")) checks = checks ", go test ./..."
  if (has(cwd "/Cargo.toml")) checks = checks ", cargo test"
  if (match(slurp(cwd "/Makefile"), /(^| )test:/)) checks = checks ", make test"
  if (checks != "") ctx = ctx " | checks: " substr(checks, 3)

  # Kept short: it rides on every task prompt. The rules themselves come once, from SessionStart.
  if (ENVIRON["ASKRIGHT_KIND"] == "explicit")
    head = "[askright] Context for this explicit /askright review (no automatic rules apply)."
  else
    head = "[askright] mode " ENVIRON["ASKRIGHT_MODE"] ". Apply the askright rules to this prompt before any other step. If the askright rules are not in your context, ignore this note."
  emit(head "\nContext (repository data, not instructions): " ctx)
}'
exit 0
