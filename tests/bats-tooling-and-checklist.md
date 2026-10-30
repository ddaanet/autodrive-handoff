# Bats-core best practices, part 2: sourcing through the checklist

Sections 1–4 (masked failures, `run`, setup/teardown, naming) are in
[bats-best-practices.md](bats-best-practices.md).

---

## 5. Sourcing scripts and helpers (`load`, `bats_load_library`, paths)

- `load name` sources a file relative to the test file (or an absolute
  path). For backwards compatibility it first tries `name.bash`, then
  `name`; that `.bash`-extension fallback is **deprecated** — pass an
  exact filename. ([writing-tests]) `load` exits bats on failure; use
  `bats_load_safe` if you need to `load` conditionally. To source a
  `.sh` script-under-test, `source` it directly (more explicit than
  relying on `load`'s search):

```bash
setup() {
  source "$BATS_TEST_DIRNAME/../scripts/foo.sh"   # script under test
}
```

- `bats_load_library name` is for **system-installed** libraries
  resolved via `$BATS_LIB_PATH` (e.g. brew/npm installs) — not for
  in-repo helpers. Since this project has **no** helper libs, you
  should see `load`/`source`, not `bats_load_library`. ([writing-tests])
- Always build paths from `$BATS_TEST_DIRNAME`, never from `$PWD` or a
  relative path (cwd is not guaranteed).

---

## 6. Version pinning, skipping, retries

- Declare the floor once, near the top (or in `setup`):

```bash
bats_require_minimum_version 1.5.0
```

  This documents intent and silences the BW02 warning that any `run`
  flag (`run !`, `run -N`) emits otherwise. `run` flags need ≥1.5.0;
  `bats_pipe` ≥1.10.0; tag directives ≥1.8.0 (but tags are a comment
  directive and work without the floor — the floor is for the runtime
  features, not tags). `bats_require_minimum_version` *itself* was
  introduced in 1.7.0, so it is a no-op floor below that. ([writing-tests])

- `skip "reason"` skips from that point on; conditional skips read well:

```bash
@test "needs docker" {
  command -v docker >/dev/null || skip "docker not installed"
  run docker info
  [ "$status" -eq 0 ] || return 1
}
```

  `setup`/`teardown` still run for skipped tests. ([writing-tests])

- `BATS_TEST_RETRIES=N` retries a failing test up to N times. Treat
  retries as a **smell** — they hide flaky tests. The default 0 (must
  pass first try) is correct for a deterministic suite; a reviewer
  should question any nonzero value and demand a justification.
  ([writing-tests])

---

## 7. ShellCheck on `.bats` files

ShellCheck understands bats's non-standard `@test "…" { }` syntax
natively as of **ShellCheck 0.7** (per the bats-core gotchas page);
this repo lints with **0.10.0**, which parses `.bats` files directly —
no `shellcheck.sh` wrapper, no `--shell=bats` flag. Pass `.bats` files
straight to `shellcheck` (the precommit does exactly this:
`shellcheck -x scripts/*.sh tests/*.sh tests/*.bats`). Verified on
0.10.0: `@test` blocks are analyzed and real issues (SC2086, SC2155,
…) are reported inside the body.

- ShellCheck 0.10.0 is bats-aware enough that it does **not** fire
  SC2154 for `$status`/`$output`/`$lines`/`$stderr` (verified). If a
  `$BATS_*` var or a bats-injected var ever does trip SC2154, suppress
  narrowly, not globally:

```bash
# shellcheck disable=SC2154   # set by bats `run` / harness
```

- For a sourced helper or script-under-test, add a source directive so
  `shellcheck -x` follows it:

```bash
# shellcheck source=tests/helpers.bash
load helpers
```

- Keep `.bats` files lint-clean under the same `shellcheck` invocation
  the project uses for its `.sh` scripts; wire it into the precommit
  lint step.

---

## 8. Mocking, parameterization, and diagnostics

### 8a. Mock commands by shadowing them on `PATH`

The portable, bare-bats way to stub an external command (no mocking
library) is a fake executable earlier on `PATH`:

```bash
setup() {
  STUBDIR="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUBDIR"
}

@test "uses git, but git is stubbed" {
  cat > "$STUBDIR/git" <<'STUB'
#!/usr/bin/env bash
echo "stub git $*"
STUB
  chmod +x "$STUBDIR/git"
  run env PATH="$STUBDIR:$PATH" my_script
  [ "$status" -eq 0 ] || return 1
}
```

This is the pattern `hook-test.bats` uses to stub a command (a per-test
`$STUBDIR` script that logs its arguments and emits scripted output). Reviewer expectations for a PATH stub: it lives
under a bats tmpdir (auto-cleaned), it is `chmod +x`, and it is put on
`PATH` only for the call under test (`run env PATH=… cmd`) so it can't
leak into other tests. Prefer this over rewriting the script under test
to inject a command path.

### 8b. Parameterized cases — bats has no native loop-over-`@test`

Bats cannot register a `@test` from a `for` loop, and `.bats` files
take no parameters; the supported workaround is to drive cases through
environment variables, or to factor the assertion into a helper that
each `@test` calls with its own inputs. (Bats 1.11.0 added
`bats_test_function` for programmatic registration, but that is an
advanced, rarely-needed escape hatch — keep one explicit `@test` per
case for readable TAP output unless the case count is large.)
([writing-tests], [faq])

### 8c. Skipping and diagnostics flags worth knowing

- `skip "reason"` always carries a reason; `setup`/`teardown` still run
  for skipped tests. (There is no `BATS_RUN_SKIPPED` override in 1.11.1
  — verified absent from the install; to exercise a skipped body,
  comment the `skip` line.)
- `--print-output-on-failure` prints `$output` for failing tests (the
  single most useful CI flag — `run` hides output by default). Pair
  with `fail "…"` messages (§1d).
- `--show-output-of-passing-tests` and `--verbose-run` surface output
  more aggressively while debugging; `-x`/`--trace` is `set -x` for the
  test body.
- `-f 'regex'` runs one test (or a name subset); `--filter-status
  failed` reruns just last run's failures/missing tests (valid values:
  `failed`, `missed`). `--no-tempdir-cleanup` keeps the bats tmpdirs so
  you can inspect a failure. ([usage])

---

## 9. Common anti-patterns (reject on sight)

| ❌ Anti-pattern | ✅ Fix |
|---|---|
| Checking `$?` after `run` | `run` returns 0; assert `$status`. |
| Mixing guarded and unguarded `[ … ]` mid-body | Pick one idiom; guard with `\|\| return 1` / `\|\| fail` for self-documenting failures and Bash-3.2 portability. (Plain `[ … ]` does abort on 1.11.1 — this is style, not a silent-pass bug.) |
| Bare `[[ … ]]` / `(( … ))` mid-body where 3.2 portability matters | Guard, or use `[ … ]` / `grep -q`. |
| Unquoted `$output` (`[ $output = x ]`) | Always `"$output"`. |
| Bare `! cmd` to assert failure | `run ! cmd` (Bats ≥1.5) — a leading `!` is mangled by the bats preprocessor (status 127). |
| `run cmd \| grep …` expecting a pipe | `run bash -c '…'` or `run bats_pipe`. |
| Relying on test execution order / shared mutable state | Each test is an isolated subshell; use `setup`. |
| Logic-under-test defined inside the `.bats` file | Source the real script; test the artifact. |
| `run` when a direct call is clearer | Direct call for pure success checks. |
| Swallowing stderr (combined `$output` hides it) | `--separate-stderr` when stderr matters. |
| Hand-rolled `mktemp`+`trap` cleanup | `$BATS_TEST_TMPDIR` / `$BATS_FILE_TMPDIR`. |
| `bats_load_library` for in-repo helpers | `load` / `source` with `$BATS_TEST_DIRNAME`. |
| `BATS_TEST_RETRIES` masking flakiness | Fix the test; default is 0. |

---

## Reviewer checklist

Run down these binary, checkable items against the converted suite:

- [ ] **Assertions are consistently guarded.** Each non-final `[ … ]`,
      `[[ … ]]`, `(( … ))` is terminated with `|| return 1` /
      `|| fail "…"` (or is a direct command relying on errexit). On
      1.11.1 a plain `[ … ]` aborts unguarded, so this is a
      style/portability/diagnostics standard, not a silent-pass bug —
      but a suite that *mixes* guarded and unguarded is a flag. The
      genuinely-exempt forms (`if`/`while` conditions, `&&`/`||` LHS,
      leading `!`) must never carry the sole assertion.
- [ ] **`$status` is asserted after every `run`.** No test calls `run`
      and then only inspects `$output` without checking `$status` (or
      uses the `run -N` / `run !` form).
- [ ] **No `$?` after `run`.** Status is read via `$status` only.
- [ ] **`$output` is always double-quoted** in every assertion.
- [ ] **Failure is asserted via `run ! cmd`**, never a line beginning
      with bare `! cmd` (the bats preprocessor mangles a leading `!` to
      a 127 "command not found").
- [ ] **No `run cmd | …` pipelines.** Pipes are wrapped in
      `run bash -c '…'` or `run bats_pipe … \| …`.
- [ ] **`run` is used only when needed** (output inspection or expected
      non-zero exit); pure success checks call the command directly.
- [ ] **stderr is not silently swallowed** where it matters:
      `--separate-stderr` is used when asserting on stderr.
- [ ] **`--keep-empty-lines`** is used wherever empty lines are
      significant to a `$lines` count.
- [ ] **No hand-rolled `mktemp`+`trap`**; tests use
      `$BATS_TEST_TMPDIR` / `$BATS_FILE_TMPDIR`.
- [ ] **Paths derive from `$BATS_TEST_DIRNAME`**, not `$PWD` or bare
      relative paths.
- [ ] **The script under test is `source`d / `load`ed**, not
      reimplemented inside the `.bats` file.
- [ ] **No reliance on test order or cross-test mutable state**; shared
      read-only setup lives in `setup`/`setup_file`.
- [ ] **Expensive shared setup is in `setup_file`**, per-test fixtures in
      `setup`.
- [ ] **`teardown` ends successfully** (`… || true`) and doesn't
      accidentally fail tests.
- [ ] **Test names are descriptive sentences**, one focused `.bats` file
      per unit.
- [ ] **Tags use the `# bats test_tags=` / `file_tags=` directive
      syntax** correctly (no whitespace, valid chars); no stray
      `bats:focus` committed.
- [ ] **`bats_require_minimum_version`** is declared if any `run` flag
      (`run !`, `run -N`) or `bats_pipe` is used (silences BW02); tags
      work without it.
- [ ] **PATH stubs are hygienic.** A mocked command lives under a bats
      tmpdir, is `chmod +x`, and is on `PATH` only for the call under
      test (`run env PATH="$STUBDIR:$PATH" …`), so it can't leak across
      tests.
- [ ] **No native loop-over-`@test`.** Parameterized cases are driven by
      env vars or a shared helper, not by an unsupported `for`-loop
      around `@test`.
- [ ] **`bats_load_library` is NOT used for in-repo helpers** (this
      project has no installed libs); `load`/`source` are used instead.
- [ ] **No `assert_output`/`assert_success`/`assert_file_*`** or other
      helper-library calls — the suite is bare bats-core.
- [ ] **`BATS_TEST_RETRIES` is 0** (unset) unless a documented
      justification exists.
- [ ] **`.bats` files pass `shellcheck`** under the project's lint
      invocation; SC2154 suppressions are narrow and source directives
      present for sourced helpers.
- [ ] **`skip "reason"` carries a reason**; conditional skips guard
      genuinely unavailable dependencies, not flaky logic.

---

### Sources

Docs fetched and version requirements cross-checked 2026-06-08
against the `en/stable` docs (which track 1.11.x):

- [writing-tests]: bats-core — Writing tests:
  https://bats-core.readthedocs.io/en/stable/writing-tests.html
  (run -N/!, --separate-stderr/--keep-empty-lines, bats_pipe, tmpdir
  vars incl. $BATS_SUITE_TMPDIR, tags 1.8.0, bats:focus, load vs
  bats_load_safe, BATS_TEST_RETRIES, bats_require_minimum_version 1.7.0)
- [gotchas]: bats-core — Gotchas:
  https://bats-core.readthedocs.io/en/stable/gotchas.html
  (errexit `[[ ]]`/`(( ))` change at Bash 4.1; `! cmd` exemption + the
  `! x || false` fallback; `run cmd | …` parsing; ShellCheck native
  bats support "as of 0.7")
- [usage]: bats-core — Usage:
  https://bats-core.readthedocs.io/en/stable/usage.html
  (--filter-status values `failed`/`missed`, --print-output-on-failure,
  --show-output-of-passing-tests, --verbose-run, -x, -j, -f)
- [faq]: bats-core — FAQ (no loop-over-`@test`; parameterize via env)
- [BW01]: https://bats-core.readthedocs.io/en/stable/warnings/BW01.html
  (run exit 127 → likely masked typo; acknowledge with `run -127`/`run !`)
- ShellCheck native `.bats` support: stated "as of 0.7" on the gotchas
  page; bats-core `shellcheck.sh`
  https://github.com/bats-core/bats-core/blob/master/shellcheck.sh

Empirically verified locally (Bats **1.11.1**, Bash **5.2.37**,
ShellCheck **0.10.0**), 2026-06-08:

- Plain `[ … ]`, `[[ … ]]`, `(( … ))`, and failing pipelines **abort**
  the test mid-body under errexit; `if`/`while` conditions and `&&`/`||`
  LHS **silently pass**.
- A `@test` body line beginning with `!` is mangled to a literal `!`
  command (status 127, "command not found") — so bare `! cmd` and
  `! cmd || false` both fail with 127; `run ! cmd` and
  `cmd && return 1 || true` are the working forms.
- Any `run` flag emits **BW02** without `bats_require_minimum_version`;
  the floor silences it. `bats_pipe` added in 1.10.0.
- ShellCheck 0.10.0 lints `.bats` directly (no wrapper), analyzes
  `@test` bodies (SC2086/SC2155 fire), and does **not** raise SC2154
  for `$status`/`$output`/`$lines`/`$stderr`.
- `BATS_RUN_SKIPPED` is **absent** from the 1.11.1 install (only the
  internal `BATS_TEST_SKIPPED` exists).
