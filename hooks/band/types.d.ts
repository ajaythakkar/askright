export type Mode = 'on' | 'auto' | 'off'

export type Band = {
  mode: Mode
  rewritten: number
  asIs: number
  skipped: number
  /** The prompt running this turn after a Rewrite pick; empty otherwise. */
  running: string
}

declare module 'claude-code' {
  interface PluginState {
    askright: { band: Band }
  }
}
