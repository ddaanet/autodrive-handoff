# Driving the transition with text in the composer

2026-10-16, Claude Code 2.1.301, same rig as
[the queued-prompt report](2026-10-16-queued-prompt-sweep-repro.md) and
[the stashed-prompt report](2026-10-16-stashed-prompt-sweep.md): interactive
haiku in the `-L qrepro` tmux server, throwaway repo `/tmp/claude/qrepro/repo`,
hook logs and `--debug-file`. The difference is the plugin: a copy at
`/tmp/claude/qrepro/plugin` (deleted afterwards) whose `hooks/handoff.ts` lacks
the one line `if ((await $.prompt.read()).text !== '') return`; the repo's own
file is untouched.

Each run: the first turn writes `.claude/autodrive` (`armed <session>`, the
kind, the lines) through `printf` and sleeps 25 s; about 2 s after the file and
the sleep are seen, `USERTEXT keepme` is typed into the composer, not
submitted and not stashed; the turn is left to end. The continuation line is
`Continue where the previous context stopped.`, the `CONTINUATION` constant at
`scripts/checkpoint.py:214`.

## Result: the mod drives fine over composer text, and the text survives

| Kind | `$.command.run` | Composer afterwards | `$.prompt.submit` | `autodrive.failed` |
| --- | --- | --- | --- | --- |
| rename | succeeds, `custom-title` written | `USERTEXT keepme`, unchanged | none | none |
| clear | `/rename` then `/clear` succeed, new session | `USERTEXT keepme`, unchanged | submits the mod's text only | none |
| compact | `/compact …` succeeds, `isCompactSummary` entry | `USERTEXT keepme`, unchanged | submits the mod's text only | none |

In no run was the user's text submitted, cleared or altered: in the pane it is
the composer's content at the end of each, and it is in none of the
transcripts nor in `ups.log` (only the arming prompt and, where there is one,
the continuation).

## rename

| UTC | event |
| --- | --- |
| 15:48:16.7 | `UserPromptSubmit`, arming prompt (the only one) |
| 15:48:23.5 | `USERTEXT keepme` typed |
| 15:48:48.3 | `Stop` |
| 15:48:48.7 | mod `drive-take.sh`; file taken and removed |
| 15:48:48.99 | toast, `$.command.run`: 20 chars queued |
| 15:48:49.2 | `turn.complete` settled; pane `/rename qrepro-title`, `Session renamed` |
| 15:48:57 | composer `USERTEXT keepme`; transcript `custom-title` 1; no `autodrive*` file |

## clear

| UTC | event |
| --- | --- |
| 15:49:14.8 | `UserPromptSubmit`, arming prompt |
| 15:49:23.6 | text typed |
| 15:49:47.5 | `Stop` |
| 15:49:48.5 | toast; `$.command.run` 20 chars queued (`/rename`) |
| 15:49:48.7 | `$.command.run` 6 chars queued (`/clear`) |
| 15:49:49.0 | `/clear` settled; `$.prompt.submit`: "Continue where the previous context stopped." |
| 15:49:49.25 | `UserPromptSubmit` carrying exactly that text |
| 15:49:49.8 | `turn.complete` settled (1.7 s); `[engine] turn 2` starts 15:49:50.3 |
| 15:49:55 and later | pane: continuation as the user message in the fresh session, model answering it; composer `USERTEXT keepme` |

A new transcript `e2596196…` holds the `/clear` command entries, then the
user entry "Continue where the previous context stopped." as the first prompt,
then the answer; `USERTEXT` occurs 0 times in it. `custom-title` entries
carry `qrepro-title` (the old session's `/rename` ran before the `/clear`).
Observed: the text lives through `/clear` in the composer.

## compact

| UTC | event |
| --- | --- |
| 15:50:23.6 | `UserPromptSubmit`, arming prompt |
| 15:50:32.1 | text typed |
| 15:50:55.9 | `Stop` |
| 15:50:56.5 | toast; `$.command.run` 32 chars queued (`/compact keep the word PINEAPPLE`) |
| 15:50:56.7 | compaction request (`source=compact`) |
| 15:51:04.2 | `SessionStart:compact` hooks; `load-compact.sh`: `handoff: compacted — No todo.` |
| 15:51:04.7 | `[engine] turn 2 end`; `$.prompt.submit` of the continuation |
| 15:51:05.2 | `UserPromptSubmit` with exactly that text |
| 15:51:05.95 | `turn.complete` settled (9.8 s, the compaction included) |
| 15:51:09.2 | second `Stop` (the continuation's turn); pane: composer `USERTEXT keepme` |

The transcript has an `isCompactSummary` entry ("This session is being
continued…") and the continuation as a user entry after it; `PINEAPPLE`
appears 12 times in the transcript file (the arming command and the
`/compact` line) but the summary text was not inspected for it, so the focus
directive's effect on the summary is not established.

## Answers to the questions

- Does `$.command.run` succeed with text in the composer? Yes, for all three
  commands (`/rename`, `/clear`, `/compact …`), observed in the debug log and
  the transcripts.
- Does the composer text survive? Yes, unchanged, through the rename, the
  `/clear` (fresh session) and the `/compact`. Observed in the pane at the end
  of each run.
- `$.prompt.submit({asUser: true})` with text in the composer: it submits the
  mod's text alone. One `UserPromptSubmit` carries exactly the continuation; the
  composer text is neither prepended nor sent separately.
- No `.claude/autodrive.failed` in any run.

## Not established

- Text typed or edited while the drive is mid-sequence (between `/rename` and
  `/clear`, or during the compaction's 9 s); the text was fixed before `Stop`.
  The deleted line was also the mod's only per-line guard against a user
  prompt arriving mid-sequence; nothing here tests that case.
- Multi-line, long, slash-prefixed or attachment-bearing composer text; one
  short word-pair was used. A composer `/`-line could behave differently.
- Cursor and selection state of the composer afterwards (only the text was
  read from the pane).
- Whether a human's keystrokes landing in the composer during the 1.7 s to
  9.8 s the drive takes are kept or lost.
- Other versions: only 2.1.301.
- `compact`'s summary content, as noted above; and whether a `pending` left
  by a failed drive changes anything (all drives succeeded here).
