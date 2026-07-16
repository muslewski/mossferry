# moshi

A two-part tool for opening remote tmux sessions over mosh. Host-agnostic:
written for a laptop ↔ workstation pair, but nothing is hard-coded to those
machines.

```
┌──────────── local ────────────┐         ┌──────────── remote ───────────┐
│  bin/moshi                    │  mosh   │  bin/repo-session             │
│  - parse args / config        │ ──ssh──▶│  - fzf (or menu) session picker│
│  - launch mosh or ssh         │         │  - create / attach / claim     │
│  - update, doctor             │         │  - all tmux logic              │
└───────────────────────────────┘         └───────────────────────────────┘
```

Installed paths are **symlinks into this repo**, so `git pull` is deploy.

## Install

**On the remote host** (where tmux sessions live):

```sh
git clone <url-or-path> ~/Repositories/moshi
cd ~/Repositories/moshi
./install.sh
```

**On the local machine** (where you type `moshi`):

```sh
git clone <host>:Repositories/moshi ~/Repositories/moshi
cd ~/Repositories/moshi
./install.sh
```

`install.sh` is idempotent: it creates `~/.local/bin` and `~/.config/moshi`,
symlinks `bin/moshi` and `bin/repo-session` into `~/.local/bin/`, and seeds
`~/.config/moshi/config` from `config.example` **only if absent**. Ensure
`~/.local/bin` is on your `PATH`.

## Usage

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

Default action is the **picker**. Direct attach-primary is behind `--primary`.
Grid flags (`--resume-closed`, `--resume-or-new`) are unchanged.

## The picker

Runs on the remote, inside the mosh session:

- One fzf list; each row: session name, active-window name, window count,
  attached/detached, current command.
- **Preview panel:** `tmux capture-pane -ep -t <session>` — the session's
  live screen, in color.
- `➕ new session…` → second fzf over directories in `MOSHI_REPO_BASE`
  (pre-filtered to `<repo>` when one was given) → create + attach.
- **Zero-session fast path:** `moshi <host> <repo>` with no live sessions
  skips the picker and creates + attaches the primary.
- Esc / Ctrl-C: exit 130; mosh ends; you land back at the local prompt.
- fzf missing on host → plain numbered menu (sessions + `n) new` + `q) quit`).
  Never falls through to a shared session.

## Configuration

`~/.config/moshi/config` — plain `KEY=value`, shell-sourced. Every key has a
built-in default; environment variables override the file; the file overrides
defaults.

| Key | Default | Where |
|---|---|---|
| `MOSHI_REMOTE_BIN` | `.local/bin/repo-session` | remote path of repo-session, relative to remote `$HOME` |
| `MOSHI_REPO_BASE` | `$HOME/Repositories` | remote: where repos live |
| `MOSHI_DEFAULT_CMD` | `neofetch` | remote: startup command in fresh sessions |
| `MOSHI_DEFAULT_HOST` | _(unset)_ | local: host used by bare `moshi` |
| `MOSHI_SERVER_TIMEOUT` | `86400` | local: mosh-server self-exit after N seconds clientless |
| `MOSHI_REMOTE_REPO` | `Repositories/moshi` | remote: repo checkout, relative to remote `$HOME` |

See `config.example` for a ready-to-edit template.

## Composition with ghostty-grid

`ghostty-grid` knows nothing about moshi; it just runs a command per pane:

```sh
ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-or-new --claude
# everyday driver: 8 panes, reattach existing syndcast sessions, fill the
# rest with new ones running claude

ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-closed
# reattach existing sessions only; leftover panes stay blank
```

## Updating

```sh
moshi update          # uses MOSHI_DEFAULT_HOST
moshi update <host>   # explicit host
```

Pulls the local clone (`git pull --ff-only`), then pulls the remote clone
over ssh, and prints `local <v> / remote <v>`.

## Health

```sh
moshi doctor
moshi doctor <host>
```

Read-only checks (config, ssh resolution, auth, mosh, remote bin, version
match, fzf, lingering mosh-servers, MagicDNS notes). Exit 1 if any check
fails.

## Testing

```sh
bash tests/run.sh
```

Plain bash harness (fake `tmux` / `mosh` / `ssh` stubs). No framework
dependency beyond bash. Nonzero exit on any failure.

## Migration

If you are upgrading from the pre-repo setup (zsh `moshi()` / `mosh()`
functions on the laptop, or a `.bashrc` block that auto-attaches tmux on
`SSH_CONNECTION`):

1. Run `./install.sh` on both machines (back up existing
   `~/.local/bin/repo-session` first if it is a plain file).
2. On the laptop: remove the `mosh()`, `moshi()`, and `moshi_help()` function
   blocks from `~/.zshrc` (keep a timestamped backup).
3. On the remote: remove the `.bashrc` auto-attach block so plain `ssh`
   lands in a normal shell (not a shared `main` session).
4. Confirm `type moshi` resolves to `~/.local/bin/moshi` and
   `ssh <host> 'echo $TMUX'` prints empty.

`install.sh` warns on stderr when it still sees those legacy blocks.

## Open-sourcing

moshi is built with no personal paths or hardcoded hosts. When you want to open-source it, just add a GitHub remote and push: `git remote add origin <url> && git push -u origin main`.
