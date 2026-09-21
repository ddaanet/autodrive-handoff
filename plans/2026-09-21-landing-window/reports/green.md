# GREEN — the landing window is sized by the boot, not the settle

2026-09-21. `HANDOFF_WATCHER_BOOT_SETTLE` is gone from the code, the tests and
the environment; the wait it bought moved behind the send, where it is the
line's landing window rather than a sleep in front of the gate.

Final state: `just precommit` fully green — **283 passed, 13 deselected** in
pytest, **170 bats rows**, every lint clean.

## The return shape

`wait_for_composer(pane, timeout=None) -> tuple[bool, bool]`, destructured at
its one call site as `opened, booting = wait_for_composer(pane)`.

Two independent booleans, each with a name at the call site, and no new type to
import or teach mypy/ty about. The alternatives weighed: `bool | None` (timeout
as `None`) inverts the existing `if not wait_for_composer(pane)` into a
truthiness trap where `False` and `None` mean opposite things; a `Literal`
string or an enum buys a third state the caller does not have — on timeout the
composer was definitionally absent, so `booting` is not undefined there, and
the tuple says so (`(False, True)`) without a state nobody reads.

`wait_for_landing(pane, line, *, booting: bool)` picks its own tunable from
that flag — `HANDOFF_WATCHER_BOOT_LANDING_DELAY` (30.0) or
`HANDOFF_WATCHER_LANDING_DELAY` (3.0). Keyword-only because ruff's FBT001
refuses a positional boolean, and the keyword reads better at the call site
anyway. The tunables stay inside the library beside every other one rather than
being resolved by the caller: "the window the caller picks" is the branch, not
the number.

## Files touched

- `/Users/david/code/handoff/scripts/_watcher_lib.py` — `wait_for_composer`
  returns the pair and no longer sleeps (`settle` local and its `_env_float`
  read deleted); its closing docstring paragraph replaced by what the cursor
  gate actually protects against. `wait_for_landing` takes `booting` and
  selects the window; its docstring gains the paragraph arguing the two
  windows.
- `/Users/david/code/handoff/scripts/drive_when_idle.py` — `_drive_line`
  destructures the gate, stamps `sent` after `_send_literal`, passes `booting`
  to `wait_for_landing`, and drops `"settle"` from the `watcher_log` record.
  The failure message now reads `` `<line>` did not land in the composer
  <n>s after it was typed. The composer held:…`` — the substring `did not land
  in the composer` is preserved, and the time is now measured from the send
  rather than from a gate stamp taken after a sleep. Three comments rewritten:
  the send (why it is prompt), the landing poll (why the window varies), and
  the `watcher_log` preamble (`gate` alone is the boot; `landed` carries the
  buffer delay `BOOT_LANDING_DELAY` is sized against).
- `/Users/david/code/handoff/tests/test_drive_when_idle.py` — `walk()`'s
  `HANDOFF_WATCHER_BOOT_SETTLE: "0.01"` removed; row 1's own `"5"` override
  kept, as the evidence the variable is inert. One docformatter reflow of the
  guard row's docstring (the gate wanted a rewrap; no wording changed).
- `/Users/david/code/handoff/tests/test_watcher_lib.py` — three new rows
  pinning the return, replacing nothing (there were no `wait_for_composer` rows
  before): already-reading → `(True, False)`, absent-then-present →
  `(True, True)`, never-appears → `(False, True)`. Needed `threading` and
  `time` imports.
- `/Users/david/code/handoff/tests/test_tui_conformance.py` — the measuring
  row's docstring said the number "sizes the gate's settle on this box"; it now
  says it sizes `BOOT_LANDING_DELAY`, and names the marker count beside it as
  what says the gap is a paint and not a loss. Live-only, not run. No env or
  code reference to the settle existed there.

`grep -rn 'BOOT_SETTLE' scripts/ tests/ bin/ hooks/ justfile` returns only
`tests/test_drive_when_idle.py:915`, the deliberate inert override.

## Mutation check

Made the boot window unconditional (`delay =
_env_float("HANDOFF_WATCHER_BOOT_LANDING_DELAY", 30.0)`, the branch deleted):

```
FAILED tests/test_drive_when_idle.py::test_a_mid_session_line_keeps_the_short_landing_window
E   AssertionError: assert 'did not land' in 'the continuation prompt was typed
    but three enters did not submit it\n'
1 failed, 92 passed
```

That row alone reds — the line lands inside the widened window and the failure
moves past `did not land` to the confirmation stage. Reverted; re-run green.

## Gate

`cd /Users/david/code/handoff && just precommit`, checks in order, all passing:

```
jq . .claude-plugin/plugin.json          jq . hooks/hooks.json
jq . .claude/settings.json               shellcheck -x .bin/* bin/* scripts/*.sh tests/*.bats
ruff check scripts tests                 → All checks passed!
ruff format --check scripts tests        → 11 files already formatted
docformatter --check scripts/*.py tests/*.py
mypy                                     ty check → All checks passed!
bats tests/hook-test.bats tests/checkpoint.bats  → 170 rows ok
pytest                                   → 283 passed, 13 deselected in 78.62s
```

No sandbox effects. (`git status` inside the sandbox lists `.bashrc`,
`.gitconfig`, `.mcp.json` and friends as untracked in the repo root; they are
`/dev/null` character devices the sandbox mounts, not files, and not this
dispatch's doing.)

## Remaining mentions of the settle, for the prose dispatch

Deliberately left — every one is prose, and prose is a later dispatch.

Must change (they assert the settle as current mechanism):

- `CLAUDE.md:306` — "plus a `BOOT_SETTLE` residual when it was not already
  there"
- `CLAUDE.md:361` — "`HANDOFF_WATCHER_BOOT_SETTLE` covers the painted-but-not-
  reading window… measured at 3 to 9 seconds… its 10s default is a bound on
  this box's load"
- `CLAUDE.md:414-415` — "plus the `settle` in force, so `gate` minus `settle`
  is how long a real boot took to start reading"
- `CLAUDE.md:1120` — the conformance row: "that number is what sizes
  `HANDOFF_WATCHER_BOOT_SETTLE`"
- `CLAUDE.md:1148` — the timing-record row: "the settle in force, a `gate` that
  saw the staged delay"
- `docs/design/driving-the-tui.md:179-181` — "`HANDOFF_WATCHER_BOOT_SETTLE` — a
  bounded residual…", and the sentence at 181 rejecting a wider `LANDING_DELAY`
  ("Widening `LANDING_DELAY` instead would only…"), which this change reverses
  for the boot case
- `docs/design/driving-the-tui.md:190-192` — the timing record's `settle` key
  and "`gate` minus `settle`… the number the settle is sized against"
- `docs/changelog.md:11` — the 2026-09-20 index line ends on the settle and on
  "widening `LANDING_DELAY` was weighed and rejected"

Write-time records, so a `> **Superseded 2026-09-21**` blockquote rather than
an edit:

- `docs/changelog/2026-09-20-the-boot-gate-asks-where-the-cursor-is.md` —
  lines 74, 85 (the rejected `LANDING_DELAY` widening), 97, 105, 117, 124,
  130-131, 144, 156
- `docs/changelog/2026-08-15-continuation-waits-for-the-composer-to-exist.md:49`
  — inside an existing superseded blockquote, which now names a mechanism that
  is gone
- `plans/2026-09-20-restart-continuation-non-delivery.md:211,214` — the brief
  that proposed `HANDOFF_WATCHER_BOOT_SETTLE` and deferred widening
  `LANDING_DELAY` to step 4. A plan, so frozen; its step 4 is what landed.

Untouched on purpose — a different settle, still current: `SHELL_SETTLE`
(`CLAUDE.md:1133`, `docs/changelog/2026-08-10-restart-transition-kind.md:45`),
the paste-window settle before Enter (`CLAUDE.md:314`,
`memory/cc-tui-tmux-driving.md:49`), the post-transition queueing settle
(`CLAUDE.md:394`, `docs/changelog/2026-07-22-submit-signal-queued-
continuation.md:49`, `docs/changelog/2026-08-13-first-driven-transition-
lands.md:25`), and `docs/changelog/2026-07-20-settle-gap-and-submit-signal.md`
entire.
