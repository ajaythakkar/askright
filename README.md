# askright

Rates your prompt before Claude Code starts work, and offers better versions when it is vague.

```
> fix the design issue in header

Prompt score 25% · Goal ✓ Target ~ Context ✗ Done ✗ Constraints ✗ · doesn't say what looks wrong
  ❯ Best match (82%) (Recommended)   Fix the layout of src/components/Header.tsx: [what looks wrong]...
    Short (64%)                      Fix [the overlap] in src/components/Header.tsx using Tailwind...
    Detailed (91%)                   Goal / File / Problem / Steps / Done when...
    Use mine (25%)
    Other                            type your own version
```

- **Clear prompts run straight away.** At or above the threshold (80% by default) you just see a one-line score.
- **Vague prompts get a picker** with three rewrites: Short (1-2 lines), Detailed (goal, context, steps, constraints, done-criteria) and Best match, plus your original. Add notes to any option to edit it, or choose **Other** to type your own.
- **Rewrites use your context:** the conversation, git branch, changed files, recent commits and detected stack, plus up to 3 quick read-only lookups, so they name real files.
- **Replies are never reviewed:** "ok do it", "yes please continue", "looks good, go ahead", "option 2", "haan kar do".
- **Consistent scoring** with a fixed rubric: Goal 25, Target 25, Context 20, Done-criteria 20, Constraints 10.

## Install

### Claude Code plugin (automatic review on every prompt)

```
/plugin marketplace add ajaythakkar/askright
/plugin install askright@askright-marketplace
```

Restart Claude Code afterwards.

### Skill only (on-demand `/askright <prompt>`, works with other agents too)

```
npx skills add ajaythakkar/askright
```

The skill alone has no hook, so it reviews only when you call it.

## Commands

| Command | What it does |
|---|---|
| `/askright on` / `/askright off` | Turn the automatic review on or off (on by default) |
| `/askright threshold 70` | Prompts scoring 70%+ run without the picker. `101` = always ask |
| `/askright mode quick` | Picker shows only Best match and Use mine |
| `/askright mode full` | Picker shows all four options (default) |
| `/askright status` | Show current settings |
| `/askright <prompt>` | Review this prompt now, even when off |
| `raw: <prompt>` | Skip the review for one message |

Settings are stored in `~/.claude/askright.conf`.

## Works on

| System | How the hook runs |
|---|---|
| macOS, Linux, WSL | bash |
| Windows with Git for Windows | Git Bash |
| Windows without Git Bash | PowerShell (5.1 or 7) |

One hook command covers all of these: it is valid in both bash and PowerShell, and each shell runs its own version of the hook (`hooks/askright-hook.sh` or `hooks/askright-hook.ps1`). Nothing else needs installing: no Python, Node or jq. Both versions are tested on Linux, macOS and Windows in CI.

## Development

```
bash tests/hook-test.sh                  # bash hook: skip/review, settings, context
HOOK_PS=pwsh bash tests/hook-test.sh     # same tests against the PowerShell hook
bash tests/dual-shell-test.sh            # hooks.json command under every installed shell
claude plugin eval skills/askright --scaffold --allow-tools Write,Edit,Bash   # skill evals (real model runs)
claude plugin validate .       # manifest checks
claude --plugin-dir . -p "fix the header"   # try it without installing
```

## License

MIT
