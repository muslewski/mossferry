# picker AI launchers — Implementation Plan

> One sequential armory child. Spec: `docs/superpowers/specs/2026-07-17-picker-launchers-design.md` — its Behavior + Acceptance sections ARE the contract; round-1 Global Constraints still bind.

### Task: the launchers child (worktree `mossferry-launchers`)

**In scope:** `bin/repo-session`, `tests/test-repo-session.sh`, `README.md`, `config.example`.

**Steps:** TDD — write failing t29–t32 per the spec's Acceptance; implement `parse_launchers` + `launcher_cmd` (LIB-exported), launcher keys in the `--expect` lists of the main picker and destination sub-picker, the armed-launcher start-command override (beats FERRY_DEFAULT_CMD / --claude / `-- cmd`), the dynamic sub-picker hints line; green; commit per milestone.

**Verify:** `bash tests/run.sh`; `bash -n bin/repo-session`; `git grep -iE '\bmoshi\b|/home/kento|/Users/muslewski' -- bin tests README.md` empty.

**Advisor after receipt:** gate, merge `--no-ff`, suite on main, VERSION → 2.3.0, push github, `ferry update` on Mac, manual checklist: ctrl-a/ctrl-g on repo, home, new-repo, and scoped new-session rows; enter unchanged.
