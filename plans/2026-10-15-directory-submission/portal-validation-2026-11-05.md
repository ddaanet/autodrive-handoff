# Portal validation of `dist`, 2026-11-05

The text below is the Validate report from claude.ai/directory/manage, plugin bundle form, for `ddaanet/autodrive-handoff`, plugin path empty. Blocking findings and policy holds are expanded, with their rule codes; warnings and notes are collapsed.

```text
Validation: 2 blocking issues to fix, plus 3 warnings et 12 policy holds
dist @ ead5e29 · 7 checks
Re-validate
2 blocking · 3 warnings · 12 policy holds

Blocking:
Unpinned npx launcher
scripts/write-guard.sh

Write the script so each command can be read on its own: for example, run a command that sits inside a quoted string on its own line, or assign its output first (x=$(cmd); echo "$x"); keep here-documents out of quoted strings, and split a very long script into smaller ones.
scripts/write-guard.sh (a script one of the plugin's commands runs) names a package launcher (npx, uvx …), or runs a program the validator cannot name, in a script the validator could not fully read, so it cannot check which package runs or that its version is pinned; the directory refuses it.
scripts/write-guard.sh · 


UNPINNED_NPX

Blocking:
Command path can’t be followed
.

A command the plugin loader runs has a path the shell computes, or something else the validator cannot follow; only the plugin's tree was validated, and such a command may reach outside it (other installed plugins, the installer's files, the user's project). Examples: a variable other than ${CLAUDE_PLUGIN_ROOT} (a Windows-style %NAME% counts too, in a command run by cmd.exe or by a package tool such as npm, npx or pip); a command substitution; a glob or brace pattern; an inline program the validator does not read (awk '…', perl -e, python3 -c, node -e and the like); a file the command itself downloads or writes and then runs or hands to an interpreter; more paths than the validator reads. Spell each path the command runs literally, as ${CLAUDE_PLUGIN_ROOT}/<file>, inside the plugin; move an inline program into a script file inside the plugin and run that file (${CLAUDE_PLUGIN_ROOT}/scripts/step.sh, …/step.py) — the validator follows plain shell scripts and holds other script files for a reviewer instead of refusing them; a hook's script can read a value it needs, such as $CLAUDE_PROJECT_DIR, from its environment instead of taking it on the command line. A shell wrapper whose -c text names ${CLAUDE_PLUGIN_ROOT} on its own, with no path after it (sh -c 'cd ${CLAUDE_PLUGIN_ROOT} && exec node server.js'), is refused as well: declare node as the command and ${CLAUDE_PLUGIN_ROOT}/server.js as its argument, and the validator holds that file for a reviewer instead of refusing it. Relative paths would not work anyway: the command's working directory is the user's project, not the plugin.
.
COMMAND_PATH_COMPUTED

Policy hold:
Mod can read local data and can also send data out
Policy hold · hooks/handoff.ts · line 80

Say in the plugin's README what the mod sends and where; if the way out is a call the directory does not know, say what that call does.
This mod can read facts about local files (fs.stat) and can also send data out (process.run). The directory names the pair; it has not found that what is read is sent.
hooks/handoff.ts · line 80 · 


MOD_LOCAL_DATA_LEAVES

Policy hold:
Mod may start a program the directory couldn’t fully check
Policy hold · hooks/handoff.ts · line 80

Write the whole command as fixed text in the call, or say in the plugin's README what it runs.
This mod runs a program (process.run) whose name or arguments are not all written as fixed text at the call, so the directory cannot read the whole command.
hooks/handoff.ts · line 80 · 


MOD_PROCESS_COMMAND_COMPUTED

Policy hold:
Mod starts other programs
Policy hold · hooks/handoff.ts · line 80

If the mod needs to run programs, say in the plugin's README which programs and why.
This mod runs programs on the user's machine (process.run).
hooks/handoff.ts · line 80 · 


MOD_RUNS_PROCESS

Policy hold:
Mod starts a shell, a network tool, or an inline script
Policy hold · hooks/handoff.ts · line 80

Run the one program the mod needs, by name, with fixed arguments; use the http call for requests.
This mod runs a shell (process.run). That can run any command or fetch any file. Places like this that the directory recorded in the file: 2; the line given is the first.
hooks/handoff.ts · line 80 · 


MOD_RUNS_SHELL_OR_DOWNLOADER

Policy hold:
Mod can read the conversation and can also send data out
Policy hold · hooks/handoff.ts · line 80

Say in the plugin's README what the mod sends and where; if the way out is a call the directory does not know, say what that call does.
This mod can read the conversation (a hook on prompt.submit) and can also send data out (process.run). The directory names the pair; it has not found that conversation text is sent.
hooks/handoff.ts · line 80 · 


MOD_SESSION_DATA_LEAVES

Policy hold:
Mod runs slash commands itself
Policy hold · hooks/handoff.ts · line 126

If the mod needs the call, say in the plugin's README which commands it runs and when.
This mod runs slash commands itself (command.run). Calls of this kind counted in the mod: 1; the line given, where there is one, is the first.
hooks/handoff.ts · line 126 · 


MOD_RUNS_COMMAND

Policy hold:
Mod can read the conversation or other data and can also submit a prompt that can carry text out
Policy hold · hooks/handoff.ts · line 134

Say in the plugin's README what the mod puts in the prompts it submits.
This mod can read facts about local files (fs.stat) and can also submit a prompt (prompt.submit), which can carry text out of the mod. The directory names the pair; it has not found that what is read is put in a prompt.
hooks/handoff.ts · line 134 · 


MOD_DATA_LEAVES_BY_PROMPT

Policy hold:
Mod writes a file that other tools run or obey
Policy hold · hooks/handoff.ts · line 174

If the mod is meant to edit a build, start-up, settings or instructions file, say so in the plugin's README; otherwise do not write it. Write the path in the call as fixed text, so that the directory can read it.
This mod writes to a path that is not fixed text, which can be a build, start-up or settings file. What is written to a file that other tools run or obey takes effect outside this mod. Writes of this kind that the directory recorded in the mod: 1; the line given is the first.
hooks/handoff.ts · line 174 · 


MOD_WRITES_BUILD_FILE

Policy hold:
Hook can approve tool calls or change their input
Policy hold · hooks/hooks.json · PreToolUse

To remove this finding, don't let the hook approve a tool call or change the call's input. The hook can deny the call or leave the decision to Claude Code's normal permission flow, and a PreToolUse hook can ask the user.
As far as this check can tell, a hook in this plugin can approve tool calls without asking the user, or change a tool call's input before it runs. Such a hook can change what the user is asked to decide, or whether they are asked at all.
hooks/hooks.json · PreToolUse · 


HOOK_GRANTS_PERMISSION

Policy hold:
The directory couldn’t confirm that the mod stays the same after it’s checked
Policy hold · scripts/_lib_drive.sh

Name only files in folders that hold no file of the mod, and write each path out (no wildcard, no variable). The plugin is not refused: a reviewer reads it before this version of the plugin is listed.
File scripts/_lib_drive.sh has a word that can name "hooks/handoff.ts", a file that loads as part of this plugin's mod (the word as the directory read it: (hooks/handoff.ts);). The word does not start at the plugin's root, and the directory does not know which folder it is under. Claude Code loads a mod's files itself, and a command that names one can change it after the directory has read it. The directory cannot tell whether a command reads the file or writes to it, so the plugin is held for review.
scripts/_lib_drive.sh · 


COMMAND_NAMES_MOD_FILE

Policy hold:
Uses a credential from the user’s machine
Policy hold · .claude-plugin/plugin.json

If the part that reads the credential and the part that sends data are related, pass a ${user_config.KEY} value the user chose to share instead of reading the installer's credential. If they are unrelated, you can leave them as they are and a reviewer confirms it, or remove every part that reads a credential, which clears this hold.
Across its surfaces this plugin reads the installer's PWD (file bin/handoff-approved) and can send data off the machine (file bin/handoff-approved: a command assembled at run time: $DRIVE_STATE\). Read together that is a credential leaving the machine in two steps; held for review beside the per-surface findings.
.claude-plugin/plugin.json · 


MCP_FORWARDS_CREDENTIAL_ENV

Policy hold:
Scripts the validator couldn’t follow
Policy hold · scripts/write-guard.sh

Point each command at a plain shell script by a literal path under CLAUDE_PLUGIN_ROOT, and keep npx, uvx and package installs out of it. A file that script runs in turn isn’t followed and always goes to a reviewer. Leaving the scripts as they are and waiting for the review is also fine.
The plugin's commands run files the validator could not check for the paths they use: scripts/write-guard.sh, scripts/inject-checkpoint-root.sh (program named by a pattern (*, ? or [) that may read code from its input), scripts/session-pointer.sh, scripts/load-handoff.sh, scripts/load-compact.sh, ., scripts/report-drive-failure.sh. Only this repository was validated, and these files could reach outside it (other installed plugins, the installer's files, the user's project) or run text the validator never checked, so a reviewer will read them before this version is listed. A file is followed automatically only when a command names it by a literal path such as ${CLAUDE_PLUGIN_ROOT}/<file> and it is a plain shell script that computes no path (no shell variables other than CLAUDE_PLUGIN_ROOT, no substitutions, no wildcard or brace patterns), runs no package launcher (npx, uvx …) or package-manager install, and feeds no program a here-document. Everything else is listed here: another program, a directory handed to a program, a script that computes a path, a script that runs or names a launcher or install, or hands a here-document to a program (the launcher is judged like a declared one, and the rest of the script, the document's text included, is the reviewer's to read), and any file a followed script runs or names in turn, because scripts are followed one level deep.
scripts/write-guard.sh · 


COMMAND_SCRIPT_NOT_FOLLOWED

Avertissement:
Unrecognized field in plugin.json
3 résultats

If you expected the field to do something, check its spelling against the plugins reference. Otherwise it can stay.

Remarque:
Mod hooks an event that settings, instructions, other hooks, or tool descriptions pass through
hooks/handoff.ts · line 44

Say in the plugin's README what the hook changes.

Remarque:
Mod hooks an event that is also the name of a call, so it may see or change that call when other code makes it
hooks/handoff.ts · line 63

Say in the plugin's README what the hook does.

Remarque:
Mod writes files
hooks/handoff.ts · line 174

Say in the plugin's README what the mod writes.

Remarque:
Images and fonts passed without a code check
.claude-plugin/plugin.json

1 well-formed image or font file(s) were let through without being read as code (their printable text was still screened): .claude-plugin/icon.png.

Remarque:
Hook is written as one line of text, not command and args
4 résultats

Put the interpreter in command and the rest in args, the file first, for example "command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/check.mjs", "--event", "PreToolUse"]. The program must be one the user's system finds by that name: on Windows a real .exe, and no single name for Python is found on every system. If the interpreter is bash or sh: on Windows, Claude Code runs the one-line form in Git Bash today and does not do so for a hook with args, so the hook then starts only where Windows itself finds bash or sh on the PATH. A node file avoids this.

Remarque:
Frontmatter value may be misread
2 résultats

If the value is text, put all of it in double quotes, for example description: "Use when: the build fails (#3)", and inside the quotes write \" for a double quote and \\ for a backslash. If it is a list or a set of keys, change what the message names. If a # was meant as a comment, move it to a line of its own.

Remarque:
Hooks of type command accepted only from Verified organizations
hooks/hooks.json

This isn’t refused yet. Later, the directory will accept command hooks only from Verified organizations, and your organization isn’t one.

Remarque:
Mods accepted only from Verified organizations
hooks/hooks.json · modules

This isn’t refused yet. Later, the directory will accept mods only from Verified organizations, and your organization isn’t one.

6 of 7 checks passed

Suivant
Fix 2 blocking issues and re-validate
Recommencer
```

## What cleared the blocking issues

Each row is a pushed probe of the `dist` tree, validated in the portal. Hook scripts were replaced by stubs to isolate the cause.

| Probe | Result |
| --- | --- |
| All six hook scripts stubbed | no blocking issue |
| Only `write-guard.sh` real | `UNPINNED_NPX` |
| `write-guard.sh` without its nested `${name%"${name##*[![:space:]]}"}` | no blocking issue |
| Only `load-compact.sh` real | no blocking issue, `.` listed as an unfollowed file |
| `load-compact.sh` with `msg="$msg."` instead of `msg+="."`, full tree | `.` no longer listed |
| Full tree without the nested expansion | `COMMAND_PATH_COMPUTED` |
| Only `write-guard.sh` and `report-drive-failure.sh` real | `COMMAND_PATH_COMPUTED` |
| That pair, with the inline `python3 -c` removed from `write-guard.sh` | no blocking issue |
| Full tree, inline program moved to `scripts/_guard_paths.py` | passed: 3 warnings, 11 policy holds |

Why `COMMAND_PATH_COMPUTED` needs both scripts is not explained. `load-handoff.sh` keeps an inline `python3 -c` and the final tree passes. The dot-source in `scripts/inject-checkpoint-root.sh` was a suspect and did not cause either issue; it now uses the same `source` line as the other hook scripts. Removing the mod path from the `scripts/_lib_drive.sh` comments cleared one hold, from 12 to 11.
