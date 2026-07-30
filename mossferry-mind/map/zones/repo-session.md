---
type: zone
summary: "Remote brain (bin/repo-session): fzf/menu session picker + servers face (ctrl-s), create/attach, atomic claim, nested start menu, FERRY_LAUNCHERS, Grok wallet badge, FERRY_SAGE wire, kill/rename, --servers discovery, validate_repo; shared lib/repo-token.sh shape gate."
tags: [remote, tmux, picker, fzf, sage, grok]
status: active
created: 2026-07-21
updated: 2026-07-30
verifiedAt: 9abae1f5
owns:
  routes: []
  testids: []
  globs:
    - "bin/repo-session"
    - "lib/servers.sh"
  tools: []
depends:
  - "[[green-ui]]"
  - "[[client]]"
invariants:
  - "Curated --help keeps a Flags section heading (exact case) for test-ui-ops f3-repo-session-help; body stays an index not a full flag wall."
  - "Shape gate lives in lib/repo-token.sh (_ferry_repo_token_ok, owned by [[client]]) — same definition as the laptop client."
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
`--validate` for shape + directory checks. Errors are prefixed `repo-session:`.

## Anchors

- `bin/repo-session` — sole owned surface; path on remote often
  `$HOME/.local/bin/repo-session` via `FERRY_REMOTE_BIN`.
- `lib/repo-token.sh` — shared with `[[client]]` (one charset rule).
- Boundary: tmux + fzf interaction and session naming; no mosh client code.
- Attach needs a TTY; create works headless (`open terminal failed: not a terminal` from tmux when attach has no terminal).

## Invariants

- **Repo tokens are path-safe:** `_ferry_repo_token_ok` (from
  `lib/repo-token.sh`) rejects `/`, `..`, and non-basename shapes before
  joining with `FERRY_REPO_BASE`. `validate_repo` and attach paths refuse
  traversal; claim lock files use a sanitized basename (`_ferry_claim_lockf`),
  never raw `$repo` with slashes.
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
- **Runs on macOS stock bash 3.2** (`3.2.57`, the only bash on the human's Mac) as
  well as bash 5. No `mapfile`, no `declare/local -A`; every array expansion uses
  `${arr[@]+"${arr[@]}"}` because bash 3.2 under `set -u` treats an empty
  `"${arr[@]}"` as unbound (bash reports the *function declaration* line, not the
  expansion). See [[2026-07-30-macos-bash32-portability]].
- **`TMUXBIN` resolves from PATH**, absolute path only as last resort; a preflight
  turns a missing tmux into an actionable message naming `REPO_SESSION_TMUXBIN`.
  The preflight must **not** fire for verbs that never touch tmux — `--servers`,
  `--picker-servers-*`, `--picker-face-header` — and the two face-dependent verbs
  require tmux only on their sessions branch. A laptop with no tmux can browse the
  servers face; attach still refuses.
- **Locking never proceeds unlocked.** `flock` when present, else an atomic `mkdir`
  mutex with PID-liveness stale recovery and a bounded 30 s wait, released on
  signal. `flock` is Linux util-linux only and is absent on macOS.
- **Servers view degrades by capability, not `uname`:** without `ss` + `/proc` (and
  without a fixture) it emits one stderr notice instead of an empty list that reads
  as "no servers running". PID liveness does *not* need `/proc` —
  `servers_scan_agents` uses signal 0, with `EPERM` counting as alive.

## Lineage

Inferred from README picker/usage sections + `bin/repo-session` header on
2026-07-21 atlas-seed pass. Design history lives under `docs/superpowers/`
(not owned by this zone).
