# picker create rows — Implementation Plan

> One sequential armory child. Spec: `docs/superpowers/specs/2026-07-16-picker-create-design.md` — its Behavior + Acceptance sections ARE the contract; round-1 Global Constraints still bind.

### Task: the create-rows child (worktree `mossferry-create-rows`)

**In scope:** `bin/repo-session`, `tests/test-repo-session.sh`, `tests/fake-tmux` (only if the stub needs `-c` path logging it lacks), `README.md` (picker section: the two new rows, one line each).

**Steps:** TDD — write failing t21–t25 per the spec's Acceptance; implement `create_repo`, `create_home_session`, the two picker rows (global chain only) + fallback `r)`/`h)` entries + `/dev/tty` prompts with reload-on-invalid; green; commit per milestone.

**Verify:** `bash tests/run.sh`; `bash -n bin/repo-session`; `git grep -iE '\bmoshi\b|/home/kento|/Users/muslewski' -- bin tests README.md` empty.

**Advisor after receipt:** gate, merge `--no-ff`, suite on main, VERSION → 2.1.0, `ferry update` on Mac, manual checklist: global picker → new session → new repo flow; → home session flow; scoped picker unchanged.
