#!/usr/bin/env bash
set -euo pipefail

# Wraps `bats` to show only failures plus a pass/fail count. A full run's TAP
# stream ("ok 1 ...", "ok 2 ...", ...) is hundreds of lines long -- too long to
# eyeball, and piping it through `tail -N` risks cropping the one "not ok"
# line that matters. The full stream goes to a log file, kept when the run
# fails so a failure that needs more context than the lines shown has it, and
# removed when the run passes.
#
# Usage: run-bats.sh <bats-args...>   (the args you'd pass to `bats` directly,
# bar any that change the output format or print something other than test
# results, such as -p, -F other than tap or tap13, -c, -v and -h: this reads
# TAP, and a run printing none counts as a run of no test)
#
# Exits with bats' own status, or 1 when bats exited 0 but ran no test. Not tied
# to the gate sentinels in `gates.just`: a consumer can use either without the
# other.

# Xs last: BSD mktemp randomises only a trailing run of them, and uses a
# template like `name-XXXXXX.log` literally -- the second run then dies on EEXIST.
log="$(mktemp "${TMPDIR:-/tmp}/plugin-dev-bats.XXXXXX")"

set +e
bats "$@" >"$log" 2>&1
status=$?
set -e

pass=$(grep -c '^ok ' "$log" || true)
fail=$(grep -c '^not ok ' "$log" || true)

if [ "$status" -eq 0 ] && [ "$pass" -eq 0 ] && [ "$fail" -eq 0 ]; then
    # A typo'd `--filter` or an empty .bats file exits 0 having checked nothing,
    # and a gate that records that has vouched for nothing.
    echo "bats: no tests ran"
    status=1
fi

if [ "$fail" -gt 0 ]; then
    awk '/^not ok /{show=1} /^ok /{show=0} show' "$log"
    echo
elif [ "$status" -ne 0 ]; then
    # A failure with no `not ok` block to show (a teardown_file crash, a test
    # count that does not add up, bats dying before a plan) -- the log is the
    # only account of it.
    cat "$log"
fi

if [ "$status" -eq 0 ]; then
    rm -f "$log"
    echo "bats: $pass passed, $fail failed"
else
    echo "bats: $pass passed, $fail failed — full log: $log"
fi
exit "$status"
