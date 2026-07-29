---
type: zone
summary: "Bash test harness (tests/): run.sh drives test-mossferry, test-repo-session, test-install, test-ui-ops, test-fleet-devlog with fake-tmux and fake-bin stubs — no framework beyond bash."
tags: [tests, harness, fakes]
status: active
created: 2026-07-21
updated: 2026-07-30
verifiedAt: 572e95f6
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
idempotency, TTY vs non-TTY UI ops tokens, and fleet-devlog hermetic cases
(including `repo_id` main/worktree/outside-git/JS-match/fail-open). Entry:
`bash tests/run.sh` or `npm test`.

## Anchors

- `tests/**` — harness, test modules (`test-mossferry`, `test-repo-session`,
  `test-install`, `test-ui-ops`, `test-fleet-devlog`, `test-servers`), `fake-bin/`,
  `fake-tmux`.
- Boundary: tests only; not demo VHS fixtures (see [[demo]]).

## Invariants

- **Hermetic HOME blocks must not invoke the desk `node` shim** to parse
  fleet-devlog JSON. The shim (`~/.local/bin/node` → nvm under `$HOME/.nvm`)
  exits 127 when HOME is a temp dir; `2>/dev/null || echo parse-fail` then
  reports empty fields as if the emitter were broken. Use pure `awk` field
  extraction (pattern already in `wired-doctor-emits`). When a test must
  call a real JS tool, capture `DOGFOOD_NODE_BIN` / nvm v24 path **before**
  hermeticizing and fail with a `harness:` message if it is missing — never
  mask extraction failure as an assertion failure. See
  [[2026-07-30-hermetic-home-no-node-shim]].

## Lineage

README Testing section + `tests/` tree on 2026-07-21 atlas-seed pass.
