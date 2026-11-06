import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'askright',
  component: 'AbovePrompt',
  props: { hasSurvey: false, bodyColumns: 100 },
} as const

// A fake settings file: env.get, fs.read and fs.write answered by the test.
const settings = (on: Parameters<Parameters<typeof test>[1]>[1], initial: string) => {
  const file = { text: initial, writes: 0 }
  on('env.get', (_, e) => ({ value: e.name === 'CLAUDE_CONFIG_DIR' ? '/cfg' : undefined }))
  on('fs.read', (_, e) => {
    if (!e.path.endsWith('askright.conf')) throw new Error('unexpected read ' + e.path)
    if (file.text === '') throw new Error('missing')
    return { value: file.text }
  })
  on('fs.write', (_, e) => {
    if (!e.path.endsWith('askright.conf')) throw new Error('unexpected write ' + e.path)
    file.text = e.text
    file.writes++
    return { value: undefined }
  })
  return file
}

const TURN = { answer: '', durationMs: 1, isAborted: false, turnId: 't' } as never

const rewritePick = (answer: string) => ({
  result: {
    questions: [{ question: 'Missing: target. Which prompt should I run?', header: 'Rewrite', options: [], multiSelect: false }],
    answers: { 'Missing: target. Which prompt should I run?': answer },
  },
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`shows the mode from the settings file (${surface})`, async ($, on) => {
    settings(on, 'mode=on\n')
    on('session.start', (_, e) => ({ cwd: e.cwd }))
    await $.session.start({ cwd: '/', surface, isInteractive: true } as never)
    const ui = await $.ui.mount({ ...BAND, surface } as never)
    expect((await ui.find({ key: 'mode' }))?.text).toContain('Rewrite on')
    await ui.unmount()
  })
}

// The real setup: another plugin's band (ponytail's) shares the AbovePrompt slot.
// Both rows must be drawn, ours on top, at a narrow and a wide terminal width.
for (const bodyColumns of [60, 160]) {
  test(`draws beside another plugin's band (${bodyColumns} columns)`, async ($, on) => {
    settings(on, 'mode=auto\n')
    on('session.start', (_, e) => ({ cwd: e.cwd }))
    on('ui.render', ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>other band</Text>
    })
    await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true } as never)
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal', props: { hasSurvey: false, bodyColumns } } as never)
    expect((await ui.find({ key: 'mode' }))?.text).toContain('Rewrite auto')
    expect((await ui.find({ type: 'Text', text: /other band/ }))?.text).toBe('other band')
    expect((await ui.find({ type: 'Text', text: /rewritten/ }))?.text).toBe('rewritten 0 · as-is 0 · skipped 0')
    await ui.unmount()
  })
}

test('hides while a survey is open and lets the slot through', async ($, on) => {
  settings(on, 'mode=on\n')
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>other band</Text>
  })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal', props: { hasSurvey: true, bodyColumns: 100 } } as never)
  expect(await ui.find({ key: 'mode' })).toBeFalsy()
  expect((await ui.find({ type: 'Text', text: /other band/ }))?.text).toBe('other band')
  await ui.unmount()
})

test('after a pick, shows the prompt that runs until the turn ends', async ($, on) => {
  settings(on, 'mode=auto\n')
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('classic.UserPromptSubmit', () => ({}))
  on('turn.complete', () => ({ text: '' }))
  const question = 'Missing: what looks wrong. Which prompt should I run?'
  on('tool.call', () => ({
    result: {
      questions: [{
        question, header: 'Rewrite', multiSelect: false,
        options: [
          { label: 'Best match (Recommended)', preview: 'Fix src/components/Header.tsx:\n[what looks wrong, e.g. nav overlap].' },
          { label: 'Skip, use mine', preview: 'fix the header' },
        ],
      }],
      answers: { [question]: 'Best match (Recommended)' },
    },
  }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true } as never)
  await $.classic.UserPromptSubmit({ prompt: 'fix the header' } as never)
  await $.tool.call({ tool: 'AskUserQuestion', questions: [] } as never)

  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)
  expect((await ui.find({ type: 'Text', text: /Running:/ }))?.text).toBe('▸ Running: Fix src/components/Header.tsx: [what looks wrong, e.g. nav overlap].')
  expect((await ui.find({ type: 'Text', text: /rewritten/ }))?.text).toBe('rewritten 1 · as-is 0 · skipped 0')
  await ui.unmount()

  await $.turn.complete(TURN)
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)
  expect(await ui.find({ type: 'Text', text: /Running:/ })).toBeFalsy()
  await ui.unmount()
})

test('a missing file shows auto; old enabled=off shows off', async ($, on) => {
  const file = settings(on, '')
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true } as never)
  let ui = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)
  expect((await ui.find({ key: 'mode' }))?.text).toContain('Rewrite auto')
  await ui.unmount()

  file.text = 'enabled=off\nthreshold=70\n'
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true } as never)
  ui = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)
  expect((await ui.find({ key: 'mode' }))?.text).toContain('Rewrite off')
  await ui.unmount()
})

test('a click cycles auto -> off -> on -> auto and rewrites only the mode', async ($, on) => {
  const file = settings(on, 'enabled=on\nthreshold=80\nfoo=bar\n')
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('ui.toast', () => ({ value: undefined }))
  on('prompt.submit', () => {
    throw new Error('the switch must not submit a prompt')
  })
  on('command.run', () => {
    throw new Error('the switch must not run a command')
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true } as never)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)

  await $.ui.press({ plugin: 'askright', key: 'mode' } as never)
  expect(file.text).toBe('foo=bar\nmode=off\n')
  expect(await ui.find({ key: 'mode' })).toBeTruthy()

  await $.ui.press({ plugin: 'askright', key: 'mode' } as never)
  expect(file.text).toBe('foo=bar\nmode=on\n')
  await $.ui.press({ plugin: 'askright', key: 'mode' } as never)
  expect(file.text).toBe('foo=bar\nmode=auto\n')
  expect(file.writes).toBe(3)
  await ui.unmount()
})

test('counts rewritten, as-is and skipped prompts', async ($, on) => {
  settings(on, 'mode=auto\n')
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('classic.UserPromptSubmit', () => ({}))
  on('turn.complete', () => ({ text: '' }))
  let pick = ''
  on('tool.call', () => rewritePick(pick))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true } as never)

  // A reply and a raw: prompt are skipped.
  await $.classic.UserPromptSubmit({ prompt: 'ok do it' } as never)
  await $.turn.complete(TURN)
  await $.classic.UserPromptSubmit({ prompt: 'raw: bump the version' } as never)
  await $.turn.complete(TURN)

  // A task prompt where the user picked Best match.
  pick = 'Best match (Recommended)'
  await $.classic.UserPromptSubmit({ prompt: 'fix the header' } as never)
  await $.tool.call({ tool: 'AskUserQuestion', questions: [] } as never)
  await $.turn.complete(TURN)

  // A task prompt where the user kept the original.
  pick = 'Skip, use mine'
  await $.classic.UserPromptSubmit({ prompt: 'fix the footer' } as never)
  await $.tool.call({ tool: 'AskUserQuestion', questions: [] } as never)
  await $.turn.complete(TURN)

  // A clear task prompt that ran without the picker.
  await $.classic.UserPromptSubmit({ prompt: 'rename getUser to fetchUser in src/api/users.ts' } as never)
  await $.turn.complete(TURN)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)
  const counts = await ui.find({ type: 'Text', text: /rewritten/ })
  expect(counts?.text).toBe('rewritten 1 · as-is 2 · skipped 2')
  await ui.unmount()
})
