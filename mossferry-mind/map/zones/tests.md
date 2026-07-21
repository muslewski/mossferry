---
type: zone
summary: "Bash test harness (tests/): run.sh drives test-mossferry, test-repo-session, test-install, test-ui-ops with fake-tmux and fake-bin mosh/ssh stubs — no framework beyond bash."
tags: [tests, harness, fakes]
status: seeded
created: 2026-07-21
updated: 2026-07-21
verifiedAt: unverified
owns:
  routes: []
  testids: []
  globs:
    - "tests/**"
  tools: []
depends:
  - "[[client]]"
  - "[[repo-session]]"
  - "[[install-config]]"
  - "[[green-ui]]"
invariants: []
skills: []
related: []
sources: []
---

## What this is

Product-facing **test suite**: plain bash, fake `tmux` / `mosh` / `ssh`,
covers client launch/doctor/update paths, remote picker/claim/validate, install
idempotency, and TTY vs non-TTY UI ops tokens. Entry: `bash tests/run.sh` or
`npm test`.

## Anchors

- `tests/**` — harness, four test modules, `fake-bin/`, `fake-tmux`.
- Boundary: tests only; not demo VHS fixtures (see [[demo]]).

## Invariants

None claimed on seed. Suite is the future `enforcedBy` home for client and
repo-session parse-stable tokens.

## Lineage

README Testing section + `tests/` tree on 2026-07-21 atlas-seed pass.
