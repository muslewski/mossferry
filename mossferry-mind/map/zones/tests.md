---
type: zone
summary: "Bash test harness (tests/): run.sh drives test-mossferry, test-repo-session, test-install, test-ui-ops, test-fleet-devlog with fake-tmux and fake-bin stubs — no framework beyond bash."
tags: [tests, harness, fakes]
status: active
created: 2026-07-21
updated: 2026-07-30
verifiedAt: d8df0027
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
mac_state, fix_plan, agent-status rows, and hermetic `--servers` fixture rows
(live `picker-servers-rows` is labeled integration and may SKIP when empty).

Product-facing **test suite**: plain bash, fake `tmux` / `mosh` / `ssh`,
covers client launch/doctor/update paths, remote picker/claim/validate, install
idempotency, TTY vs non-TTY UI ops tokens, and fleet-devlog XDG-isolated cases
(including `repo_id` shape, symlink containment, fail-closed machine config).
Entry: `bash tests/run.sh` or `npm test`.

## Anchors

- `tests/**` — harness, test modules (`test-mossferry`, `test-repo-session`,
  `test-install`, `test-ui-ops`, `test-fleet-devlog`, `test-servers`), `fake-bin/`,
  `fake-tmux`.
- Boundary: tests only; not demo VHS fixtures (see [[demo]]).

## Invariants

- **Suite result must not depend on this desk's node shim.** Fleet-devlog
  extracts JSON with pure `awk`. The helper is `devlog_xdg_tmp` (XDG only —
  does not claim full HOME isolation). Wired blocks that set `HOME` restore it.
  Optional JS dual-source uses `FLEET_REPO_ID_JS` + pre-captured `SUITE_NODE_BIN`
  and **SKIP**s visibly when absent — never a hardcoded `/home/kento/...` path.
- **Harness failures are textually distinct:** `FAIL harness: …` / `HARNESS_FAIL`
  never `|| echo parse-fail` into a value compared as product output. See
  [[2026-07-30-hermetic-home-no-node-shim]], [[2026-07-30-harness-vs-assert]].

## Lineage

README Testing section + `tests/` tree on 2026-07-21 atlas-seed pass.
