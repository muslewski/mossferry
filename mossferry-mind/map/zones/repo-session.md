---
type: zone
summary: "Remote brain (bin/repo-session): fzf/menu tmux session picker, create/attach, atomic grid claim (--resume-closed / --resume-or-new), AI launchers, validate_repo, ferry banner header."
tags: [remote, tmux, picker, fzf]
status: seeded
created: 2026-07-21
updated: 2026-07-21
verifiedAt: unverified
owns:
  routes: []
  testids: []
  globs:
    - "bin/repo-session"
  tools: []
depends:
  - "[[green-ui]]"
invariants: []
skills: []
related:
  - "[[client]]"
  - "[[install-config]]"
sources: []
---

## What this is

The **remote** half of mossferry. Installed on the host where tmux sessions
live. Owns all session logic: **picker** (fzf with preview, or numbered menu),
primary/new/list/resume flags, **atomic claim** for ghostty-grid drivers,
`create_repo` / home sessions, **FERRY_LAUNCHERS** AI start keys, and
`--validate` for local typo checks. Errors are prefixed `repo-session:`.

## Anchors

- `bin/repo-session` — sole owned surface; path on remote often
  `$HOME/.local/bin/repo-session` via `FERRY_REMOTE_BIN`.
- Boundary: tmux + fzf interaction and session naming; no mosh client code.

## Invariants

None claimed yet on seed. Candidates for later verification:

- Default action is the picker; attach-primary is `--primary` / `-p`.
- Zero live sessions for `ferry <host> <repo>` fast-path creates + attaches
  primary without showing the empty picker.
- `ctrl-x` / `ctrl-r` reserved (kill/rename); not valid launcher keys.

## Lineage

Inferred from README picker/usage sections + `bin/repo-session` header on
2026-07-21 atlas-seed pass. Design history lives under `docs/superpowers/`
(not owned by this zone).
