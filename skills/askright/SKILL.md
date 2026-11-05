---
name: askright
description: Scores a prompt from 0 to 100% against a fixed rubric and offers three context-aware rewrites (short, detailed, best match) or the user's original, then runs whichever the user picks. Use this whenever the user types /askright, asks to rate, score, review, check, sharpen or improve a prompt or request before Claude acts on it ("is this a good prompt?", "make my prompt better then do it", "how would you phrase this ask?"), or wants to turn the automatic prompt review on or off or change its threshold or mode. Do NOT use it when the user asks to rewrite code, text, an email, a document or a message ("rewrite this function", "rewrite this paragraph"): that is an ordinary editing task, not a prompt review. Also not for writing system prompts or prompts for other AI products.
argument-hint: "on | off | status | threshold <0-100> | mode quick|full | <your prompt>"
---

# /askright

Argument: `$ARGUMENTS`

Vague requests waste a turn: Claude guesses, the user corrects, and both start over. This skill spends a few seconds up front to show the user how clear their request is and to offer sharper versions, so the first attempt lands. The user always keeps the final say, including running their original prompt unchanged.

## Settings

Settings live in `${CLAUDE_CONFIG_DIR:-~/.claude}/askright.conf` (on Windows, `%USERPROFILE%\.claude\askright.conf`) as `key=value` lines:

| Key | Values | Default | Meaning |
|---|---|---|---|
| `enabled` | on, off | on | Whether the plugin's hook reviews every new task automatically |
| `threshold` | 0-101 | 80 | Prompts scoring at or above it run straight away; `101` always asks |
| `mode` | full, quick | full | quick offers only Best match and Use mine |

Change a setting with your file tools (Read, then Edit or Write, creating the file if missing). That works the same on macOS, Linux and Windows, unlike shell one-liners.

| Argument | Action |
|---|---|
| `on` / `off` | Set `enabled`. Reply in one line, e.g. "askright is ON (threshold 80%, mode full). Prefix a message with `raw:` to skip once." |
| `threshold N` | Set `threshold`, confirm in one line |
| `mode quick` / `mode full` | Set `mode`, confirm in one line |
| `status` or empty | Read the file; report enabled, threshold and mode (defaults when missing) and list these commands |
| anything else | Review that text as a prompt (below) |

## Reviewing a prompt

When called with a prompt, always show the picker, whatever the threshold: the user asked for a review explicitly.

1. **Gather context.** Use the conversation so far, then up to 3 quick read-only lookups (git status, Glob, Grep, CLAUDE.md, a short file) to find the real file, component and page names. Rewrites that name real files are far more useful than generic ones. Keep the lookups few and read-only; this is a pre-flight check, not the task itself.

2. **Score** with this rubric, judged against what you already know. A short prompt that is clear in context deserves a high score; the point is whether Claude could act on it without guessing.

   | Part | Points | Full marks when |
   |---|---|---|
   | Goal | 25 | The outcome is clear |
   | Target | 25 | The file, page, component or behaviour is named or obvious |
   | Context | 20 | What happens now, or what was tried, is stated |
   | Done-criteria | 20 | It says how to tell it worked |
   | Constraints | 10 | It says what must not change |

3. **Write three rewrites** in the user's language and voice, keeping their intent:
   - **Short**: 1-2 lines.
   - **Detailed**: goal, context, steps, constraints and done-criteria.
   - **Best match**: the version most likely to get the result the user wants, balancing length and precision.

   Use [bracketed placeholders] for anything you don't know. An invented detail looks authoritative and quietly sends the work the wrong way; a visible placeholder invites the user to fill it in. Score each rewrite with the same rubric.

4. **Ask** with AskUserQuestion, one question, header "Rewrite":
   - Question: "Prompt score NN% · Goal ✓ Target ✗ Context ✗ Done ✗ Constraints ✗ · <what's missing>. Which prompt should I run?"
   - Options, in order: "Best match (NN%) (Recommended)", "Short (NN%)", "Detailed (NN%)", "Use mine (NN%)". Give each a one-line description and its full prompt as the preview. In quick mode, offer only Best match and Use mine.
   - If AskUserQuestion isn't available, list the same options as numbered text and ask the user to reply with a number.

5. **Run it.** Apply any notes the user added to their choice as edits, or use their "Other" text as the prompt. Ask once for any placeholders you still can't fill. Show the final prompt in a quote headed "Running:", then carry it out.

## Example

User, in a Next.js + Tailwind repo where `src/components/Header.tsx` has uncommitted changes: `/askright fix the design issue in header`

> Prompt score 25% · Goal ✓ Target ~ Context ✗ Done ✗ Constraints ✗ · doesn't say what looks wrong or what "fixed" means. Which prompt should I run?
> - **Best match (82%) (Recommended)**: Fix the layout of src/components/Header.tsx: [what looks wrong, e.g. logo and nav overlap below 768px]. Use Tailwind, keep the current colors and links, and make it work from 320px to desktop.
> - **Short (64%)**: Fix [the overlap] in src/components/Header.tsx using Tailwind; don't change colors.
> - **Detailed (91%)**: Goal / File / Problem / Steps / Done when...
> - **Use mine (25%)**: fix the design issue in header
