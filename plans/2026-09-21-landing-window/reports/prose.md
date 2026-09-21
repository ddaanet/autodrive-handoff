# PROSE — the landing window is sized by the boot, not a settle

2026-09-21. Documentation only: no behaviour changed in `scripts/` or `tests/`.
The two `scripts/_watcher_lib.py` edits are docstring bodies (proved inert —
see "The one gate failure" below). `plugin.json`'s `.version` untouched.

`just precommit`: **283 passed, 14 deselected** in pytest, **170 bats rows**,
every lint clean.

## The new entry

`/Users/david/code/handoff/docs/changelog/2026-09-21-the-landing-window-is-sized-by-the-boot.md`
— **The landing window is sized by the boot, not a settle**

Sections: the defect (the 2026-09-20 measuring row stopped at the first marker
and never counted the rest, so a paint delay read as discarded keystrokes; and
`gate_opened` was stamped after the sleep, hiding it); the fix (`(opened,
booting)`, the send at the gate, the two landing windows, the record dropping
`settle`); "The gate now rests on two grounds" carrying the live measurement as
measured — the discrete 1–1.5s band at 1.7–3.3s, closing ~2s *before* the
alternate-screen switch and 2.5–3.7s before the gate, with what bounds it
unidentified and every gate-held marker landing in order 3/3 runs; "What
2026-09-20 got right" naming the stale-glyph diagnosis, `cursor_in_composer`,
the composer-quoting failure message and `watcher_log`; alternatives weighed
(the uniform widening, a shorter settle, the parked readiness probe); and the
open residual, stated as undecided.

Index line added at the top of `/Users/david/code/handoff/docs/changelog.md`,
in the existing one-physical-line format. The 2026-09-20 index line is
**untouched** — the repo's precedent is that index lines are write-time records
too (2026-08-15's still describes the glyph-presence gate, and
2026-08-14-relaunch-through-the-shim's still describes the argv replay, both
superseded).

## Superseded / Corrected blockquotes

All five in
`docs/changelog/2026-09-20-the-boot-gate-asks-where-the-cursor-is.md`, each
scoped, each heading the section it qualifies:

| heads | scope |
|---|---|
| `## What was measured` | the *reading* of the table, not the table — the row never counted the markers sent before the first paint. The four timings stand, as timings of the paint. |
| `## The fix` | `HANDOFF_WATCHER_BOOT_SETTLE` alone, deleted. The cursor predicate and its two-readings rule are unchanged. |
| `## Alternatives weighed` | the three bullets that turn on the settle. Raising `LANDING_DELAY` is what landed, boot branch only; the argument against it is a true reading of *that* incident. The retype refusal is untouched. |
| `## Dogfooded` | the record's `settle` key. `watcher_log`, its four other figures, the bounded file and the untested exports stand. |
| `## Residual` | the two paragraphs about the settle's sizing, including the keep-one-drop-the-next observation, which was the uncounted reading again. The report wording, the printed-not-pinned rule and the wrap row stand. |

`docs/changelog/2026-08-15-continuation-waits-for-the-composer-to-exist.md:49`
— its existing 2026-09-20 blockquote ended on "plus a bounded settle", so a
`Superseded again 2026-09-21 … on the settle alone` sentence is appended
*inside* that blockquote, following this repo's own precedent at
`2026-05-19-original-activation-and-loading.md:8`. The write-time prose below
it is untouched.

`plans/2026-09-20-restart-continuation-non-delivery.md` — **no `Corrected at
review` added, deliberately.** Its two settle passages are step 3 (propose
`HANDOFF_WATCHER_BOOT_SETTLE`) and step 4 (defer widening `LANDING_DELAY`):
proposals that were later superseded, which the repo's rule says is not a
correction. Hypothesis (b) at line 104 is labelled a hypothesis. Hypothesis (c)
at 113–119 argues that raising `LANDING_DELAY` alone would not have delivered
*that* line — true when written and still true, since the 2026-09-20 line was
typed into the loss window through a gate the stale glyph had opened. The
"discards keystrokes" reading the brief asked about is not in the plan; it is
in the 2026-09-20 changelog entry, where it takes a Superseded blockquote
instead.

## Files touched

- `docs/changelog/2026-09-21-the-landing-window-is-sized-by-the-boot.md` — new.
- `docs/changelog.md` — one index line.
- `docs/changelog/2026-09-20-the-boot-gate-asks-where-the-cursor-is.md` — five
  blockquotes, no prose edited.
- `docs/changelog/2026-08-15-continuation-waits-for-the-composer-to-exist.md` —
  one appended blockquote sentence.
- `docs/design/driving-the-tui.md` — the cursor-gate paragraph rewritten
  present-tense (no dated narrative, and it no longer claims the exited
  session's frame is a glyph source); a new paragraph giving the gate's two
  grounds with the measured loss band; a residual paragraph; a new
  `## Two landing windows` section carrying `(opened, booting)`, the two
  tunables and why they are not one window widened; the `watcher_log`
  paragraph's key list corrected to four keys with `gate`/`landed` explained.
- `docs/design.md` — `Last updated:` stamp only. Grepped: neither the hub,
  `docs/design/decisions.md` nor `docs/design/rejected-alternatives.md`
  mentioned the settle or the rejected `LANDING_DELAY` widening. The only
  `SHELL_SETTLE` hits there are the other, still-current settle.
- `CLAUDE.md` — five passages, below.
- `scripts/_watcher_lib.py` — two docstrings, below.
- `memory/cc-tui-tmux-driving.md`, `memory/cc-boot-input-window.md` (new),
  `memory/MEMORY.md` — below.

## green.md's list, item by item

Every "must change" item is done:

- `CLAUDE.md:306` — the `BOOT_SETTLE` residual clause replaced by
  `wait_for_composer` returning `(opened, booting)`; the same bullet now says
  the send happens the moment the gate opens and that `wait_for_landing` takes
  `booting=`, and cites the new changelog entry beside the other two.
- `CLAUDE.md:361` — the `wait_for_composer` scaffold entry rewritten: the
  glyph's source is replayed text, **not** the exited frame (probed, CC
  2.1.278, and the tension with 2026-09-20's "on screen from the first moment"
  is stated rather than resolved); the loss band and the buffering are given as
  measured; the `❯`-below-cursor residual is named. `wait_for_landing`'s entry
  one line up gained the two windows and why they are not one.
- `CLAUDE.md:414` — the `watcher_log` key list: `gate`, `idle`, `landed`,
  `confirmed` "and nothing else", with `gate` as the boot and `landed` as the
  buffer delay `BOOT_LANDING_DELAY` is sized against.
- `CLAUDE.md:1120` — the conformance rows: "Two rows (2026-09-20)" → three
  rows over a `resuming_pane` fixture whose staged previous screen is a
  parameter; the measuring row now sizes `BOOT_LANDING_DELAY` and prints its
  marker count; the new row
  `test_only_keystrokes_ahead_of_the_boot_gate_are_lost[post-exit-screen]` is
  described with what it asserts vs. prints, and why it is parametrized onto a
  glyph-free screen while the default is kept for the other two.
- `CLAUDE.md:1148` — the timing-record row: the exact key set
  (`at`/`line`/`gate`/`idle`/`landed`/`confirmed`, no `settle`), and its
  ordinal corrected from "ninth" to "eleventh", which is the count the brief
  asked about — the two new offline rows land ahead of it in the file.
- `docs/design/driving-the-tui.md:179-181` and `:190-192` — both rewritten, as
  above.
- `docs/changelog.md:11` — left as written; see "The new entry".

Also added to CLAUDE.md beyond the list: the two new offline rows (the
late-paint boot row, and the mid-session guard row with its mutation check
spelled out), and the three `wait_for_composer` return rows in
`tests/test_watcher_lib.py` with why the second boolean is load-bearing.

Deliberately left, all still current and all a different settle:
`SHELL_SETTLE` (`CLAUDE.md`, `2026-08-10-restart-transition-kind.md`), the
paste-window settle before Enter, the post-transition queueing settle, and
`2026-07-20-settle-gap-and-submit-signal.md` entire. The `BOOT_SETTLE` hits
remaining in `tests/` are the deliberate inert override and the prose about it.

## Docstrings

`scripts/_watcher_lib.py`, wording only:

- `wait_for_composer` — the paragraph claiming the keystrokes are "eaten by the
  screen switch" and lost "before the TUI's first paint" on "the terminal's raw
  screen" now states what was measured: a discrete band 1–1.5s wide at
  1.7–3.3s, keystrokes either side kept, closing ~2s before the
  alternate-screen switch and 2.5–3.7s before the gate, with what bounds it
  unidentified. The `aoeuidhtnsaoe`/`aoeunsaoe` evidence and the closing
  "the wait belongs to the line" sentence are kept.
- `cursor_in_composer` — "in the previous session's last frame" dropped from
  the never-has-the-cursor list (the probe says that frame does not survive),
  and a two-sentence `Residual:` paragraph added for the below-the-glyph case.

`wait_for_landing`'s new docstring paragraph was left as GREEN wrote it: its
"3 to 9s past the cursor" is the *paint* delay and is stated as such, which is
accurate.

## Memory

The single file could not hold both facts under the cap — it was **5967 bytes**
before this pass, so roughly a third of it already sat past the 4KB recall
cutoff, with the boot material in the invisible tail. Compressed as far as it
goes without dropping facts it landed at 4702. So it is **split**, which the
memory hook also directed and which drops nothing:

- `memory/cc-boot-input-window.md` — **new, 2564 bytes**. The boot/resume
  input window as one fact: readiness ≠ the `❯` glyph (and the 3.9s bare
  launch), the cursor-in-composer gate with the below-the-glyph residual, the
  discrete loss band with the alternate-screen timing, buffered-not-lost from
  the cursor on with its three consequences, and that a real `/exit` leaves no
  `❯` (CC 2.1.278). Links `[[cc-tui-tmux-driving]]`.
- `memory/cc-tui-tmux-driving.md` — **3666 bytes** (was 5967). Keeps the
  running-TUI facts, compressed throughout: the four mid-turn classes, the hook
  chain, Esc, command recognition, busy detection, the absorbed Enter, and
  never confirming a submit by reading the pane. The two boot bullets become
  one line pointing at `[[cc-boot-input-window]]`. The `/compact`
  double-recording section and the `display-popup` gotcha fold into bullets.
  Dropped only genuinely dead wording: the "supersedes the 2026-07-18 pass"
  narrative and the reference to `_rename-lib.sh`, a file that no longer
  exists.
- `memory/MEMORY.md` — the `cc-tui-tmux-driving` line rescoped to the running
  TUI, plus a new line for `cc-boot-input-window` whose hook is the symptom a
  session arrives holding ("keystrokes … don't show in the composer though `❯`
  is up"). gitlore's index→frontmatter sync rewrote both `description:` lines
  from the index, as expected.

No commit ids or other volatile state; "my human partner" is used nowhere in
these files because neither needed to refer to them. Nothing committed inside
`memory/`.

**Open for you:** the gitlore gate fired on the dirty memory submodule and asks
for an approved summary before `.claude/gitlore-memory-message` is written. I
did not write it — that approval is not a subagent's to take. The split (two
files where there was one, plus two index lines) is the part worth your eye
before it is committed.

## The one gate failure, and why it is the box

The first `just precommit` run failed on
`tests/test_drive_when_idle.py::test_a_delivered_line_records_its_gate_timings`
at `assert last["gate"] >= 0.15` (got 0.09, then 0.14 standalone). Load average
was **8.88** on a box with 157MB free; the walker's own interpreter startup
measured 0.25–0.45s against the 0.3s of composer absence that row stages, which
is exactly the hazard its own comment names.

Controlled rather than assumed: with **every** docstring in
`scripts/_watcher_lib.py` collapsed to `"""x"""` (22317 → 10653 bytes, so
strictly faster to import than either version), the row still failed 1 in 5. It
is load-sensitive on unmodified logic, not something this dispatch introduced.
Re-run once the load average fell below 4: green, first attempt.

Worth a separate look sometime — that row has ~0.15s of margin against a
startup cost that varies by 0.2s on this machine — but it is not this
dispatch's to change, and the brief forbids behaviour changes in `tests/`.

## Gate

`cd /Users/david/code/handoff && just precommit`

```
jq . .claude-plugin/plugin.json          jq . hooks/hooks.json
jq . .claude/settings.json               shellcheck -x .bin/* bin/* scripts/*.sh tests/*.bats
ruff check scripts tests                 ruff format --check scripts tests
docformatter --check scripts/*.py tests/*.py
mypy                                     ty check
bats tests/hook-test.bats tests/checkpoint.bats  → 170 rows ok
pytest → 283 passed, 14 deselected in 75.36s
ok
```

All new prose hard-wrapped at 80 columns (changelog index lines excepted, which
are one physical line by convention). The only over-80 lines in the files
touched are pre-existing.
