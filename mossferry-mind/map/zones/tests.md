---
type: zone
summary: "Bash test harness (tests/): run.sh drives test-mossferry, test-repo-session, test-install, test-ui-ops, test-fleet-devlog with fake-tmux and fake-bin stubs — no framework beyond bash."
tags: [tests, harness, fakes]
status: active
created: 2026-07-21
updated: 2026-07-29
verifiedAt: f57de42d
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

`tests/test-servers.sh` covers `lib/servers.sh` fixture-driven discovery,
mac_state, fix_plan, agent-status rows, and `--servers` helpers.

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
