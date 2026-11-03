// Stub rig for the mod tests (handoff.test.ts, window.test.ts): answers every mods API call the mod makes and
// records them, in call order, into one log. Register before the test's first
// call on `$` (the kit rejects `on` after that).
import { FIXTURES } from './fixtures'

export const ROOT = '/work/proj'

export type Opts = {
  // cwd the session reports as its project root
  root?: string
  // answers $.fs.exists(<cwd>/.claude/autodrive)
  sentinelExists?: boolean
  // drive-take.sh's stdout ('' for nothing armed, or raw JSON); a list answers
  // the successive takes in order, the last one repeating
  stdout?: string | string[]
  // lines ('/name args' for command.run, the text for prompt.submit) whose call rejects
  rejectLines?: Record<string, string>
  // drive-cancel.sh's stdout ('' for nothing to cancel, or raw JSON)
  cancelStdout?: string
  // drive-cancel.sh's spawn rejects
  cancelRejects?: boolean
  // hold the named script's answer open until release.<script>() is called
  hold?: { take?: boolean; cancel?: boolean }
  // command.run lines ('/name args') whose call stays in flight until
  // release.line(<line>), or release.line() for all of them
  holdLine?: string | string[]
  // the text of a prompt.submit whose stub stays in flight until release.submit()
  holdSubmit?: string
  // answers $.fs.stat on any path: a symbolic link when true, missing (ENOENT) otherwise
  statIsLink?: boolean
}

export type Rig = {
  // process.run, command.run, prompt.submit, fs.write, in call order
  log: string[]
  toasts: string[]
  existsPaths: string[]
  writes: { path: string; text: string }[]
  // drive-take.sh spawns
  processArgv: string[][]
  // drive-cancel.sh spawns
  cancelArgv: string[][]
  // what the prompt.submit stub beneath the mod received
  submitted: { text: string; context: string[] }[]
  // lets a held spawn answer
  release: { take: () => void; cancel: () => void; line: (line?: string) => void; submit: () => void }
  statPaths: string[]
}

// The turn ends: Stop records, then turn.complete drives (cwd null: no Stop).
export async function endTurn($: any, cwd: string | null = ROOT, turnId = 't1') {
  if (cwd !== null) await $.classic.Stop({ cwd, session_id: 's1' })
  return $.turn.complete({ turnId, answer: 'ok', durationMs: 1, isAborted: false, usage: null })
}

export function fixture(name: keyof typeof FIXTURES, root: string): string {
  return FIXTURES[name].split('@ROOT@').join(root)
}

export function rig(on: any, opts: Opts = {}): Rig {
  const root = opts.root ?? ROOT
  const r: Rig = {
    log: [], toasts: [], existsPaths: [], writes: [], processArgv: [], cancelArgv: [], submitted: [],
    release: { take: () => {}, cancel: () => {}, line: () => {}, submit: () => {} }, statPaths: [],
  }
  const held: Record<string, Promise<void>> = {}
  let takes = 0
  // One gate per listed line, in order: the nth call of a line takes the nth gate
  // listed for it, and calls beyond the list pass through.
  const gates: { line: string; open: () => void; wait: Promise<void>; taken: boolean }[] = []
  for (const line of [opts.holdLine ?? []].flat()) {
    const g = { line, open: () => {}, wait: Promise.resolve(), taken: false }
    g.wait = new Promise<void>((res) => { g.open = res })
    gates.push(g)
  }
  // release.line(<line>) opens the earliest unreleased gate of that line;
  // release.line() opens all of them.
  const opened = new Set<object>()
  r.release.line = (line?: string) => {
    for (const g of gates) {
      if (opened.has(g) || (line !== undefined && g.line !== line)) continue
      opened.add(g)
      g.open()
      if (line !== undefined) return
    }
  }
  let heldSubmit: Promise<void> | null = null
  if (opts.holdSubmit !== undefined) heldSubmit = new Promise<void>((res) => { r.release.submit = res })
  for (const k of ['take', 'cancel'] as const) {
    if (opts.hold?.[k]) held[k] = new Promise<void>((res) => { r.release[k] = res })
  }

  on('classic.Stop', () => ({}))
  on('turn.complete', () => ({ text: '' }))
  on('session.root', () => ({ value: root }))
  on('session.cwd', () => ({ value: root }))
  on('fs.exists', ($: any, e: any) => {
    r.existsPaths.push(e.path)
    return { value: opts.sentinelExists ?? false }
  })
  on('fs.stat', ($: any, e: any) => {
    r.statPaths.push(e.path)
    // a throwing stub makes the mod's call reject, as a missing path does
    if (!opts.statIsLink) throw new Error('ENOENT')
    return { value: { kind: 'other', size: 0, mtimeMs: 0, isLink: true } }
  })
  on('fs.write', ($: any, e: any) => {
    r.writes.push({ path: e.path, text: e.text })
    r.log.push(`fs.write ${e.path}`)
    return { value: undefined }
  })
  // Routed on the script's name: drive-cancel.sh is logged apart ('process.run
  // cancel') so the take's rows keep their 'process.run'.
  on('process.run', async ($: any, e: any) => {
    if (e.argv[1].endsWith('/drive-cancel.sh')) {
      r.cancelArgv.push(e.argv)
      r.log.push('process.run cancel')
      if (held.cancel) await held.cancel
      if (opts.cancelRejects) throw new Error('spawn failed')
      return { value: { exitCode: 0, stdout: opts.cancelStdout ?? '', stderr: '' } }
    }
    r.processArgv.push(e.argv)
    r.log.push('process.run')
    if (held.take) await held.take
    const out = Array.isArray(opts.stdout) ? opts.stdout[Math.min(takes, opts.stdout.length - 1)] : (opts.stdout ?? '')
    takes++
    return { value: { exitCode: 0, stdout: out, stderr: '' } }
  })
  on('ui.toast', ($: any, e: any) => {
    r.toasts.push(e.text)
    return { value: undefined }
  })
  on('command.run', async ($: any, e: any) => {
    const line = `/${e.command}${e.args ? ' ' + e.args : ''}`
    r.log.push(`command.run ${e.command} [${e.args ?? ''}]`)
    const gate = gates.find((g) => g.line === line && !g.taken)
    if (gate) {
      gate.taken = true
      await gate.wait
    }
    const why = opts.rejectLines?.[line]
    // {deny}/{drop} do not make an event-backed call reject in the kit; a throwing
    // stub is skipped, nothing beneath answers, and the mod's call rejects.
    if (why !== undefined) throw new Error(why)
    return { text: '' }
  })
  on('prompt.submit', async ($: any, e: any) => {
    // the mod's {text, asUser} reaches the event as e.origin = {kind, name, asUser}
    r.log.push(`prompt.submit ${e.text} asUser=${e.origin?.asUser}`)
    r.submitted.push({ text: e.text, context: e.context ?? [] })
    if (heldSubmit && e.text === opts.holdSubmit) await heldSubmit
    const why = opts.rejectLines?.[e.text]
    if (why !== undefined) throw new Error(why)
    return { text: e.text }
  })
  return r
}
