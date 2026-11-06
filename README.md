# askright

**Stop wasting turns on vague prompts.** askright spots what your prompt is missing before your AI coding agent starts guessing, and offers sharper rewrites in one click. Clear prompts run untouched.

[![tests](https://github.com/ajaythakkar/askright/actions/workflows/test.yml/badge.svg)](https://github.com/ajaythakkar/askright/actions/workflows/test.yml)
[![release](https://img.shields.io/github/v/release/ajaythakkar/askright)](https://github.com/ajaythakkar/askright/releases)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![skills.sh](https://img.shields.io/badge/skills.sh-askright-black)](https://skills.sh/ajaythakkar/askright/askright)
![works with](https://img.shields.io/badge/works%20with-Claude%20Code%20·%20Codex%20·%20OpenCode-8A2BE2)

<!-- Demo GIF: record ~15 s (vague prompt -> picker -> Running: quote -> result), save as docs/demo.gif, then uncomment:
![askright demo](docs/demo.gif)
-->

**Install in Claude Code** (then restart it):

```
/plugin marketplace add ajaythakkar/askright
/plugin install askright@askright-marketplace
```

Other agents: [Codex](#openai-codex-cli-always-on-review-beta), [OpenCode](#opencode-always-on-review-beta), or any agent that reads skills: `npx skills add ajaythakkar/askright`.

**What you get:** clear prompts run as usual with nothing extra on screen. Prompts that would make Claude guess (which file? what's wrong? what does done mean?) get a picker first:

```
> fix the design issue in header

Missing: what looks wrong · done-check · constraints. Which prompt should I run?
  ❯ Best match (Recommended)   Fix the layout of src/components/Header.tsx: [what looks wrong, e.g. ...]...
    Short                      Fix [the overlap] in src/components/Header.tsx using Tailwind...
    Detailed                   Goal / Files / Current behaviour / Steps / Constraints / Done when...
    Skip, use mine
    Other                      type your own version
```

- **Works in the background.** Install once and it stays on. No command to type, nothing printed for clear prompts, no scores.
- **One switch: `on`, `auto` or `off`.** `auto` (default) rewrites only when the prompt is missing something Claude would have to guess: which file, what is wrong, what "done" means. `on` offers rewrites for every task prompt. `off` does nothing. Click the band above the prompt to switch, or use `/askright on|auto|off`.
- **Says what's missing, not a number.** The picker names the absent parts: goal, target, context, done-check, constraints. A part that isn't needed (a done-check for a rename) doesn't count as missing.
- **Rewrites built for developers and prompt engineers:** Best match (up to 3 lines), Short (1 line) and Detailed (`Goal / Files / Current behaviour / Steps / Constraints / Done when`, with a real check such as your test command), plus your original. Unknowns stay as `[placeholders, e.g. a suggestion]` instead of invented facts. Add notes to any option to edit it, or choose **Other** to type your own.
- **Rewrites use your context:** the conversation, git branch, changed files and detected stack. No searching or file reading before the picker, so it appears in seconds and costs few tokens.
- **Replies and questions are never rewritten:** "ok do it", "yes please continue", "option 2", "haan kar do", "what does this function do?".
- **Any language:** rewrites come back in the language you wrote in. Tested with English, Hinglish, Hindi, Chinese and Japanese prompts; short replies such as "oui, merci", "sí, dale", "ja, mach weiter", "tamam devam", "да" or "好的" are recognised and never reviewed.
- **Not just code:** the Detailed rewrite picks labels that fit the task. Code gets `Goal / Files / Current behaviour / Steps / Constraints / Done when`; design gets `Goal / Screen / Audience / Style / References / Done when`; writing gets `Goal / Audience / Tone / Length / Must include / Done when`; data gets `Goal / Data / Question / Method / Output / Done when`.
- **Works in Claude Code** automatically (Codex and OpenCode in beta), and as an on-demand skill in Cursor, Gemini CLI, claude.ai and other agents that read `SKILL.md`.

## Before and after

**Without askright**, a vague prompt costs at least two turns:

```
> fix the design issue in header
  Claude reads files, guesses "the logo spacing", edits Header.tsx      ← turn 1, tokens spent
> no, the nav links overflow on mobile, and don't touch the colors
  Claude undoes part of it and tries again                              ← turn 2, more tokens
```

**With askright** (mode auto), you get one quick question, then one turn that lands:

```
> fix the design issue in header
Missing: what looks wrong · done-check · constraints. Which prompt should I run?
  ❯ Best match (Recommended)
    Fix src/components/Header.tsx: [what looks wrong, e.g. nav links overflow below 640px].
    [constraints, e.g. keep colors and links]. Done when [check, e.g. no overflow from 320px up]
    and `npm run build` passes.
  (you fill the placeholder, Claude runs it)                            ← one turn
```

A clear prompt sees no difference at all:

```
> chnage logo widht to w-32 in header
  Claude edits Header.tsx straight away. No picker, nothing extra on screen.
```

| | Without | With askright (auto) |
|---|---|---|
| Vague prompt | Claude guesses, you correct, repeat | Picker names what's missing; first run lands |
| Clear prompt | Runs | Runs (no picker, no visible trace) |
| Question ("what does X do?") | Answered | Answered (never rewritten) |
| Reply ("ok do it", "option 2") | Runs | Runs (never rewritten) |
| Cost of the check | None | About 130 tokens of hidden context per task prompt, plus about 700 tokens of rules once per session. No tool calls before the picker |

**Measured** (`tests/auto-bench.sh`, 21 labelled prompts in auto mode, covering code, design, writing and data): the picker showed for the vague prompts ("fix it", "make it faster", "add tests", "make the landing page look better", "write a blog post", "analyze the sales data", a Hinglish one...) and never for the clear ones (a typo-filled edit, a bug report with the error, a rename, a Hindi request, a question, a precise style change, a precise release note, a follow-up that is only clear from the turn before). Latest full run: **21 of 21 correct, 100% precision and 100% recall**. A picker turn took a median of 33 s and 695 output tokens (about 300 of them the visible picker, the rest the model's thinking), with no tool calls.

In the skill's eval suite (9 cases, 3 real model runs each), all 9 cases score 1.00 with askright installed, a mean of 0.39 higher than without it.

## Use cases

| You are | You type | askright helps by |
|---|---|---|
| Developer fixing a bug | `login is broken` | Asking for the error or repro and a done-check (`npm test`, a failing case) before Claude edits anything |
| Developer on a feature | `add dark mode` | Naming the files from your changes, the scope and a real check command from your project |
| Refactoring | `clean up the api code` | Turning "clean up" into a target, a rule (keep behaviour) and a test to run |
| Performance work | `make it faster` | Asking what is slow and how to measure it, so "faster" has a number |
| Prompt engineer | any vague ask | Showing the five parts (goal, target, context, done-check, constraints) a good prompt needs, every time, as a habit-builder |
| Designer | `make the landing page look better` | Turning taste into a checkable brief: screen, audience, style, references, done when |
| Writer | `write a blog post about our launch` | Asking for audience, tone, length and what it must include |
| Data analyst | `analyze the sales data` | Asking which dataset, which question and what output (chart, table, SQL) |
| Non-native English speaker | a request in Hindi, Spanish, Chinese... | Rewriting in your own language, never translating it away |

It stays out of the way for clear prompts, replies ("ok do it", "option 2"), questions and slash commands.

## Best practices

- **Leave it on `auto`.** It only asks when Claude would otherwise guess. Use `on` while you are learning to write prompts, or when you want to see the rewrites for every task.
- **Fill the placeholders.** `[what looks wrong, e.g. nav overlap]` is a question to you. Pick the option, then type the real answer in the notes field, or accept the suggestion as it is.
- **Pick Short for small, obvious jobs, Detailed for anything that spans files.** Best match is the balance and the right choice most of the time.
- **Use the notes field to edit an option** instead of retyping it: "also keep the old API" is enough.
- **Skip once with `raw:`.** `raw: just try it` runs exactly what you wrote, with no check.
- **Review a prompt on demand** with `/askright <prompt>`, in any mode, to see what it is missing before you send it.
- **Keep your project's checks in `package.json` scripts** (`test`, `lint`, `typecheck`, `build`), a `Makefile` `test:` target, pytest, `go test` or `cargo test`. askright reads them for free and puts the real command in the done-check.
- **Watch the band.** `rewritten · as-is · skipped` shows how often your prompts needed help; the number going down means your prompts are getting sharper.

## How it works

Two hooks and a band, no visible output from the hooks:

1. **SessionStart** loads the rules into Claude's context once per session (and again after `/clear` or compaction).
2. **UserPromptSubmit** attaches a short hidden note to each task prompt: the mode and project context (branch, up to 5 changed files, detected stack, and `checks:` with your project's own test, lint and build commands from `package.json` scripts, pytest, `go test`, `cargo test` or `make test`). So a rewrite can say "Done when `pnpm run test` passes" without reading a single file. It stays small, about 130 tokens, because it rides on every prompt. An explicit `/askright <prompt>` gets the same project context. Replies, slash commands and `raw:` messages get no note, so Claude doesn't touch them.
3. **The band** above the prompt (Claude Code only) shows `● Rewrite auto   rewritten 2 · as-is 5 · skipped 3`. Click it to cycle on → auto → off; it writes the settings file directly, sends nothing to the terminal, and the next prompt uses the new mode. After you pick a rewrite, a second line shows `▸ Running: <the prompt you picked>` until that turn ends, because Claude Code itself only shows the message you typed. Restart Claude Code after installing or updating to see it.

Both hooks return `hookSpecificOutput.additionalContext` JSON, so Claude Code passes the text to Claude without showing it in the terminal. When the mode is off, neither hook outputs anything.

## Install

### Claude Code plugin (always-on review)

```
/plugin marketplace add ajaythakkar/askright
/plugin install askright@askright-marketplace
```

Or from a terminal:

```
claude plugin marketplace add ajaythakkar/askright
claude plugin install askright@askright-marketplace
```

Restart Claude Code afterwards.

### OpenAI Codex CLI (always-on review, beta)

Codex has the same `SessionStart` and `UserPromptSubmit` hooks, so askright runs the same scripts there:

```
git clone https://github.com/ajaythakkar/askright && sh askright/integrations/codex/install.sh
```

The script copies the hooks to `~/.codex/askright/`, writes `~/.codex/hooks.json` (or prints the two entries to add if you already have one), and installs the skill to `~/.agents/skills/askright`. Start `codex`, open `/hooks` and trust the two askright hooks. Codex has no picker dialog, so the rewrites come as a numbered list: reply with a number. No band.

### OpenCode (always-on review, beta)

```
git clone https://github.com/ajaythakkar/askright && sh askright/integrations/opencode/install.sh
```

This installs a small plugin (`~/.config/opencode/plugins/askright.ts`) that runs the same hook scripts and adds the rules and each prompt's note to the system prompt, plus the skill. Restart `opencode`. Rewrites come as a numbered list. No band.

The Codex and OpenCode integrations are built from each tool's documented hook API and pass the installer tests and a type-check against `@opencode-ai/plugin` 1.19.5, but have not yet been tried in a live Codex or OpenCode session. Please open an issue if something differs.

### Skill only (on-demand `/askright <prompt>`)

For other agents that read `SKILL.md` (Cursor, Gemini CLI and others):

```
npx skills add ajaythakkar/askright
```

For claude.ai or the Claude desktop app: download `askright.skill` from the latest GitHub release and upload it under Settings > Capabilities > Skills.

Without the hooks nothing runs automatically: the skill reviews a prompt only when you call it.

## Commands

| Command | What it does |
|---|---|
| `/askright auto` | Rewrite only prompts that would make Claude guess (default) |
| `/askright on` | Offer rewrites for every task prompt |
| `/askright off` | Turn the background rewrite off |
| `/askright status` | Show the current mode |
| `/askright <prompt>` | Review this prompt now, in any mode |
| `raw: <prompt>` | Skip the rewrite for one message |

The mode is stored as `mode=on|auto|off` in `~/.claude/askright.conf` (or `$CLAUDE_CONFIG_DIR/askright.conf`). Keys and values are case-insensitive, and a BOM or Windows line endings are fine. Older files with `enabled=off` still read as off; `threshold` and `mode=full|quick` are ignored.

## Works on

| System | How the hooks run |
|---|---|
| macOS, Linux, WSL | POSIX `sh` (bash, dash or zsh's sh) |
| Alpine and other minimal containers | busybox `sh` (bash not needed) |
| Windows with Git for Windows | Git Bash `sh` |
| Windows without Git Bash | PowerShell (5.1 or 7) |

Each hook command is valid in both `sh` and PowerShell, and each shell runs its own version of the hook (`hooks/askright-hook.sh` or `hooks/askright-hook.ps1`). Nothing else needs installing: no Python, Node or jq. The sh hook starts at most three processes per prompt (awk, git, awk) and takes about 0.3 s, so it stays fast even where starting a process is slow, as in Git Bash on Windows. The PowerShell version is slower (about 3 s per prompt on Windows PowerShell 5.1), so Git for Windows is recommended. The hook command runs the script inside the shell Claude Code already starts (with `.`) instead of starting a second one, which on Git Bash cut the measured hook time from about 1.5 s to 0.5-1 s per prompt. Most of what remains is Claude Code starting that shell. CI tests both versions on Linux, macOS and Windows, plus busybox on Alpine.

## Development

```
bash tests/hook-test.sh                  # sh hook: skip/review, settings, session rules, context, JSON
HOOK_SH=dash bash tests/hook-test.sh     # same tests under dash
HOOK_PS=pwsh bash tests/hook-test.sh     # same tests against the PowerShell hook
bash tests/parity-test.sh                # sh and PowerShell hooks print the same text; checklist matches SKILL.md
bash tests/dual-shell-test.sh            # hooks.json commands under every installed shell
bash tests/integrations-test.sh          # Codex and OpenCode installers in a throwaway home folder
bash tests/auto-bench.sh                 # auto mode on 21 labelled prompts (code, design, writing, data): picker precision/recall, time, tokens (real model runs, about $3)
claude plugin test .                     # band module tests (mode switch, settings file, counters)
claude plugin eval skills/askright --scaffold --allow-tools Write,Edit   # skill evals (real model runs; add Bash only where a sandbox exists)
claude plugin validate .                 # manifest checks
claude --plugin-dir . -p "fix the header"   # try it without installing
```

## License

MIT

---

If askright saved you a turn, a ⭐ on [GitHub](https://github.com/ajaythakkar/askright) helps other developers find it.
