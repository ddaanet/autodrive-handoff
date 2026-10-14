// Stub rig for handoff.test.ts: answers every mods API call the mod makes and
// records them, in call order, into one log. Register before the test's first
// call on `$` (the kit rejects `on` after that).
import { FIXTURES } from './fixtures'

export const ROOT = '/work/proj'

export type Opts = {
  // cwd the session reports as its project root
  root?: string
  // answers $.fs.exists(<cwd>/.claude/autodrive)
  sentinelExists?: boolean
  // process.run stdout (a fixture name, '' for nothing armed, or raw JSON)
  stdout?: string
  // prompt box text per $.prompt.read() call; the last entry repeats
  promptTexts?: string[]
  // lines ('/name args' for command.run, the text for prompt.submit) whose call rejects
  rejectLines?: Record<string, string>
  // answers $.fs.stat on any path: a symbolic link when true, missing (ENOENT) otherwise
  statIsLink?: boolean
}

export type Rig = {
  // process.run, prompt.read, command.run, prompt.submit, fs.write, in call order
  log: string[]
  toasts: string[]
  existsPaths: string[]
  writes: { path: string; text: string }[]
  processArgv: string[][]
  statPaths: string[]
}

export function fixture(name: keyof typeof FIXTURES, root: string): string {
  return FIXTURES[name].split('@ROOT@').join(root)
}

export function rig(on: any, opts: Opts = {}): Rig {
  const root = opts.root ?? ROOT
  const r: Rig = { log: [], toasts: [], existsPaths: [], writes: [], processArgv: [], statPaths: [] }
  let reads = 0

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
  on('process.run', ($: any, e: any) => {
    r.processArgv.push(e.argv)
    r.log.push('process.run')
    return { value: { exitCode: 0, stdout: opts.stdout ?? '', stderr: '' } }
  })
  on('prompt.read', () => {
    const texts = opts.promptTexts ?? ['']
    const text = texts[Math.min(reads, texts.length - 1)]
    reads += 1
    r.log.push('prompt.read')
    return { value: { text, cursor: text.length } }
  })
  on('ui.toast', ($: any, e: any) => {
    r.toasts.push(e.text)
    return { value: undefined }
  })
  on('command.run', ($: any, e: any) => {
    const line = `/${e.command}${e.args ? ' ' + e.args : ''}`
    r.log.push(`command.run ${e.command} [${e.args ?? ''}]`)
    const why = opts.rejectLines?.[line]
    // {deny}/{drop} do not make an event-backed call reject in the kit; a throwing
    // stub is skipped, nothing beneath answers, and the mod's call rejects.
    if (why !== undefined) throw new Error(why)
    return { text: '' }
  })
  on('prompt.submit', ($: any, e: any) => {
    // the mod's {text, asUser} reaches the event as e.origin = {kind, name, asUser}
    r.log.push(`prompt.submit ${e.text} asUser=${e.origin?.asUser}`)
    const why = opts.rejectLines?.[e.text]
    if (why !== undefined) throw new Error(why)
    return { text: e.text }
  })
  return r
}
