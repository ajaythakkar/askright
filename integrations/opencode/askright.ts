// askright for OpenCode: the same review as the Claude Code plugin.
// It runs the shared hook scripts (installed beside this file by install.sh) and adds
// their text to the system prompt: the rules on every request, and the latest
// prompt's note (mode + project context) while that prompt is being answered.
// Settings are shared with Claude Code: ${CLAUDE_CONFIG_DIR:-~/.claude}/askright.conf
import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join } from "node:path"

const DIR =
  process.env.ASKRIGHT_DIR ??
  join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "opencode", "askright")

// Run the hook (sh first; PowerShell on Windows without sh) and return its additionalContext.
async function runHook(args: string[], input: object): Promise<string> {
  const tries = [["sh", join(DIR, "askright-hook.sh"), ...args]]
  if (process.platform === "win32")
    tries.push(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", join(DIR, "askright-hook.ps1"), ...args])
  for (const cmd of tries) {
    try {
      const proc = Bun.spawn({ cmd, stdin: new Blob([JSON.stringify(input)]), stdout: "pipe", stderr: "ignore" })
      const out = await new Response(proc.stdout).text()
      if ((await proc.exited) !== 0) continue
      if (!out.trim()) return ""
      return String(JSON.parse(out)?.hookSpecificOutput?.additionalContext ?? "")
    } catch {
      continue
    }
  }
  return ""
}

export const AskRight: Plugin = async ({ directory }) => {
  let rules = await runHook(["session"], {})
  const notes = new Map<string, string>()

  return {
    // Each new user message: ask the hook whether it is a task (it skips replies,
    // slash commands and raw:), and keep its note for this session's next requests.
    "chat.message": async (input, output) => {
      try {
        const text = output.parts
          .filter(p => p.type === "text" && !p.synthetic)
          .map(p => (p.type === "text" ? p.text : ""))
          .join("\n")
        notes.set(input.sessionID, await runHook([], { prompt: text, cwd: directory }))
      } catch {
        notes.delete(input.sessionID)
      }
    },
    // Every model request: the rules, plus the note for the latest user message.
    "experimental.chat.system.transform": async (input, output) => {
      try {
        const note = input.sessionID ? notes.get(input.sessionID) : undefined
        // Switched on mid-session: load the rules the first time a note appears.
        if (note && !rules) rules = await runHook(["session"], {})
        if (rules) output.system.push(rules)
        if (note) output.system.push("This [askright] note belongs to the latest user message:\n" + note)
      } catch {}
    },
  }
}
