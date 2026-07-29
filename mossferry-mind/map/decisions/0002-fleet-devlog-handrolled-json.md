---
type: decision
summary: "Bash fleet-devlog emitter hand-rolls JSON because jq is not installed on the host; keep values to enums/numbers so escaping stays honest."
status: active
date: 2026-07-29
decided: 2026-07-29
tags: [fleet-devlog, bash, privacy]
related:
  - "[[client]]"
  - "[[tests]]"
---

## Context

W7 fleet-devlog needs a mossferry emitter matching the shared contract
(`fleet-devlog v1`). The three JS tools vendor a Node reference. mossferry is
pure bash. On the verified host (2026-07-29), **`jq` is not installed**.

## Decision

Implement `lib/fleet-devlog.sh` as a **hand-rolled JSON writer** with a minimal
surface:

```
devlog_emit <cmd> <exit> <ms> [key=value…]
```

Values are restricted to **numbers and enum tokens**. That restriction keeps
escaping honest — only `\` and `"` need escaping in string fields — and
prevents free-text (prompts, paths, keys) from entering the log by accident.

`counts.<name>=value` accepts numbers only; non-numeric values are dropped
silently (allow-list, not deny-list).

## Consequences

- No hard dependency on `jq` or any other JSON CLI.
- Emitter stays small and fail-open (unwritable root → log nothing).
- Must stay in lockstep with the Node reference field rules by human review
  (bash cannot share the byte-identical checksum test the JS tools use).
