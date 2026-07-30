---
type: decision
summary: "Removed six vendored atlas skill copies from mossferry; single source is user-scope ~/.claude/skills/ (canonical memory-atlas package). Two divergences were stale older prose, not improvements."
status: active
date: 2026-07-30
decided: 2026-07-30
tags: [atlas, skills, user-scope, collapse, vendoring]
related:
  - "[[2026-07-30-survivors-reconcile]]"
---

## Decision

Delete the six vendored skill trees under `.claude/skills/` and stop
recording them in `.atlas-state.json`. Agents install atlas skills once
at user scope (`~/.claude/skills/`). Verify with
`test -f ~/.claude/skills/atlas-nav/SKILL.md`.

## Six copies removed

| skill | vendored sha256[:8] | user-scope sha256[:8] | relation |
|---|---|---|---|
| atlas-nav | 1e4276d9 | 1e4276d9 | byte-identical |
| atlas-adopt | b59f1e80 | b59f1e80 | byte-identical |
| atlas-update | 02174472 | 02174472 | byte-identical |
| atlas-seed | 4e2b2726 | 4e2b2726 | byte-identical |
| writing-for-retrieval | 8c44453b | 1ebfbfbb | diverged (vendored older) |
| atlas-recollection | b331ce5d | 709627d9 | diverged (vendored older) |

Canonical source of truth: `memory-atlas/skills/<name>/SKILL.md` (npm
package file list). User-scope hashes match canonical for all six at the
time of this collapse.

## Divergence detail (read before delete)

### writing-for-retrieval (8c44453b → 1ebfbfbb)

Vendored lacked the trailing `## Bootstrap vs edit` section that
canonical has (empty vault → atlas-seed; ongoing → writing-for-retrieval +
atlas-recollection). No unique content in the vendored copy.

### atlas-recollection (b331ce5d → 709627d9)

Vendored used a single "Rebuild and check" bullet claiming `atlas check`
regenerates `map/index.md`. Canonical has:

- Worker vs integrator split (workers must not `atlas build` / stage index)
- merge-driver safety net note
- Docs soft-nudge checklist for public `docs/`

Vendored had **no** unique improvement over canonical; discarding is safe.

## State file

`.atlas-state.json` skill keys removed via `memory-atlas` `writeState`
after `git rm` (same shape agentic-sage collapse used under installed
0.5.3 doctor, which has no `source: user-scope` yet). On-ramp block hashes
for CLAUDE.md / AGENTS.md left unchanged by writeState; content edits to
those files live outside or inside onramp as committed.

## Transitional issue

Installed atlas 0.5.3 still nudges:

`⬆ atlas 0.5.3 installed, wired 0.4.0 — run the atlas-update skill (.claude/skills/atlas-update/SKILL.md)`

That path no longer exists in-repo until a newer atlas (with user-scope
nudge path) is installed here. Do not re-vendor the skill to paper over
the nudge. Fix: bump memory-atlas and run atlas-update when ready.

## Tech-debt dir consolidation

Chose **`mossferry-mind/tech-debt/`** only — matches
`atlas.config.json` → `folders.techDebt: "tech-debt"`. The alternate
`mossferry-mind/map/tech-debt/` was already removed on main; survivors
reconcile folded `2026-07-30-brutality-deferred.md` into
`tech-debt/2026-07-30-survivors-reconcile.md`. No second debt home remains
on this branch.

## Salvage (same series)

From `chore/atlas-0.5.3-telemetry-on` (not its `.atlas-state.json`):

1. `.agentic-sage/adapter.mjs` — peer-identical (agentic-sage / llm-armory /
   eventizer, sha256 7c18a2f7…)
2. sage-fleet-pointer blocks in AGENTS.md / CLAUDE.md
3. package.json atlas scripts + `devDependencies.memory-atlas` pin **0.5.3**
   (exact; matches installed node_modules and peer eventizer; not caret so
   this collapse stays on the verified toolkit)

Kept main's `desk:ship=human-end-gate` and full CLAUDE pipeline / docs
soft-nudge (telemetry branch had truncated that).

## Single source now

`~/.claude/skills/<name>/SKILL.md` (user scope), content-equal to
`memory-atlas` package skills at install time.
