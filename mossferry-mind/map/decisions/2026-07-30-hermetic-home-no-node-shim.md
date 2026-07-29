---
type: decision
summary: "Hermetic-HOME fleet-devlog tests must extract JSON with awk, never the desk node-from-nvm24 shim — that shim exits 127 under temp HOME and parse-fail masks hide harness breakage as product failures."
status: active
date: 2026-07-30
decided: 2026-07-30
tags: [fleet-devlog, tests, hermetic, node-shim]
related:
  - "[[client]]"
  - "[[tests]]"
  - "[[0002-fleet-devlog-handrolled-json]]"
---

## Context

Desk PATH puts `~/.local/bin/node` first. That binary is a **shim** that
resolves the real interpreter as:

```bash
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
base="$(ls -1d "$NVM_DIR/versions/node"/v24.* | sort -V | tail -1)"
```

Under `hermetic_home` (and any block that sets `HOME` to a temp dir with no
`.nvm`), the shim prints `error: no nvm Node ≥24` and exits **127**.

Five new `repo-id-*` tests in `tests/test-fleet-devlog.sh` reintroduced
`node -e` extractions wrapped as:

```bash
got=$(... | node -e '...' 2>/dev/null || echo parse-fail)
```

The emitter was correct (event lines already carried the right `repo_id`);
the harness could not read them. The same trap previously cost this repo a
child ("hermetic HOME broke node-from-nvm24") and agentic-sage on the order
of **193** test failures when suites assumed bare `node` under hermetic HOME.

There is no `jq` on this host — that is why the emitter hand-rolls JSON
([[0002-fleet-devlog-handrolled-json]]).

## Decision

1. **Extract JSON fields with pure `awk`** in fleet-devlog (and any other)
   hermetic tests. No `$HOME` dependency. Match the existing
   `wired-doctor-emits` pattern.
2. When a test **must** run a JS tool (cross-tool `repo_id` compare against
   `agentic-sage/lib/repo-id.mjs`), resolve a real Node ≥24 binary **once at
   suite load** via `DOGFOOD_NODE_BIN` or `$NVM_DIR/versions/node/v24.*/bin/node`,
   and invoke that absolute path. Do not rely on the PATH shim after HOME
   changes.
3. **Never mask harness failure as assertion failure.** If extraction or the
   JS interpreter is unavailable, `FAIL` with a message that starts with
   `harness:` (distinct from product `got=` / `want=` failures).
4. Do **not** modify the human's `~/.local/bin/node` shim — the suite adapts.

## Consequences

- `tests/test-fleet-devlog.sh` carries shared `json_str` / `json_str_status` /
  `json_counts_num` helpers and `resolve_suite_node`.
- Future hermetic tests that call `node` without a pre-captured binary are a
  known landmine; stamp this decision when reviewing fleet-devlog harness PRs.
