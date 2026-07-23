# picker banner — Implementation Plan

> One sequential armory child. Spec: `docs/superpowers/specs/2026-07-17-picker-banner-design.md` — its Art + Behavior + Acceptance sections ARE the contract; round-1 Global Constraints still bind.

### Task: the banner child (worktree `mossferry-banner`)

**In scope:** `bin/repo-session`, `bin/mossferry`, `tests/test-repo-session.sh`, `tests/test-mossferry.sh`, `README.md`, `config.example`.

**Steps:** TDD — write failing t26–t28 + m16 per the spec's Acceptance; implement `ferry_banner` (both scripts, LIB-exported in repo-session), `--layout=reverse --header-first` + banner headers on both fzf invocations, fallback-menu + `--help` banner printing, `FERRY_BANNER` config key; green; commit per milestone.

**Verify:** `bash tests/run.sh`; `bash -n bin/repo-session`; `bash -n bin/mossferry`; `git grep -iE '\bmoshi\b|/home/kento|/Users/muslewski' -- bin tests README.md` empty.

**Advisor after receipt:** gate, merge `--no-ff`, suite on main, VERSION → 2.2.0, push github, `ferry update` on Mac, manual checklist: banner in real picker (full + short pane + off), reverse layout feel.
