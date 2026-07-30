---
type: zone
summary: "Bash test harness (tests/): run.sh drives test-mossferry, test-repo-session, test-install, test-ui-ops, test-fleet-devlog with fake-tmux and fake-bin stubs — no framework beyond bash."
tags: [tests, harness, fakes]
status: active
created: 2026-07-21
updated: 2026-07-30
verifiedAt: 9cea64cf796c14fea10f4528465cd1eda781c438
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
  and **SKIP**s visibly when absent — never a hardcoded `/home/<user>/...` path.
- **t45 is PATH-honest:** picker-preview chrome must pass with a broken `node`
  first on PATH (product uses awk, not `node -e`). Same verdict under desk PATH
  and `PATH=/usr/bin:/bin:/usr/local/bin`.
- **Harness failures are textually distinct:** `FAIL harness: …` / `HARNESS_FAIL`
  never `|| echo parse-fail` into a value compared as product output. See
  [[2026-07-30-hermetic-home-no-node-shim]], [[2026-07-30-harness-vs-assert]].
- **`tests/test-macos-compat.sh` is a static portability fence** (32 assertions)
  over `bin/*`, `lib/*.sh`, `install.sh`. Needs no Mac, tmux, mosh, fzf, ss, or
  network. Deliberate exceptions carry a trailing `# portable-ok: <reason>` — never
  loosen the patterns. It is quote- and comment-aware, so a tool name in a comment
  or inside a message string is not read as a call.
- **The fence does NOT scan `tests/`**, so the harness can still be unportable
  while the product is clean. That gap is real: a `timeout 8` inside
  `test-ui-ops.sh` failed with rc=127 on every Mac (no `timeout`/`gtimeout` on
  stock macOS) and the fence could not see it. Tech-debt: extend the scan.
- **The suite itself must parse under bash 3.2.** A heredoc inside `$( )` is a
  bash 3.2 *parse* error, so it killed all 54 assertions in
  `test-repo-session.sh` on every Mac before one of them ran. Use
  `IFS= read -r -d '' var <<'EOF' … EOF || true` and strip the trailing newline
  (`$()` strips it, `read` does not).
- **Compare physical paths, not logical ones.** `readlink -f` against a `pwd`-derived
  `ROOT` fails on macOS because `/tmp` is a symlink to `private/tmp`; resolve both
  sides with `pwd -P`. This repo also deliberately never depends on GNU
  `readlink -f` (absent on macOS without coreutils).
- **A green Linux suite says nothing about macOS.** Three of seven modules were
  failing or not parsing on the Mac while Linux was green. Baseline any macOS
  failure against the pre-change commit before calling it a regression, and export
  the real user PATH first — `node` is absent from a non-interactive ssh PATH on
  that Mac. See [[2026-07-30-macos-bash32-portability]].

## Lineage

README Testing section + `tests/` tree on 2026-07-21 atlas-seed pass.
