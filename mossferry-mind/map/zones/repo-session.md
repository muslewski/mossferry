---
type: zone
summary: "Remote brain (bin/repo-session): fzf/menu session picker + servers face (ctrl-s), create/attach, atomic claim, nested start menu, FERRY_LAUNCHERS, Grok wallet badge, FERRY_SAGE wire, kill/rename, --servers discovery, validate_repo."
tags: [remote, tmux, picker, fzf, sage, grok]
status: active
created: 2026-07-21
updated: 2026-07-29
verifiedAt: 084738b8
owns:
  routes: []
  testids: []
  globs:
    - "bin/repo-session"
    - "lib/servers.sh"
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
`create_repo` / home sessions, **nested start menu** (`FERRY_START_MENU`) plus
optional **FERRY_LAUNCHERS** hotkeys, in-place kill/rename binds, and
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
- fzf kill/rename binds use full-line `{}` + tab-split for the session name
  (not `n="{1}"`). Modern fzf already shell-quotes placeholders; wrapping
  `{1}` in extra quotes made kill target `'name'` and fail silently. Full-line
  extract also keeps trailing-space names that field `{1}` would strip.
  `picker_kill` strips one layer of wrapping quotes as defense-in-depth.
- Main picker preview uses `--picker-preview` (sage chrome optional + capture);
  synthetic rows never call bare `capture-pane -t ''` (cycle-to-➕ no self-mirror).
- Optional **FERRY_SAGE** hybrid wire: when `sage` on PATH and not `off`, preview
  shows `sage about --tmux` facts/judge lines; **⚖ new judge…** runs
  `sage judge run --fleet|--repo`.
- Create path: destination first, then nested start menu when
  `FERRY_START_MENU` or launcher cmds are non-empty; hotkey-armed `startcmd`
  skips the menu.
- Live Grok panes badge wallet from `GROK_HOME` (`g:delieta:…` /
  `g:muslewski:…`, cmd `grok[wallet]`) so dual-company hosts can tell identities
  apart in the picker. Linux `/proc` only; silent empty on other OS.

## Lineage

Inferred from README picker/usage sections + `bin/repo-session` header on
2026-07-21 atlas-seed pass. Design history lives under `docs/superpowers/`
(not owned by this zone).
