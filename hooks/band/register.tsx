// askright band: one row above the prompt (Claude Code only).
//   ● Rewrite auto   rewritten 2 · as-is 5 · skipped 3
// A click on the mode cycles on -> auto -> off by writing askright.conf directly:
// no command, prompt or turn reaches the terminal, and the next prompt's
// UserPromptSubmit hook reads the new mode. The hooks keep all review logic;
// this module only shows and switches the mode and counts what happened.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Band, Mode } from './types'

const EMPTY: Band = { mode: 'auto', rewritten: 0, asIs: 0, skipped: 0, running: '' }
const band = atom({ plugin: 'askright', key: 'band' } as const, EMPTY)
const NEXT: Record<Mode, Mode> = { on: 'auto', auto: 'off', off: 'on' }

// Short replies made only of these words skip the review. Same list as the
// awk in askright-hook.sh and $replyWords in askright-hook.ps1: keep all three in sync.
const REPLY = new Set(
  ('ok okay okk okey k kk alright yes yeah yea yep yup ya y no nope nah n sure fine cool great nice perfect good awesome ' +
    'thanks thank thx ty you please pls plz go ahead on do it that this them those these all both same then now just and so ' +
    'continue proceed next done stop cancel wait hold lgtm looks sounds seems approve approved ship keep going carry ' +
    'try again retry agreed agree right correct exactly first second third one option a b c d apply let lets s ' +
    'haan han ha haa theek thik hai chalo karo kardo kar bas accha acha achha sahi hmm hm mm ' +
    'si vale claro dale listo gracias adelante perfecto bien hazlo sigue oui non daccord accord merci ' +
    'vas parfait fais le ja nein danke mach weiter genau passt gut bitte sim nao beleza ' +
    'obrigado obrigada pode isso certo faz manda va bene grazie fallo perfetto procedi nee prima dank ' +
    'je doe maar evet hayir tamam tesekkurler devam tidak oke sip lanjut terima kasih baik tak ' +
    'nie dobrze dzieki dalej').split(' '),
)

const utf8Bytes = (s: string): number => {
  let n = 0
  for (const ch of s) {
    const c = ch.codePointAt(0) ?? 0
    n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4
  }
  return n
}

// The hooks' skip rules: empty, slash command, raw:, or a short reply.
const isSkipped = (text: string): boolean => {
  const t = text.trim()
  if (t === '' || t.startsWith('/') || t.toLowerCase().startsWith('raw:')) return true
  const words = t.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(w => w !== '')
  // No ASCII words at all (Hindi, Chinese...): a task unless a few emoji/chars (> 12 UTF-8 bytes).
  if (words.length === 0) return utf8Bytes(t) <= 12
  return words.length <= 8 && words.every(w => REPLY.has(w) || /^[0-9]{1,2}$/.test(w))
}

const confPath = async ($: EngineInterface): Promise<string> => {
  const dir = await $.env.get('CLAUDE_CONFIG_DIR')
  if (dir) return `${dir}/askright.conf`
  const home = (await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE')) ?? ''
  return `${home}/.claude/askright.conf`
}

// Same reading as the hooks: mode=on|off|auto wins; else enabled=off is off; else auto.
// Keys and values are case-insensitive; a BOM and CRLF endings are ignored.
const parseMode = (text: string): Mode => {
  const conf = new Map<string, string>()
  for (const line of text.replace(/^﻿/, '').split(/\r?\n/)) {
    const i = line.indexOf('=')
    if (i > 0) conf.set(line.slice(0, i).trim().toLowerCase(), line.slice(i + 1).trim().toLowerCase())
  }
  const mode = conf.get('mode')
  if (mode === 'on' || mode === 'off' || mode === 'auto') return mode
  return conf.get('enabled') === 'off' ? 'off' : 'auto'
}

const readMode = async ($: EngineInterface): Promise<Mode> =>
  parseMode(await $.fs.read(await confPath($)).catch(() => ''))

// Writes mode=..., drops the old enabled and threshold keys, keeps every other line.
const writeMode = async ($: EngineInterface, mode: Mode): Promise<void> => {
  const path = await confPath($)
  const old = await $.fs.read(path).catch(() => '')
  const kept = old
    .replace(/^﻿/, '')
    .split(/\r?\n/)
    .filter(line => line.trim() !== '' && !/^\s*(mode|enabled|threshold)\s*=/i.test(line))
  await $.fs.write(path, [...kept, `mode=${mode}`].join('\n') + '\n')
}

const syncMode = async ($: EngineInterface) => {
  const mode = await readMode($)
  await update($, band, b => (b.mode === mode ? b : { ...b, mode }))
}

export const register: Register = on => {
  // Per turn: did a task prompt start it, and did the Rewrite picker answer it.
  let pending = false
  let picked = false

  // Every handler calls next(e) exactly once, outside its try: a counting error
  // must never block or repeat a prompt or a tool call.
  on('session.start', async ($, e, next) => {
    try {
      await syncMode($)
    } catch {}
    return next(e)
  })

  // /clear starts over: the counters reset, the mode stays.
  on('session.end', async ($, e, next) => {
    try {
      if (e.reason === 'clear') await update($, band, b => ({ ...EMPTY, mode: b.mode }))
    } catch {}
    return next(e)
  })

  // The same event the shell hooks answer, so the band counts exactly the
  // prompts they see; slash commands count as skipped.
  on('classic.UserPromptSubmit', async ($, e, next) => {
    try {
      const { mode } = await read($, band)
      if (mode !== 'off') {
        if (isSkipped(e.prompt)) {
          await update($, band, b => ({ ...b, skipped: b.skipped + 1 }))
        } else {
          pending = true
          picked = false
        }
      }
    } catch {}
    return next(e)
  })

  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    const result = await next(e)
    try {
      type Q = { question: string; header: string; options?: { label: string; preview?: string }[] }
      const out = result.result as { questions?: Q[]; answers?: Record<string, string> } | undefined
      const q = out?.questions?.find(x => x.header === 'Rewrite')
      const answer = q ? out?.answers?.[q.question] : undefined
      if (q && answer !== undefined) {
        picked = true
        const asIs = /use mine/i.test(answer)
        // The terminal shows only what the user typed: keep the prompt that actually runs
        // (the picked option's preview, or the user's own "Other" text) on screen this turn.
        const asked = (e as unknown as { questions?: Q[] }).questions?.find(x => x.header === 'Rewrite')
        const option = [...(q.options ?? []), ...(asked?.options ?? [])].find(o => o.label === answer)
        const running = (option?.preview ?? answer).replace(/\s+/g, ' ').trim()
        await update($, band, b => ({
          ...b,
          running,
          ...(asIs ? { asIs: b.asIs + 1 } : { rewritten: b.rewritten + 1 }),
        }))
      }
    } catch {}
    return result
  })

  // A task prompt that ran without the picker ran as written. The mode may have
  // changed during the turn (/askright on|off|auto edits the file), so re-read it.
  on('turn.complete', async ($, e, next) => {
    try {
      if (pending && !picked) await update($, band, b => ({ ...b, asIs: b.asIs + 1 }))
      await update($, band, b => (b.running ? { ...b, running: '' } : b))
      pending = false
      picked = false
      await syncMode($)
    } catch {}
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    // Other mods share this slot: draw theirs below ours.
    const below = await next(e).catch(() => undefined)
    const b = await read($, band)
    const { Box, Text, Button } = $.ui.resolve(e)

    const cycle = async () => {
      const mode = NEXT[b.mode]
      try {
        await writeMode($, mode)
        await update($, band, x => ({ ...x, mode }))
        $.ui.toast(
          mode === 'on'
            ? 'Rewrite on: every task prompt gets rewrites'
            : mode === 'auto'
              ? 'Rewrite auto: only prompts that would make Claude guess'
              : 'Rewrite off',
        )
      } catch {
        $.ui.toast(`Could not save the mode. Add mode=${mode} to ${await confPath($)}`)
      }
    }

    const color = b.mode === 'on' ? 'success' : b.mode === 'auto' ? 'suggestion' : 'inactive'
    const width = Math.max(20, (e.props.bodyColumns ?? 80) - 14)
    const running = b.running && b.running.length > width ? b.running.slice(0, width - 1) + '…' : b.running
    const row = (
      <Box flexDirection="row" alignItems="center" gap={2}>
        <Button key="mode" plain onPress={cycle}>
          <Text color={color}>●</Text> Rewrite {b.mode}
        </Button>
        <Text dimColor>
          rewritten {b.rewritten} · as-is {b.asIs} · skipped {b.skipped}
        </Text>
      </Box>
    )
    const mine = running ? (
      <Box flexDirection="column">
        {row}
        <Text color="suggestion">
          ▸ Running: {running}
        </Text>
      </Box>
    ) : (
      row
    )
    return below ? (
      <Box flexDirection="column">
        {mine}
        {below}
      </Box>
    ) : (
      mine
    )
  }).catch(($, e, next) => next(e))
}
