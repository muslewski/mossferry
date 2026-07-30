---
type: zone
summary: "Remote brain (bin/repo-session): fzf/menu session picker + servers face (ctrl-s), create/attach, atomic claim, nested start menu, FERRY_LAUNCHERS, Grok wallet badge, FERRY_SAGE wire, kill/rename, --servers discovery, validate_repo."
tags: [remote, tmux, picker, fzf, sage, grok]
status: active
created: 2026-07-21
updated: 2026-07-30
verifiedAt: 5f96f1c1
owns:
  routes: []
  testids: []
  globs:
    - "bin/repo-session"
    - "lib/servers.sh"
  tools: []
depends:
  - "[[green-ui]]"
invariants:
  - "Curated --help keeps a Flags section heading (exact case) for test-ui-ops f3-repo-session-help; body stays an index not a full flag wall."
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
`create_repo` / home sessions, **nested start menu** (`FERRY_START_MENU`) plus
optional **FERRY_LAUNCHERS** hotkeys, in-place kill/rename binds, and
`--validate` for local typo checks. Errors are prefixed `repo-session:`.

## Anchors

- `bin/repo-session` — sole owned surface; path on remote often
  `$HOME/.local/bin/repo-session` via `FERRY_REMOTE_BIN`.
- Boundary: tmux + fzf interaction and session naming; no mosh client code.

## Invariants

- **Repo tokens are path-safe:** `_ferry_repo_token_ok` rejects `/`, `..`, and
  non-basename shapes before joining with `FERRY_REPO_BASE`. `validate_repo`
  and attach paths refuse traversal; claim lock files use a sanitized
  basename (`_ferry_claim_lockf`), never raw `$repo` with slashes.
- **Session filter is fixed-string:** `build_session_rows` /
  `_list_repo_sessions` never interpolate `$repo` into `grep -E` (dots in
  `o'neil-file.txt` must not match `o'neil-fileXtxt`).
- **create_repo self-heals:** if `git init` fails, an empty non-git directory
  is removed so retry is not blocked by "already exists".
- Scoped `--list <repo>` validates the repo exists (vanished trees are not
  silent empty success).
- Default action is the picker; attach-primary is `--primary` / `-p`.
- Zero live sessions for `ferry <host> <repo>` fast-path creates + attaches
  primary without showing the empty picker.
- `ctrl-x` / `ctrl-r` reserved (kill/rename); not valid launcher keys.
- fzf kill/rename binds use full-line `{}` + tab-split for the session name
  (not `n="{1}"`).
- Main picker preview uses `--picker-preview` (sage chrome optional + capture);
  synthetic rows never call bare `capture-pane -t ''`.
- Optional **FERRY_SAGE** hybrid wire: when `sage` on PATH and not `off`, preview
  shows `sage about --tmux` facts/judge lines; **⚖ new judge…** runs
  `sage judge run --fleet|--repo`. Sage chrome JSON is parsed with awk (no
  `node -e`) so hermetic HOME / desk nvm shims cannot empty the preview.
- **desk:ship** is not yet shown on local status/list surfaces (deferred —
  [[2026-07-30-survivors-reconcile]]).
- Create path: destination first, then nested start menu when
  `FERRY_START_MENU` or launcher cmds are non-empty.
- Live Grok panes badge wallet from `GROK_HOME` (Linux `/proc` only).

## Lineage

Inferred from README picker/usage sections + `bin/repo-session` header on
2026-07-21 atlas-seed pass. Design history lives under `docs/superpowers/`
(not owned by this zone).
