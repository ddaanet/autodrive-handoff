# inbox

Where a session working in another repository drops a brief, note or finding
that concerns the handoff plugin.

Drop the file here, not at the repo root. A brief at the root is easy to
mistake for a tracked project document.

`plans/` is for this repo's own prospective work — specs, design proposals,
implementation plans a handoff session wrote for itself. `inbox/` is for what
arrives from outside. Triaging an inbox file usually means acting on it and
deleting it, or promoting it into `plans/` if it becomes work this repo will
schedule.

A brief's recommendation is input, not a decision: it was written by an agent
that could not verify this repo's constraints, so surface the choice before
implementing it.

Git does not track empty directories, which is why this file exists.
