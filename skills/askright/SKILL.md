---
name: askright
description: "Use this skill whenever the user types /askright, asks to review, check, sharpen, rewrite or improve their own prompt or request before Claude acts on it (\"is this a good prompt?\", \"make my prompt better then do it\", \"how would you phrase this ask?\"), or wants to switch askright's always-on prompt rewrite on, off or to auto. It finds what the prompt is missing (goal, target, context, done-check, constraints), offers three context-aware rewrites (best match, short, detailed) plus the original, then runs the one the user picks. Do not use it to rewrite code, text, an email, a document or a message (\"rewrite this function\", \"rewrite this paragraph\"): that is an ordinary editing task. Also not for writing system prompts or prompts for other AI products."
license: MIT
---

# /askright

Argument: `$ARGUMENTS`

(If the line above still shows a literal `$ARGUMENTS`, the agent running this skill does not substitute arguments: use whatever the user wrote after `/askright` or `askright`, and treat no text as `status`.)

Vague requests waste a turn: Claude guesses, the user corrects, and both start over. This skill spends a few seconds up front to show what a request is missing and to offer sharper versions, so the first attempt lands. The user always keeps the final say, including running their original prompt unchanged.

## How it runs

- **With the Claude Code plugin** (hooks installed), the rewrite works in the background, always on. At session start a hook loads the rules silently, and each task prompt gets a short hidden `[askright]` note. In `auto` mode, clear prompts run with no visible trace and only prompts that would make Claude guess show the Rewrite picker; in `on` mode every task prompt shows it. Replies, questions, slash commands and `raw:` messages are never rewritten. A band above the prompt shows the mode and switches it with a click. This skill is then only used for settings and for explicit `/askright <prompt>` reviews.
- **Codex CLI and OpenCode** (installed with `integrations/codex/install.sh` or `integrations/opencode/install.sh`) run the same hooks automatically, without the band. There is no picker dialog there, so list the options numbered and ask for a number.
- **Skill only** (no hooks, for example installed with `npx skills add` into another agent, or uploaded to claude.ai), nothing runs automatically. It reviews only when called. `on`, `off` and `auto` still save the setting, but say in the reply that the automatic rewrite needs the Claude Code plugin.

## Settings

Settings live in `${CLAUDE_CONFIG_DIR:-~/.claude}/askright.conf` (on Windows, `%USERPROFILE%\.claude\askright.conf`) as `key=value` lines. There is one key:

| Key | Values | Default | Meaning |
|---|---|---|---|
| `mode` | on, off, auto | auto | `on`: rewrite every task prompt. `auto`: only when the prompt would make Claude guess. `off`: never |

Older files may hold `enabled`, `threshold` or `mode=full|quick`. The hooks read `enabled=off` as off and treat the rest as auto. When you write the file, set `mode=` and remove the `enabled` and `threshold` lines; keep any other lines as they are.

Change the setting with your file tools (Read, then Edit or Write, creating the file if missing). That works the same on macOS, Linux and Windows, unlike shell one-liners.

A missing file means the default (auto). If the file can't be read or written (a permission rule or sandbox blocks it), don't claim the change worked: say it couldn't be saved, give the exact path and the `mode=...` line to add by hand, and for `status` report the default while noting that the file couldn't be read.

| Argument | Action |
|---|---|
| `on` / `off` / `auto` (also `mode on`, `mode off`, `mode auto`) | Set `mode`. Reply in one line, e.g. "askright is AUTO: rewrites only when a prompt would make me guess. Prefix a message with `raw:` to skip once." The change applies from the next message. |
| `status` or empty | Read the file; report the mode (auto when missing) and list these commands |
| anything else | Review that text as a prompt (below) |

## Reviewing a prompt

When called with a prompt, always show the picker, whatever the mode: the user asked for a review explicitly.

1. **Use only what you already have.** Build the rewrites from the conversation so far and, when present, the Context line of the `[askright]` note (branch, changed files, stack, and `checks:` with the project's own test, lint and build commands). With the Claude Code plugin, an explicit `/askright <prompt>` gets that note too. Make no tool calls first: no searching, reading files or git commands. The point is to save the user time and tokens, so the picker should appear within seconds. Sharpen what the user asked; do not research or plan the solution. Name a file or symbol only when it appears in that context; otherwise use a placeholder.

2. **Find what's missing.** Check the prompt for these five parts, judged against what you already know. A part counts as present when it is stated, obvious from context, or not needed (no done-check for a rename, no constraints for a one-line fix). A subjective goal such as "better", "nicer", "cleaner" or "faster" with no criterion leaves the done-check missing, even when the target is obvious. The point is whether Claude could act without guessing. Never turn this into a score.

   | Part | Present when |
   |---|---|
   | Goal | The outcome is clear |
   | Target | The file, page, component, screen, audience, dataset or behaviour is named or obvious |
   | Context | What happens now, or what was tried, is stated |
   | Done-check | It says how to tell it worked: a test, command, repro step, review criterion or expected output |
   | Constraints | It says what must not change |

3. **Write three rewrites** in the user's language and voice, keeping their intent:
   - **Best match**: the version most likely to get the result the user wants, balancing length and precision. At most 3 lines.
   - **Short**: 1 line.
   - **Detailed**: at most 6 labelled lines, with labels that fit the task:

     | Task | Labels |
     |---|---|
     | Code (default; any change to files in the repo, UI and CSS fixes included) | `Goal / Files / Current behaviour / Steps / Constraints / Done when` |
     | Design (mockups, visual direction or UX not yet in code) | `Goal / Screen / Audience / Style / References / Done when` |
     | Writing (docs, copy, posts) | `Goal / Audience / Tone / Length / Must include / Done when` |
     | Data (analysis, SQL, charts) | `Goal / Data / Question / Method / Output / Done when` |

     For code, Done when uses a command from the Context line's `checks:` when one fits, otherwise a repro step or the expected output. For other tasks it is a review criterion the user can check, such as "fits on one screen at 375px" or "under 200 words".

   Keep every rewrite tight: each line should remove a guess, not add words. A prompt that costs fewer tokens and gets the right result first time is the goal.

   Use [bracketed placeholders] for anything you don't know. An invented detail looks authoritative and quietly sends the work the wrong way; a visible placeholder invites the user to fill it in.

   Facts from the conversation or Context line (file names, the stack, the test command) go in as plain text. Guesses about what the user means, such as which problem they see in a file you read, are still unknowns: put them inside the placeholder as suggestions, like `[what looks wrong, e.g. links overflow below 640px, or logo and nav not aligned]`, so the user confirms or replaces them instead of inheriting your guess. The same goes for constraints and done-checks you add yourself: the user never said "keep the colors" or "320px to desktop", so write `[constraints, e.g. keep colors and links]`, not the bare claim. Never state a guess as fact, in any option: Short drops what it can't confirm, it never turns a guess like "don't change the colors" into a plain claim.

4. **Ask** with AskUserQuestion, one question, header "Rewrite":
   - Question: "Missing: <the absent parts, separated by ·>. Which prompt should I run?" If nothing is missing: "Clear as written. Which prompt should I run?" Show no score, percentage or ✓/✗ marks.
   - Options, in order: "Best match (Recommended)", "Short", "Detailed", "Skip, use mine". Give each a description of at most 5 words and its full prompt as the preview. Write no text before the call: the picker is the whole reply.
   - If AskUserQuestion isn't available, list the same options as numbered text and ask the user to reply with a number.

5. **Run it.** Apply any notes the user added to their choice as edits, or use their "Other" text as the prompt. Fill a placeholder that holds an "e.g." suggestion with that suggestion; ask once only for placeholders that have none. Before any tool call, print the final prompt in full as a quote headed "Running:", then carry it out. Don't skip or shorten this: the terminal only shows what the user typed, so the quote is the only place they see the prompt that actually runs.

## Example

User, in a Next.js + Tailwind repo. The note's Context line says `changed: src/components/Header.tsx | stack: next tailwindcss | checks: npm run lint, npm run build`. Prompt: `/askright fix the design issue in header`

> Missing: what looks wrong · done-check · constraints. Which prompt should I run?
> - **Best match (Recommended)**: Fix src/components/Header.tsx: [what looks wrong, e.g. logo and nav overlap below 768px]. Use Tailwind. [constraints, e.g. keep colors and links]. Done when [check, e.g. no overlap from 320px up] and `npm run build` passes.
> - **Short**: Fix [the issue, e.g. the overlap] in src/components/Header.tsx with Tailwind.
> - **Detailed**: Goal: [the fix] / Files: src/components/Header.tsx / Current behaviour: [what looks wrong] / Steps: [e.g. fix flex layout, add wrapping] / Constraints: [e.g. keep colors and links] / Done when: [visual check, e.g. 320px to 1440px], `npm run lint` and `npm run build` pass
> - **Skip, use mine**: fix the design issue in header
