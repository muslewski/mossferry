---
type: spec
summary: "Optional mossferry↔agentic-sage wire: auto one-liners (facts + judge) via sage about --tmux; ferry hybrid FERRY_SAGE adapter for picker preview chrome and ⚖ new judge… → sage judge run (fleet|repo). Neither product requires the other."
tags: [interop, picker, sage, judge, preview]
status: approved
created: 2026-07-24
---

# Ferry × SAGE optional wire — design

**Date:** 2026-07-24 · **Status:** approved · **Approach A**

## Problem

Mossferry is the tmux door (list / create / attach). Agentic-sage is the fleet mind (board, briefs, live judge). Owners of both want an **optional** wire so ferry navigation shows sage context and can spawn judge sessions — without making either tool depend on the other.

## Goals

1. Without sage (or `FERRY_SAGE=off`): ferry behavior identical to today.
2. With sage usable: picker preview shows sage **facts** one-liner and optional **judge** one-liner above pane capture.
3. One-liners are **produced automatically by sage** (lifecycle + `sage judge run` / publish), never authored by ferry.
4. Wired picker adds **⚖ new judge…** → fleet | repo → `sage judge run`.
5. Silent degrade on timeout/error/missing sage.

## Non-goals (v1)

- Ferry writing sage store / claims / briefs.
- Embedding Node into mossferry.
- Mac-side sage (remote host only).
- Multi-line essays; left-column chips; numbered-menu about lines.

## Ownership

| Product | Owns |
|---------|------|
| **agentic-sage** | Auto facts + judge one-liners; `sage about --tmux`; brief `session_lines`; SCHEMA |
| **mossferry** | `FERRY_SAGE` hybrid detect; preview adapter; create-judge UX; fake-sage tests |

## Enable (hybrid)

- Default **auto**: wire if `command -v sage` and `FERRY_SAGE` not in `off|0|false|no`.
- **Hard off:** `FERRY_SAGE=off`.
- **`on`:** prefer wire; if sage missing → silent off (doctor may note).
- Probe never blocks attach/kill; max ~250ms for about.

## SAGE: automatic one-liners

### Facts line

Derived at read time from session record fields (war-row spirit), e.g.:

`working · main · claim:src/** · syndcast`

No LLM. Always available when sage knows the session.

### Judge line (automatic on judge run)

- On **fact brief** (`harness none` / `judge run` fact path): for each live non-judge session in scope, write a short line into brief **`session_lines`** (tmux session key when known + session_id + text from facts).
- On **judge publish** (LLM or skill): accept optional `session_lines`; if omitted, keep prior lines or re-derive from hotspots/summary for v1.
- Freshness: same as brief (TTL + grace). Stale/offline → no judge line.

### `sage about --tmux <name> [--json]`

- Exit 0 always for not-found (ferry-friendly).
- Match: fleet scan where `tmux` pane target session equals name (`syndcast:0` → `syndcast`), else worktree basename, else window_name.
- JSON:

```json
{
  "schema": 1,
  "kind": "sage.about",
  "tmux": "syndcast",
  "found": true,
  "facts": "working · main · …",
  "judge": "optional one-liner or \"\"",
  "role": "worker",
  "liveness": "working",
  "session_id": "…",
  "repo_id": "…"
}
```

## Mossferry adapter

### Preview

When wired, preview command:

1. `sage about --tmux {1} --json` (timeout) → print non-empty facts/judge (+ separator).
2. Existing capture-pane guard for empty `{6}` (➕ row).

### Create

- Extra main-picker row when wired: `⚖ new judge…`
- Scope: fleet | pick repo under `FERRY_REPO_BASE`
- Create/attach tmux session with startcmd `sage judge run --fleet` or `sage judge run --repo` (cwd = repo or `$HOME` for fleet).
- Cancel → reload picker. Failure → message + reload.

### Doctor

One line: sage adapter auto|off|unavailable.

## Failure modes

| Case | Behavior |
|------|----------|
| No sage / off | No adapter |
| about timeout/error | Pane only |
| found false | Pane only |
| Judge create cancel | Reload picker |

## Success criteria

1. Host without sage: ferry unchanged.
2. With sage + sessions: preview shows facts; with live/grace judge + session_lines: judge line too.
3. ⚖ new judge creates attachable judge session.
4. `FERRY_SAGE=off` disables wire.
5. One-liners update when judge runs / sessions refresh without ferry writes.

## Work order

1. agentic-sage: about + session_lines + tests + SCHEMA
2. mossferry: adapter + tests + docs
