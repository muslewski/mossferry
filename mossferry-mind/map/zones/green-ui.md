---
type: zone
summary: "Vendored GREEN-UI-KIT (lib/green-ui.sh): source-able bash UI library — detect_color, ui_tty, banner/ok/warn/die/panel/checklist; stdout=data stderr=chrome; missing kit never kills ferry tools."
tags: [ui, tty, green-ui-kit]
status: active
created: 2026-07-21
updated: 2026-07-30
verifiedAt: 69e11f9b
owns:
  routes: []
  testids: []
  globs:
    - "lib/green-ui.sh"
  tools: []
depends: []
invariants: []
skills: []
related:
  - "[[client]]"
  - "[[repo-session]]"
  - "[[install-config]]"
sources: []
---

## What this is

Pinned vendored copy of **GREEN-UI-KIT** used for TTY-gated ops chrome across
`bin/mossferry`, `bin/repo-session`, and `install.sh`. Provides color mode
detection, glyph sets, banners, checklists, and panels. Law: **stdout =
data/records; stderr = chrome** (with documented exceptions for choose /
sparkline / table).

## Anchors

- `lib/green-ui.sh` — sole owned surface (other `lib/*` files belong to their feature zones).
- Consumers load it from repo root; each binary also defines
  `_ferry_ui_fallbacks` so a missing file degrades to monochrome tokens.

## Invariants

None enforced-by on seed. README product rule to confirm later:

- Non-TTY / pipes / CI stay monochrome and parse-stable (`ok` / `FAIL` /
  version lines).
- Array expansions use `${arr[@]+"${arr[@]}"}` so an empty array cannot abort a
  caller under macOS bash 3.2 + `set -u`. The file header still advertises
  "bash >= 4"; the intent is that the UI **degrades** on 3.2 rather than dying, and
  the consumers (`bin/mossferry`, `bin/repo-session`, `install.sh`) already install
  inline fallbacks when this library is missing or unusable.
  See [[2026-07-30-macos-bash32-portability]].

## Lineage

Header pin note in `lib/green-ui.sh` (GREEN-UI-KIT 0.1.0). Seeded 2026-07-21
from tree + README "Ops screens (v2.5.0)".
