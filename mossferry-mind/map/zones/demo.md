---
type: zone
summary: "Demo recording pipeline (demo/) and published GIF assets (assets/): VHS tapes for picker/help/doctor, green-demo.sh, fixtures with stub ferry/mosh/ssh/tmux-greenui for offline capture."
tags: [demo, vhs, assets]
status: seeded
created: 2026-07-21
updated: 2026-07-21
verifiedAt: unverified
owns:
  routes: []
  testids: []
  globs:
    - "demo/**"
    - "assets/**"
  tools: []
depends:
  - "[[client]]"
  - "[[green-ui]]"
invariants: []
skills: []
related:
  - "[[tests]]"
sources: []
---

## What this is

Marketing and README demo media pipeline. **Tapes** under `demo/scenes/` and
`demo/house.tape` drive captures; `demo/fixtures/` supplies a mini home + PATH
stubs so recordings do not need a real remote. Rendered GIFs land in
`assets/` (`demo-picker`, `demo-help`, `demo-doctor`) and are embedded in the
README.

## Anchors

- `demo/**` — scripts, fixtures, scene tapes, build outputs under
  `demo/build/`.
- `assets/**` — committed demo GIFs for GitHub/README.

## Invariants

None on seed. Fixtures are for capture, not the unit-test harness.

## Lineage

Tree + README demo embeds on 2026-07-21 atlas-seed pass.
