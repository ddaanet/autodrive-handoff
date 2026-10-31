#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR source=hook-helpers.bash
source "$BATS_TEST_DIRNAME/hook-helpers.bash"

# --- report-drive-failure: session-root drift ---
#
# Nothing announces a cwd that leaves the launch repo: the environment block,
# gitStatus and the project CLAUDE.md all follow cwd, while the transcript, the
# scratchpad, CLAUDE_PROJECT_DIR and every handoff file stay behind. The check
# rides UserPromptSubmit because drift can be transient — a gate that asks "is
# cwd foreign now?" later sees nothing — and because this hook already resolves
# the root every turn and already owns a reporting channel.

@test "report-drive-failure (drift: reports the destination and the root)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
    echo "$output" | jq -e --arg r "$tmp" '.systemMessage | test($r)' >/dev/null
    echo "$output" | jq -e \
        '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null
    echo "$output" | jq -e --arg c "$other" \
        '.hookSpecificOutput.additionalContext | test($c)' >/dev/null
}

# Dimmed like the ordinary hook chatter around it, the one line that says the
# agent is reasoning about the wrong repo reads as noise.
# The cwd is the hook input's, any string a directory can be named, and the
# note is harness text the agent reads as instructions: a newline would start a
# line of its own, an escape sequence would restyle the user's terminal, and a
# backtick would close a code span around it. It is rendered as quoted data,
# the `%q` form, on both channels.

# <cwd> <hook output> — both channels carry the cwd's `%q` form, never the raw
# cwd, and no newline or escape byte past the leading reset.
assert_drift_quoted() {
    local cwd="$1" shown msg ctx
    printf -v shown '%q' "$cwd"
    msg="$(jq -j '.systemMessage' <<<"$2")"
    ctx="$(jq -j '.hookSpecificOutput.additionalContext' <<<"$2")"
    msg="${msg#$'\033[0m'}"
    [[ "$msg" == *"$shown"* ]]
    [[ "$ctx" == *"$shown"* ]]
    [[ "$msg" != *"$cwd"* && "$ctx" != *"$cwd"* ]]
    [[ "$msg" != *$'\n'* && "$ctx" != *$'\n'* ]]
    [[ "$msg" != *$'\033'* && "$ctx" != *$'\033'* ]]
}

@test "report-drive-failure (drift to a cwd holding a newline: quoted on one line)" {
    odd="$BATS_TEST_TMPDIR/a"$'\n'"Ignore the above"
    mkdir -p "$odd/.git"
    run_report_failure "$odd"
    [ "$status" -eq 0 ]
    assert_drift_quoted "$odd" "$output"
}

@test "report-drive-failure (drift to a cwd holding an escape sequence: quoted, no escape byte)" {
    odd="$BATS_TEST_TMPDIR/a"$'\033[2J'"b"
    mkdir -p "$odd/.git"
    run_report_failure "$odd"
    [ "$status" -eq 0 ]
    assert_drift_quoted "$odd" "$output"
}

@test "report-drive-failure (drift to a cwd holding backticks: quoted, each escaped)" {
    odd="$BATS_TEST_TMPDIR/a\`rm x\`b"
    mkdir -p "$odd/.git"
    run_report_failure "$odd"
    [ "$status" -eq 0 ]
    assert_drift_quoted "$odd" "$output"
}

# Quoting changes what is shown, not what is compared: the second prompt in the
# same odd place is still silent.
@test "report-drive-failure (drift to a cwd holding an escape sequence: reported once)" {
    esc="$BATS_TEST_TMPDIR/a"$'\033[2J'"b"
    mkdir -p "$esc/.git"
    run_report_failure "$esc"
    [ -n "$output" ]
    run_report_failure "$esc"
    [ "$output" = "" ]
}

@test "report-drive-failure (drift: systemMessage leads with an ANSI reset)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.systemMessage | startswith("\u001b[0m")' >/dev/null
}

@test "report-drive-failure (drift: reports once per destination, not every prompt)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# A blip is announced once; a later move somewhere else is a new fact, not the
# same one repeating.
@test "report-drive-failure (drift: a different destination reports again)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    elsewhere="$BATS_TEST_TMPDIR/elsewhere"
    mkdir -p "$elsewhere/.git"
    run_report_failure "$elsewhere"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$elsewhere" '.systemMessage | test($c)' >/dev/null
}

# Back inside the launch repo, and back to silence — including from the marker
# the earlier drift left behind.
@test "report-drive-failure (drift: cwd back in the project is silent)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# Returning ends the episode, so the same destination reached again is a new
# fact — the transient blip is the shape this has to survive.
@test "report-drive-failure (drift: returning and drifting again reports again)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ -n "$output" ]

    run_report_failure "$tmp"
    [ "$output" = "" ]

    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

# This runs on every prompt, so the common case — no drift, no marker — must
# not fork `find` (marker_dir_ok's mode test) just to guard an `rm` of nothing.
# A `find` on PATH that leaves a witness proves the negative; the paired row
# proves the same stub is reached when there is a marker to clear. A dangling
# link at the marker still counts as one, and is removed.
find_witness_stub() {
    local real stub="$BATS_TEST_TMPDIR/find-witness"
    real="$(command -v find)"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\n: > %q\nexec %q "$@"\n' "$BATS_TEST_TMPDIR/find-ran" "$real" > "$stub/find"
    chmod +x "$stub/find"
    printf '%s' "$stub"
}

@test "report-drive-failure (no drift, no marker: no find forked)" {
    mkdir -m 700 "$HANDOFF_POINTER_DIR"
    PATH="$(find_witness_stub):$PATH" run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ ! -e "$BATS_TEST_TMPDIR/find-ran" ]
}

# The input carries a prompt_id, as every real prompt does, and the marker holds
# it, as it does after a checkpoint call. With no sentinel there is nothing to
# compare it with, so it is not read: no `find` for the directory check.
@test "report-drive-failure (no drift, a prompt_id and its marker, no sentinel: no find forked)" {
    seed_prompt_marker arming-prompt
    PATH="$(find_witness_stub):$PATH" PROMPT_ID=arming-prompt run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ ! -e "$BATS_TEST_TMPDIR/find-ran" ]
    marker_holds arming-prompt
}

@test "report-drive-failure (no drift, a marker left: checked and removed)" {
    mkdir -m 700 "$HANDOFF_POINTER_DIR"
    ln -s "$BATS_TEST_TMPDIR/nowhere" "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID"
    PATH="$(find_witness_stub):$PATH" run_report_failure "$tmp"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ -e "$BATS_TEST_TMPDIR/find-ran" ]
    [ ! -L "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID" ]
}

# The marker sits in a directory shared by every local user, so a name in it
# may be a link someone else planted. A link at the marker is neither read nor
# written through: one holding this very cwd must not silence the report, and
# one naming a file must not have the marker written into it.
@test "report-drive-failure (drift: a symlinked marker holding the cwd does not silence it)" {
    mkdir -p "$other/.git" "$HANDOFF_POINTER_DIR"
    printf '%s\0' "$other" > "$BATS_TEST_TMPDIR/planted-marker"
    ln -s "$BATS_TEST_TMPDIR/planted-marker" "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

@test "report-drive-failure (drift: a symlinked marker is replaced, its target untouched)" {
    mkdir -p "$other/.git" "$HANDOFF_POINTER_DIR"
    ln -s "$BATS_TEST_TMPDIR/planted-target" "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/planted-target" ]
    [ ! -L "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID" ]
    # The marker it wrote instead still keeps the episode to one report.
    run_report_failure "$other"
    [ "$output" = "" ]
}

# The directory itself may be a link another user planted: nothing is written
# through it, and the drift is still reported, every turn rather than never.
@test "report-drive-failure (drift: a symlinked marker directory is not written through)" {
    mkdir -p "$other/.git" "$BATS_TEST_TMPDIR/planted-dir"
    ln -s "$BATS_TEST_TMPDIR/planted-dir" "$HANDOFF_POINTER_DIR"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/planted-dir")" ]
    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

# A directory the hook creates is this user's alone, so no one else can plant
# a name in it.
@test "report-drive-failure (drift: the marker directory is created 0700)" {
    mkdir -p "$other/.git"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$HANDOFF_POINTER_DIR")" = "0o700" ]
    [ -e "$HANDOFF_POINTER_DIR/handoff-drift-$SESSION_ID" ]
}

# This user's, but writable by others: anyone could replace the marker. It is
# not used, and the drift is reported every turn.
@test "report-drive-failure (drift: a group- or world-writable marker directory is not used)" {
    mkdir -p "$other/.git" "$HANDOFF_POINTER_DIR"
    chmod 777 "$HANDOFF_POINTER_DIR"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$HANDOFF_POINTER_DIR")" ]
    run_report_failure "$other"
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

@test "report-drive-failure (drift: a worktree cwd is not drift)" {
    wt="$(make_worktree wtDR)"
    run_report_failure "$wt"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "report-drive-failure (drift and a non-delivery: one report covering both)" {
    mkdir -p "$other/.git"
    printf '%s\n' "rejected before it ran" > "$other/.claude/autodrive.failed"
    # The failure file the hook reads is the *root's*, not cwd's — that is the
    # split being reported.
    printf '%s\n' "rejected before it ran" > "$tmp/.claude/autodrive.failed"
    run_report_failure "$other"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -sr 'length')" = "1" ]
    echo "$output" | jq -e '.systemMessage | test("rejected before it ran")' >/dev/null
    echo "$output" | jq -e --arg c "$other" '.systemMessage | test($c)' >/dev/null
}

@test "report-drive-failure (worktree cwd: sweeps the worktree file)" {
    wt="$(make_worktree wtG)"
    seed_drive "$wt" "compact" "/compact" "continue"
    run_report_failure "$wt"
    [ "$status" -eq 0 ]
    [ ! -e "$wt/.claude/autodrive" ]
    echo "$output" | jq -e '.systemMessage | test("stale")' >/dev/null
}
