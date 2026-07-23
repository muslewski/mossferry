# moshi refactor — design spec

**Date:** 2026-07-16
**Status:** approved (brainstormed Mac-side with Fable 5; implementation via subagents)
**Repo:** `~/Repositories/moshi` on manjaro (canonical home; Mac is a pull-only clone)

## 1. What moshi is

A two-part tool for opening remote tmux sessions over mosh, built for the
MacBook ↔ Manjaro pair but written host-agnostically:

- **`bin/moshi`** — local client. Runs on the machine you sit at. Parses args,
  reads config, launches `mosh <host> -- repo-session …` (or `ssh` for
  non-interactive subcommands like `--list`).
- **`bin/repo-session`** — remote brain. Runs on the host you connect to.
  Owns all tmux logic: the picker, session create/attach, atomic grid claiming.

Composes with `ghostty-grid` (which knows nothing about moshi):
`ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-or-new --claude`.

## 2. Problems this refactor fixes

1. **The `main` trap.** Bare `moshi <host>`, a typo'd repo, and plain
   `ssh` logins all funnel into one shared `main` tmux session
   (repo-session fallback + `.bashrc` auto-attach). Multiple entry points,
   same surprise.
2. **No version control.** repo-session lives loose in `~/.local/bin`;
   parallel edit sessions clobbered and lost fixes twice. moshi lives as
   zsh functions inside `~/.zshrc`, plus a legacy `mosh()` wrapper that
   duplicates it.
3. **Hardcoded personal paths.** `/home/kento/.local/bin/repo-session` is
   baked into the Mac's zshrc; blocks open-sourcing.
4. **Connection config asymmetry.** Manjaro→Mac (`Host mac-music`, used by
   the sound-effect hook) has keepalives + ControlMaster + timeouts;
   Mac→Manjaro has none of that, plus a duplicate broken `Host manjaro`
   block and a hardcoded Tailscale IP with no comment.
5. **Zombie mosh-servers.** Closed Ghostty panes orphan mosh-server
   processes that never exit (10 lingering at design time).

## 3. Decisions (settled with the user)

| Decision | Choice |
|---|---|
| Bare `moshi <host>` | fzf picker over **all** sessions, with live preview |
| `moshi <host> <repo>` | fzf picker scoped to that repo's sessions (no more silent attach-primary) |
| Attach primary | explicit flag: `--primary` / `-p` |
| Typo'd repo | error + repo list + hint to run bare `moshi <host>`; exit 1 (no picker) |
| Plain `ssh` login | normal shell — `.bashrc` auto-attach to `main` removed |
| Source home | dedicated git repo `~/Repositories/moshi` on manjaro |
| Open-source posture | no hardcoded personal paths; config file + env overrides; README notes: to open-source, just add a GitHub remote |
| Architecture | evolve existing bash two-part design (no rewrite); keep battle-tested claim/takeover logic |
| Picker tech | fzf (present on manjaro) with `tmux capture-pane` preview; numbered-menu fallback if fzf missing |

## 4. Repo layout

```
moshi/
├── bin/
│   ├── moshi            # local client (executable, replaces zsh functions)
│   └── repo-session     # remote brain
├── install.sh           # symlinks bin/* into ~/.local/bin, seeds config if absent
├── config.example       # annotated template for ~/.config/moshi/config
├── VERSION              # single version string, read by both scripts
├── docs/superpowers/specs/  # this spec and future ones
├── tests/               # fake-tmux stub harness + test scripts
└── README.md            # usage, install, open-sourcing note ("add a GitHub remote")
```

Installed files are **symlinks into the repo**, so `git pull` is deploy.
Manjaro repo gets `receive.denyCurrentBranch=updateInstead` so a push from
the Mac cleanly updates the checkout. Mac installs via:
`git clone manjaro-remote:Repositories/moshi ~/Repositories/moshi && ./install.sh`.

## 5. Config

`~/.config/moshi/config` — plain `KEY=value`, shell-sourced by whichever
script runs on that machine. Every key has a built-in default and an
environment-variable override (env wins over file; file wins over default).

```sh
MOSHI_REMOTE_BIN=".local/bin/repo-session"  # relative to remote $HOME
MOSHI_REPO_BASE="$HOME/Repositories"        # remote: where repos live
MOSHI_DEFAULT_CMD="neofetch"                # remote: startup cmd in fresh sessions
MOSHI_DEFAULT_HOST="manjaro-remote"         # local: bare `moshi` target (optional)
MOSHI_SERVER_TIMEOUT="86400"                # local: MOSH_SERVER_NETWORK_TMOUT seconds
```

No `/home/<user>` literal appears in any script.

## 6. Command surface

| Command | Behavior |
|---|---|
| `moshi` | uses `MOSHI_DEFAULT_HOST` → global picker (error if key unset) |
| `moshi <host>` | fzf picker, all sessions + `➕ new session…` row |
| `moshi <host> <repo>` | fzf picker, that repo's sessions + `➕ new session…` row |
| `moshi <host> <repo> --primary\|-p` | attach primary, create if missing (old default, now explicit) |
| `moshi <host> <repo> --new` | force fresh session (unchanged) |
| `moshi <host> [repo] --list\|-l` | list sessions via ssh (unchanged) |
| `moshi <host> <repo> --resume-closed` | atomic claim, unchanged (grid driver) |
| `moshi <host> <repo> --resume-or-new` | claim-or-create, unchanged (grid driver) |
| `moshi <host> --resume [N\|name]` | bare → same fzf picker; N/name → direct attach (unchanged) |
| `moshi <host> <repo> --claude\|-c` | fresh sessions run `claude` (unchanged) |
| `moshi <host> <repo> -- cmd…` | custom startup command (unchanged) |
| `moshi update [host]` | `git pull` local clone + `ssh <host> git -C ~/Repositories/moshi pull`; prints both versions |
| `moshi doctor [host]` | health checks (see §9) |
| `moshi --help\|-h` | usage printed locally, no connection (unchanged behavior) |
| `moshi <host> typoo` | `no repo 'typoo' under <base> — pick one below, or run 'moshi <host>' to browse all sessions` + repo list, exit 1 |

Default mode inversion: repo-session's **default action becomes the picker**;
direct attach-primary moves behind `--primary`. The grid flags are untouched
byte-for-byte, so the everyday driver keeps working:
`ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-or-new --claude`.

## 7. The picker (runs on the remote, inside the mosh session)

- One fzf list; each row: session name, active-window name (the Claude label
  session-sync.py maintains), window count, attached/detached, current command.
- **Preview panel:** `tmux capture-pane -ep -t <session>` — the session's
  actual live screen, in color, rendered as you move the cursor.
- `➕ new session…` → second fzf over directories in `MOSHI_REPO_BASE`
  (pre-filtered to `<repo>` when one was given) → create + attach, honoring
  `--claude` / `-- cmd…`.
- **Zero-session fast path:** `moshi <host> <repo>` with no live sessions
  skips the picker and creates + attaches the primary, printing a one-liner.
- Esc / Ctrl-C: exit 130, mosh ends, user lands back at the local prompt,
  attached to nothing.
- fzf missing on host → plain numbered menu (sessions + `n) new` + `q) quit`).
  Never fall through to a shared session.

## 8. Connection layer

**`~/.ssh/config` (Mac)** — dedupe the two `Host manjaro` blocks (delete the
broken `HostName manjaro` one), and upgrade `manjaro-remote` to mirror the
proven `mac-music` block from the Manjaro side:

```
Host manjaro                 # LAN
  HostName 192.168.1.12
  User kento

Host manjaro-remote          # Tailscale, from anywhere
  HostName 100.101.198.44    # stable tailnet IP (MagicDNS off at design time)
  User kento
  ServerAliveInterval 15
  ServerAliveCountMax 2
  ConnectTimeout 5
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
```

ControlMaster multiplexing makes `--list`, `update`, `doctor`, version
checks, and mosh's ssh bootstrap reuse one warm connection. mosh itself is
UDP after bootstrap and is unaffected.

**Zombie policy** — use mosh's own mechanism, not a kill script: moshi
launches `mosh --server="MOSH_SERVER_NETWORK_TMOUT=$MOSHI_SERVER_TIMEOUT mosh-server" …`.
A server whose client disappears self-terminates after the timeout (default
24 h); ordinary roaming and network drops are unaffected. Migration includes
a one-time confirmed sweep of the currently lingering servers.

**Version handshake** — moshi prepends `--client-version <v>` (read from
`VERSION` via its own resolved symlink) to every repo-session invocation.
repo-session compares against its `VERSION`; on mismatch prints one stderr
line — `moshi: client <a> / remote <b> — run 'moshi update'` — and proceeds.

## 9. `moshi doctor [host]`

Read-only checks, one line each: local config readable; host in ssh config;
Tailscale peer reachable; ssh auth works (BatchMode); mosh binary present
both ends; remote repo-session resolves + versions match; fzf present on
remote; lingering mosh-server count; MagicDNS availability note.

## 10. Error handling

- Typo'd repo: error + repo list, exit 1 (never attach anything).
- No tmux server running: picker shows only `➕ new session…` repo rows.
- Host unreachable: friendly hint to run `moshi doctor <host>`.
- repo-session invoked with unknown flags: warn on stderr, ignore (as today).
- Version drift: warn, never block.
- Concurrent grid claims: existing flock + `@claim_ts` TTL logic preserved
  unchanged, including two-pass takeover (`attach -d`) of stale-attached
  sessions.

## 11. Migration plan (each step backed up first)

1. Seed `~/Repositories/moshi` on manjaro: initial commit = current live
   scripts as-is (repo-session from `~/.local/bin`, moshi functions extracted
   from Mac zshrc); second commit = this spec. Retire scattered
   `repo-session.bak*` files once history exists.
2. Build the new `bin/moshi`, `bin/repo-session`, `install.sh`,
   `config.example`, `VERSION`, `README.md`, `tests/` in the repo.
3. Install on manjaro (`install.sh` symlinks `~/.local/bin/repo-session` →
   repo). Path is unchanged, so old clients keep working mid-migration.
4. Clone + install on the Mac; remove `moshi()`, `moshi_help()`, and the
   legacy `mosh()` wrapper from `~/.zshrc` (backup kept).
5. Remove `.bashrc` auto-attach block on manjaro; drop the
   `env -u SSH_CONNECTION` workaround from repo-session.
6. Fix `~/.ssh/config` per §8.
7. One-time zombie sweep (with user confirmation).
8. Verify: bare picker, scoped picker, typo, `--primary`, `--list`, grid
   driver `ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-or-new
   --claude`, `update`, `doctor`.

## 12. Testing

- `tests/` with a fake-tmux stub (via existing `REPO_SESSION_TMUXBIN` hook):
  arg parsing, list scoping, typo path, `--primary`, zero-session fast path,
  claim/flock behavior, version-handshake warning.
- Picker interactivity: manual checklist (part of §11 step 8).
- Tests run on manjaro with `tests/run.sh`; no framework dependency beyond
  bash.

## 13. Out of scope

- Sound-effect hook stack (`ping-mac-music.sh`, `notify-mode`) — reference
  model only; unchanged.
- `ghostty-grid` — unchanged; composition contract preserved.
- Renaming existing grid flags or sessions naming scheme (`repo`, `repo-2`…).
- GitHub publication itself (repo is made ready; publishing is a later
  one-liner: add remote, push).
