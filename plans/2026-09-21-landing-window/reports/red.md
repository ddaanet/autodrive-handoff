# RED — the landing window is sized by the boot, not the settle

2026-09-21. Tests only; nothing under `scripts/` touched. `tests/conftest.py`
unchanged — the stub needed no new capability. All edits are in
`/Users/david/code/handoff/tests/test_drive_when_idle.py`.

Final state of the file: **2 failed, 32 passed** — the two failures are the two
rows this dispatch owns, and every pre-existing row still passes.

## Rows added

### 1. `test_a_booting_pane_is_typed_into_at_once_and_given_time_to_paint` — RED

The state of the world that fails it: a pane whose composer is absent for the
first second (boot chrome, cursor at the screen origin), then appears; the
walker's literal send is not painted into the composer until 0.5s after the
keystroke. `HANDOFF_WATCHER_LANDING_DELAY` is 0.1, `BOOT_LANDING_DELAY` 5,
`BOOT_SETTLE` 5.

Unchanged code hands that line the 0.1s mid-session window and gives up on a
line the session already holds:

```
>       assert result.returncode == 0, (
            fail_file.read_text() if fail_file.exists() else result.stderr
        )
E       AssertionError: `continue with task 3` did not land in the composer 0.2s after it started reading input. The composer held:
E         ❯
E
E       assert 1 == 0
tests/test_drive_when_idle.py:921: AssertionError
```

The row's second claim — that the line is sent *promptly*, with no settle —
reds on its own assertion. Probed by temporarily hoisting it above the
returncode assert (probe reverted; the committed order is returncode first):

```
>       assert elapsed < 4
E       assert 6.33434917870909 < 4
```

6.33s is the 5s `BOOT_SETTLE` plus the boot and the failed landing poll. After
GREEN that variable is ignored and the run should finish around 2s.

Note what the unchanged failure message hides: it reports `0.2s after it
started reading input`, because `gate_opened` is stamped *after* the settle
sleep. The 5s the line waited is invisible in the one channel a detached
walker has. That is a second reason the settle is the wrong shape, beyond
costing the delay.

### 2. `test_a_mid_session_line_keeps_the_short_landing_window` — GREEN BY DESIGN

Composer present from the gate's first reading; same 0.5s late paint; same 0.1s
`LANDING_DELAY` with `BOOT_LANDING_DELAY` at 5. Asserts the walker **fails**
with `did not land` and never Enters.

Green against unchanged code, and it must stay green after GREEN. It exists so
row 1 cannot be satisfied by widening the window everywhere — that would cost
`BOOT_LANDING_DELAY` of silence on the one report that says a keystroke was
swallowed, in the situation where the composer has been reading for as long as
the session has.

Checked for a vacuous pass rather than observed passing: widen that row's
`LANDING_DELAY` to 5 and the line lands — the failure moves past `did not
land` to the confirmation stage. So the row fails on the window, not on the
staging.

```
E       AssertionError: assert 'did not land' in 'the continuation prompt was typed but three enters did not submit it\n'
```

## Row changed

### 3. `test_a_delivered_line_records_its_gate_timings` — RED

`assert last["settle"] == 0.01` replaced by an exact key-set assertion, which
subsumes the `{"at", "idle", "landed", "confirmed"}` subset check it also
replaces:

```python
assert set(last) == {"at", "line", "gate", "idle", "landed", "confirmed"}
```

```
>       assert set(last) == {"at", "line", "gate", "idle", "landed", "confirmed"}
E       AssertionError: assert {'at', 'confi..., 'line', ...} == {'at', 'confi...nded', 'line'}
E         Extra items in the left set:
E         'settle'
tests/test_drive_when_idle.py:1023: AssertionError
```

The docstring's closing sentence ("the settle is the one the walker was
given") is rewritten to say why the key is gone. `assert last["gate"] >= 0.15`
is untouched and still passes: the 0.3s absent composer that row stages is the
gate's own share, which survives the change.

## Helper change

`walk()` gained one default, beside the `LANDING_DELAY` line it mirrors:

```python
"HANDOFF_WATCHER_BOOT_LANDING_DELAY": "0.5",
```

Ignored by unchanged code. It keeps the three pre-existing boot-staging rows
(2026-08-15 glyph-absence, 2026-09-20 stale glyph, the timing record) off the
30s production default once GREEN lands — none of them expects a non-delivery,
so a short window is correct for all three, and all three still pass.

## For GREEN

`walk()` still exports `HANDOFF_WATCHER_BOOT_SETTLE: "0.01"`. Left in place so
this RED run stays fast (removing it makes every boot-staging row pay the 10s
production default against unchanged code). Deleting the tunable is GREEN's
job, and that line goes with it — row 1 sets `BOOT_SETTLE` in its own env
deliberately and that override should stay, as the evidence that the variable
is inert.

## Commands

```
cd /Users/david/code/handoff
.venv/bin/pytest tests/test_drive_when_idle.py
.venv/bin/ruff check tests/test_drive_when_idle.py tests/conftest.py   # All checks passed
.venv/bin/ruff format --check tests/test_drive_when_idle.py tests/conftest.py   # 2 files already formatted
```
