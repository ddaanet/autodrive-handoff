#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

seed_marker_in_untrusted_dir() {
    printf '%s\0' arming-prompt > "$1/$prompt_marker"
    seed_armed_kind rename
}

@test "report-drive-failure (a symlinked marker directory is not read for the prompt marker: the file is swept)" {
    mkdir "$BATS_TEST_TMPDIR/planted-dir"
    ln -s "$BATS_TEST_TMPDIR/planted-dir" "$HANDOFF_POINTER_DIR"
    seed_marker_in_untrusted_dir "$BATS_TEST_TMPDIR/planted-dir"
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES" unsettled
}

@test "report-drive-failure (a group- or world-writable marker directory is not read for the prompt marker: the file is swept)" {
    mkdir -p "$HANDOFF_POINTER_DIR"
    chmod 777 "$HANDOFF_POINTER_DIR"
    seed_marker_in_untrusted_dir "$HANDOFF_POINTER_DIR"
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES" unsettled
}

# A marker that is not a regular file, or that cannot be read at all, leaves
# the prompt_id unsettled in the same way: the sweep and the lines are as for
# any stale file, and the note says a queued prompt may be the cause.
@test "report-drive-failure (a directory at the prompt marker: swept, the note names a queued prompt)" {
    make_pointer_dir
    mkdir "$HANDOFF_POINTER_DIR/$prompt_marker"
    seed_armed_kind rename
    PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES" unsettled
}

# The reader's helper fails on the marker alone (the stub, as reader_stub, but
# only for a marker path): no answer about the marker.
@test "report-drive-failure (the marker read fails: swept, the note names a queued prompt)" {
    local real stub="$BATS_TEST_TMPDIR/broken-marker-reader"
    real="$(command -v python3)"
    mkdir -p "$stub"
    # shellcheck disable=SC2016  # the stub's own $1/$4, expanded when it runs
    printf '#!/usr/bin/env bash\ncase "$1 $4" in "-I "*handoff-prompt-*) exit 97 ;; esac\nexec %q "$@"\n' "$real" > "$stub/python3"
    chmod +x "$stub/python3"
    seed_armed_kind rename
    seed_prompt_marker arming-prompt
    PATH="$stub:$PATH" PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ ! -e "$tmp/.claude/autodrive" ]
    assert_unloaded_report "$output" "$LINES" unsettled
}

# The pair: a marker that answers (here `absent`, the first prompt of a
# session, or another turn's id) keeps the note without the phrase, as the rows
# above do.
