---
type: debt
summary: "Standing landmine: any new hermetic-HOME test that shells out to PATH node (desk nvm24 shim) will false-fail; awk helpers exist in test-fleet-devlog.sh — copy them, do not reintroduce node -e under hermetic blocks."
tags: [tests, hermetic, node-shim, fleet-devlog]
status: open
created: 2026-07-30
updated: 2026-07-30
severity: high
effort: "small per new test; large if re-discovered after green reports"
related:
  - "[[tests]]"
  - "[[client]]"
  - "[[2026-07-30-hermetic-home-no-node-shim]]"
sources: []
---

## What's deferred

No shared test-lib yet for JSON field extraction across `tests/test-*.sh`.
Helpers live only in `tests/test-fleet-devlog.sh`. Other modules
(`test-servers.sh` still has a `node -e` JSON length parse) can trip the same
shim under a future hermetic HOME.

## Why

Extracting a shared `tests/lib/json-awk.sh` is a small refactor, not required
to fix the five `repo-id-*` failures. Documenting the trap matters more than
DRY today — this failure mode has already produced false-green reports from
multiple children in this fleet.
