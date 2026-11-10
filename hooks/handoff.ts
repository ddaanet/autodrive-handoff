// handoff mod: runs the transition the checkpoint armed.
//
// classic.Stop only records the turn's cwd and session id (Esc fires no Stop,
// so an aborted turn arms nothing). The drive runs inline from the turn.complete that follows:
// the host refuses $.command.run from a Stop hook and from any timer started
// there. The sentinel is never read here; scripts/drive-take.sh takes it and
// prints the plan, so the one parser (handoff_drive_read) stays the only one.
// The session id goes with the cwd: drive-take.sh takes only an armed file this
// session owns, since every session sharing the root ends turns there.
//
// The plan is data: {kind, arg, continue, failFile, message}. Everything this
// mod can run is in this file: commandsFor() maps the kind to /rename, /clear
// and /compact, the plan's arg is only their free-text argument, and CONTINUATION
// is the one prompt, submitted when the plan's continue flag is true. No
// command name and no prompt text is read from the plan or from disk, so a
// plan can reach nothing else (docs/design/driving-the-transition.md).
//
// A prompt a person sends after the Stop and before the transition command is
// issued would be answered in a context the transition then discards. The
// window takes once, at the first of turn.complete or such a prompt; the
// prompt.submit handler asks scripts/drive-cancel.sh, once per window, to cancel
// the clear or compact that take left pending, and the drive checks the cancel
// before each command it issues (docs/design/queued-prompts.md).

// The one prompt this mod submits, after a driven transition whose plan says
// continue. tests/test_mod_fixtures.py pins it to HANDOFF_CONTINUATION in
// scripts/_lib_drive.sh, which the sweep's offer renders.
const CONTINUATION = 'Continue where the previous context stopped.'

// One window per Stop: it opens at classic.Stop (`stopped`), turn.complete moves
// it to `driving` and hands it to drive(), and it closes when the transition
// command is issued or the drive ends. A prompt typed while it is open would be
// answered in a context the transition then discards. `plan` is the window's one
// take, made by whichever of turn.complete or a prompt in the window comes
// first; `cancelled` is its one drive-cancel answer, made only for a clear or
// compact that take moved to pending, null when nothing was cancelled
// (docs/design/queued-prompts.md). A later turn's Stop can open the next window
// before this drive ends, so a drive touches only its own, and a later window's
// take finds this one's file pending and takes nothing.
// A Stop another plugin's hook blocked leaves the window open while the turn
// goes on, and the next Stop replaces it (a bound, in the same node).
type Window = {
  cwd: string
  session: string
  plan: Promise<any | null> | null
  cancelled: Promise<any | null> | null
}
let stopped: Window | null = null
let driving: Window | null = null

export function register(on: any) {
  on('classic.Stop', async ($: any, e: any, next: any) => {
    stopped = { cwd: e.cwd, session: e.session_id ?? '', plan: null, cancelled: null }
    return next(e)
  })

  on('turn.complete', async ($: any, e: any, next: any) => {
    const w = stopped
    stopped = null
    if (w !== null) {
      driving = w
      try {
        await drive($, w)
      } finally {
        if (driving === w) driving = null
      }
    }
    return next(e)
  })

  on('prompt.submit', async ($: any, e: any, next: any) => {
    const w = stopped ?? driving
    if (w === null || e.command || e.isMeta) return next(e)
    // Set before anything is awaited, so the drive loop waits for this answer.
    const first = w.cancelled === null
    if (first) w.cancelled = cancelTaken($, w)
    const answer = await w.cancelled
    if (!first || !answer?.note) return next(e)
    $.ui.toast(answer.message)
    return next({ ...e, context: [...(e.context ?? []), answer.note] })
  })
}

// The window's one take: the promise of drive-take.sh's plan, or null when it
// printed nothing. Started by the first caller, synchronously, so the second
// awaits the same spawn.
function take($: any, w: Window): Promise<any | null> {
  if (w.plan === null) w.plan = runTake($, w.cwd, w.session)
  return w.plan
}

async function runTake($: any, cwd: string, session: string): Promise<any | null> {
  // A worktree or subdir cwd falls through: the script owns root resolution.
  if (cwd === (await $.session.root()) && !(await $.fs.exists(`${cwd}/.claude/autodrive`))) return null
  const out = await $.process.run(['bash', `${$.plugin.root}/scripts/drive-take.sh`, cwd, session])
  if (out.stdout.trim() === '') return null
  return JSON.parse(out.stdout)
}

// The cancel {kind, message, note} of the window's own take, made only when
// that take left a clear or compact pending; null when it took anything else,
// or drive-cancel.sh printed nothing, or anything failed: the sweep and the
// drive then behave as without it.
async function cancelTaken($: any, w: Window): Promise<any | null> {
  try {
    const plan = await take($, w)
    if (plan?.kind !== 'clear' && plan?.kind !== 'compact') return null
    const out = await $.process.run(['bash', `${$.plugin.root}/scripts/drive-cancel.sh`, w.cwd, w.session, plan.kind])
    if (out.stdout.trim() === '') return null
    return JSON.parse(out.stdout)
  } catch {
    return null
  }
}

async function drive($: any, w: Window) {
  const plan = await take($, w)
  if (plan === null) return
  if (w.cancelled !== null && (await w.cancelled)?.note) return
  const { session } = w
  $.ui.toast(plan.message)
  // A Stop with no session id: drive-take.sh took nothing and said so. Recorded
  // like a rejected command, so the next prompt reports it rather than it passing
  // as a toast alone.
  if (session === '' && plan.failFile) {
    await recordFailure($, plan.failFile, plan.message)
    return
  }

  const steps = commandsFor(plan.kind, typeof plan.arg === 'string' ? plan.arg : '')
  for (let i = 0; i < steps.length; i++) {
    const { command, args } = steps[i]
    // Read before any yield: with no prompt yet, nothing is awaited between
    // this read and issuing the command.
    if (w.cancelled !== null && (await w.cancelled)?.note) return
    // The window closes as the last command is issued: a prompt after it is
    // held by the host and answered in the new context, and the sentinel must
    // stay pending for the loader.
    if (i === steps.length - 1 && driving === w) driving = null
    try {
      await $.command.run({ command, args })
    } catch (err: any) {
      await reportFailure($, plan.failFile, `/${command}${args === '' ? '' : ` ${args}`}`, err)
      return
    }
  }
  if (plan.continue === true && steps.length > 0) {
    try {
      await $.prompt.submit({ text: CONTINUATION, asUser: true })
    } catch (err: any) {
      await reportFailure($, plan.failFile, CONTINUATION, err)
    }
  }
}

// What the mod runs for a plan's kind: literal command names, the plan's arg as
// the free-text argument where the kind takes one. Every other kind, null and
// the prepare marker included, runs nothing.
function commandsFor(kind: unknown, arg: string): { command: string; args: string }[] {
  switch (kind) {
    case 'rename':
      return [{ command: 'rename', args: arg }]
    case 'clear':
      return [{ command: 'rename', args: arg }, { command: 'clear', args: '' }]
    case 'compact':
      return [{ command: 'compact', args: arg }]
    default:
      return []
  }
}

async function reportFailure($: any, failFile: string, what: string, err: any) {
  const reason = `handoff: ${what} failed: ${err?.message ?? String(err)}`
  if (await recordFailure($, failFile, reason)) $.ui.toast(reason)
}

// Writes the failure record for the next prompt's report. $.fs.write follows a
// link and has no replace-not-follow form, so a link at the name, dangling or
// not, is checked for first (one stat; a missing file rejects it) and not
// written through: the toast then says the record was skipped. A link put
// there between the stat and the write is still followed — the bound, in a
// project directory the user trusts. Returns false when it toasted instead.
async function recordFailure($: any, failFile: string, text: string): Promise<boolean> {
  const st = await $.fs.stat(failFile).catch(() => undefined)
  if (st?.isLink) {
    $.ui.toast(`${text} (not recorded: ${failFile} is a symbolic link)`)
    return false
  }
  await $.fs.write(failFile, `${text}\n`)
  return true
}
