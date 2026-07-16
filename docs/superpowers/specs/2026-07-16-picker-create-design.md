# picker create rows (new repo + home session) — design spec

**Date:** 2026-07-16 · **Status:** approved · **Version target:** 2.1.0

## Problem
The new-session chain can only pick an EXISTING directory under `FERRY_REPO_BASE`. Two real cases are unsupported: starting a brand-new repo, and a deliberate repo-less session at `$HOME` (the legitimate rebirth of the old `main` — chosen, never forced).

## Behavior

**Global new-session chain** (`➕ new session…` from the global picker) lists, in order: repo dirs, `➕ new repo…`, `🏠 home session…`. The repo-scoped picker's chain stays pre-filtered to that repo — no special rows there. The no-fzf fallback repo menu gains `r) new repo` and `h) home session`.

**`➕ new repo…`** → prompt `new repo name: ` (from `/dev/tty`). Name must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`. Invalid name or existing directory → one-line message, reload picker. Valid → `mkdir` under `FERRY_REPO_BASE` + `git init -q -b main`, then create + attach the session there via the existing lock-guarded path (honors `--claude` / `-- cmd…`).

**`🏠 home session…`** → prompt `session name [home]: ` (empty → `home`; same name regex). Creates the session with cwd `$HOME` (no repo, no git), honoring `--claude` / `-- cmd…`. If a session with that name already exists, attach it (`-A` semantics). Home sessions are ordinary sessions afterwards: they appear in the global picker, kill/rename work, grid claim flags ignore them (repo-scoped by design).

**LIB exports for tests:** `create_repo <name>` (validate + mkdir + git init, no tmux), `create_home_session <name>` (tmux create at `$HOME` + startcmd + attach).

## Acceptance
- t21 `create_repo side-quest` → dir + `.git` exist under a mktemp base; t22 invalid name (`../evil`, `has space`) → nonzero, nothing created; t23 existing dir → nonzero, message; t24 `create_home_session home` → fake-tmux log has `new-session -d -s home -c $HOME` then attach; t25 existing-name home session → attach only, no new-session.
- Existing tests t1–t20, m1–m14, install tests: green, assertions unmodified.
- README picker section documents both rows. `/dev/tty` prompts stay on the manual checklist.
