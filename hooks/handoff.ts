// handoff mod: runs the transition the checkpoint armed.
//
// classic.Stop only records the turn's cwd (Esc fires no Stop, so an aborted
// turn arms nothing). The drive runs inline from the turn.complete that follows:
// the host refuses $.command.run from a Stop hook and from any timer started
// there. The sentinel is never read here; scripts/drive-take.sh takes it and
// prints the plan, so the one parser (handoff_drive_read) stays the only one.

let stoppedIn: string | null = null

export function register(on: any) {
  on('classic.Stop', async ($: any, e: any, next: any) => {
    stoppedIn = e.cwd
    return next(e)
  })

  on('turn.complete', async ($: any, e: any, next: any) => {
    const cwd = stoppedIn
    stoppedIn = null
    if (cwd !== null) await drive($, cwd)
    return next(e)
  })
}

async function drive($: any, cwd: string) {
  const sentinel = `${cwd}/.claude/autodrive`
  // A worktree or subdir cwd falls through: the script owns root resolution.
  if (cwd === (await $.session.root()) && !(await $.fs.exists(sentinel))) return

  const out = await $.process.run(['bash', `${$.plugin.root}/scripts/drive-take.sh`, cwd])
  if (out.stdout.trim() === '') return
  const plan = JSON.parse(out.stdout)
  $.ui.toast(plan.message)

  for (const line of [...plan.before, ...plan.after]) {
    // Parity with the old composer check: never type over a person.
    if ((await $.prompt.read()).text !== '') return
    try {
      await runLine($, line)
    } catch (err: any) {
      const reason = `handoff: ${line} failed: ${err?.message ?? String(err)}`
      await $.fs.write(plan.failFile, `${reason}\n`)
      $.ui.toast(reason)
      return
    }
  }
}

async function runLine($: any, line: string) {
  if (!line.startsWith('/')) return $.prompt.submit({ text: line, asUser: true })
  const space = line.indexOf(' ')
  const command = space < 0 ? line.slice(1) : line.slice(1, space)
  const args = space < 0 ? '' : line.slice(space + 1)
  return $.command.run({ command, args })
}
