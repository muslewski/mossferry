---
type: decision
summary: "A test suite result must not depend on this desk's node shim; harness failures must be textually distinct from product assertion failures — this repo has paid for that lesson three times."
status: active
date: 2026-07-30
decided: 2026-07-30
tags: [tests, hermetic, fleet-devlog, harness]
related:
  - "[[client]]"
  - "[[tests]]"
  - "[[2026-07-30-hermetic-home-no-node-shim]]"
  - "[[0002-fleet-devlog-handrolled-json]]"
---

## Context

Cold review of `integration/desk-hardening` returned **DO NOT SHIP**: the suite
was a false-green machine under desk `nvm` and red under a cold PATH. Five
fleet-devlog failures showed correct product JSON while extraction returned
empty / `parse-fail` / `no-event` because the desk `node` shim exits 127 when
`$HOME` has no nvm. That same class previously cost this repo a child and
agentic-sage on the order of **193** misread failures.

A second recurring trap: reporting harness failure with the same shape as a
product assertion (`got=` empty while `line=` is full valid JSON) steers the
next agent to "fix the emitter" instead of "fix the harness".

## Decision

1. **Suite result is desk-independent.** Fleet-devlog field checks use pure
   `awk`. No test may require the desk PATH node shim. Optional JS
   cross-tool checks use `FLEET_REPO_ID_JS` + a binary captured before any
   XDG/HOME isolation (`DOGFOOD_NODE_BIN` / nvm v24 absolute path) and
   **SKIP** with a named message when the dependency is absent.
2. **Never embed absolute desk paths** in the OSS test surface
   (`/home/kento/...` is forbidden).
3. **Harness vs assert is textual.** Failures from missing tools, empty
   event files when the harness could not run, or interpreter exit use
   `FAIL harness: …` (or `HARNESS_FAIL`). Never `|| echo parse-fail` into a
   value that is then compared to an expected product field.
4. **Helper names must not overstate guarantees.** `devlog_xdg_tmp` sets
   XDG roots only; it does not claim full hermetic HOME. Call sites that
   set `HOME` must restore it.

## Consequences

- Cold PATH and desk PATH must yield the same fleet-devlog outcome
  (pass/skip names), modulo only visible skips for optional host deps.
- Reviewers grepping suite output for `harness:` can separate env breakage
  from product regressions without re-running under nvm.
