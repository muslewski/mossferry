# responsive banner v2 + cyclic picker — Implementation Plan

> One sequential armory child. Spec: `docs/superpowers/specs/2026-07-17-banner-v2-cycle-design.md` — its Art + Behavior + Acceptance sections ARE the contract (art byte-exact after ANSI strip); round-1 Global Constraints still bind.

### Task: the banner-v2 child (worktree `mossferry-banner2`)

**In scope:** `bin/repo-session`, `bin/mossferry`, `tests/test-repo-session.sh`, `tests/test-mossferry.sh`, `README.md`.

**Steps:** TDD — update t26/t27/t28/m16 and add failing t33–t35 per the spec's Acceptance; implement the width-tiered `ferry_banner [width]` (both scripts, keep-in-sync), the main picker's 40%-width call, `--cycle` on all three fzf invocations; green; commit per milestone.

**Verify:** `bash tests/run.sh`; `bash -n bin/repo-session`; `bash -n bin/mossferry`; `git grep -iE '\bmoshi\b|/home/kento|/Users/muslewski' -- bin tests README.md` empty.

**Advisor after receipt:** gate (including byte-diff of all three art tiers), merge `--no-ff`, suite on main, VERSION → 2.4.0, push github, `ferry update` on Mac, manual checklist: wide/medium/small tiers + wrap-around scroll.
