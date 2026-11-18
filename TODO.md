## Open decisions

- A frame over Claude Code's hook-output limit reaches every session as a 2KB `<persisted-output>` preview, and nothing tells the agent the rest of `TODO.md` exists; `pending` now reads the file, nothing else does. Whether the loader should inject less once the frame is large (the current task plus a count and a pointer to `TODO.md`), and at what size: the limit was not measured (20.1KB was over it, on 2.1.323).
