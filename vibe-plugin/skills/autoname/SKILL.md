---
name: autoname
description: 'Set the session title from the conversation — a rename only, with no task snapshot and no memory write. Vibe auto-titles sessions, so this is the manual counterpart: the checkpoint validates the title and the closing line hands it to the user. Use when the user asks to "name this conversation", "name this chat", "name this session", "rename session", "rename this session", "title this session", or "autoname". For "save handoff", "before /clear", "wrap up", or "I''m done", use the handoff skill instead.'
---

# autoname — Session Title Only

Name the current Vibe session — nothing else. This is handoff's rename-half
on its own: no task snapshot, no memory write, no `/clear`. Use it for a
side conversation, or any session worth a name while the main thread stays
live.

## Protocol

Decide a concise session title from the conversation. Make **no tool
calls** to decide it. Title rules: ≤ ~50 characters, Title Case, no
surrounding quotes, no trailing punctuation. The title is always
derived from the conversation — autoname takes no argument.

Then run `checkpoint.py` (Bash) from the plugin's skill directory — the
skill tool printed its path when this skill loaded, as
`Base directory for this skill: <path>` — piping the whole call as JSON on
stdin via a heredoc:

````
python3 "<base directory>/checkpoint.py" <<'JSON'
{"skill": "autoname", "rename": "<session title>"}
JSON
````

Those two fields are the whole payload. Every other field the checkpoint
takes belongs to a boundary this skill is not — no task file, no memory,
no transition — and each is a schema error here rather than a silent
ignore. A non-zero exit names the offending field on stderr.

Its output ends on the `/rename` command that carries the title to the
user. End the reply on that `/rename ...` line — nothing under Vibe can type
`/rename`, so the user runs it.

## Anti-patterns

- Writing `TASK.md`, updating memory, or running any other tool.
  autoname is rename-only; for residual task state use the handoff skill.
- Taking a title from the user's words verbatim when the conversation
  implies a better one. Derive the title; do not transcribe the request.
- Restating the title in your own words after the line. The user copies
  the printed `/rename` command.
