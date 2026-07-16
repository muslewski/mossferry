# mossferry

The green ferry between your machines. *Moss* carries the green identity and the
mosh phonetics; *ferry* is the job — carrying you across to your remote tmux
sessions. Short daily command: **`ferry`**.

A two-part tool for opening remote tmux sessions over mosh. Host-agnostic:
written for a laptop ↔ workstation pair, but nothing is hard-coded to those
machines.

```
┌──────────── local ────────────┐         ┌──────────── remote ───────────┐
│  bin/mossferry                │  mosh   │  bin/repo-session             │
│  - parse args / config        │ ──ssh──▶│  - fzf (or menu) session picker│
│  - launch mosh or ssh         │         │  - create / attach / claim     │
│  - update, doctor             │         │  - all tmux logic              │
└───────────────────────────────┘         └───────────────────────────────┘
```

Installed paths are **symlinks into this repo**, so `git pull` is deploy.

## Name origin

**mossferry** was chosen after the previous short name collided hard with a
popular speech model (owning PyPI/crates) and a mobile SSH/mosh terminal in the
same space. The name is clean on npm, crates.io, PyPI, Homebrew, AUR, and
GitHub. Identity color: green.

## Install

**On the remote host** (where tmux sessions live):

```sh
git clone <url-or-path> ~/Repositories/mossferry
cd ~/Repositories/mossferry
./install.sh
```

**On the local machine** (where you type `ferry`):

```sh
git clone <host>:Repositories/mossferry ~/Repositories/mossferry
cd ~/Repositories/mossferry
./install.sh
```

`install.sh` is idempotent: it creates `~/.local/bin` and `~/.config/mossferry`,
symlinks `bin/mossferry` as both `mossferry` and `ferry`, plus `repo-session`,
into `~/.local/bin/`, removes a repo-owned legacy short-name symlink if present,
migrates the old `~/.config/<previous-name>/config` (prefix `MOSHI_` → `FERRY_`)
when the new config is absent, and seeds `~/.config/mossferry/config` from
`config.example` **only if absent**. Ensure `~/.local/bin` is on your `PATH`.

## Usage

| Command | Behavior |
|---|---|
| `ferry` | uses `FERRY_DEFAULT_HOST` → global picker (error if key unset) |
| `ferry <host>` | fzf picker, all sessions + `➕ new session…` row |
| `ferry <host> <repo>` | fzf picker, that repo's sessions + `➕ new session…` row |
| _(picker keys)_ | `enter=attach · ctrl-x=kill · ctrl-r=rename` |
| `ferry <host> <repo> --primary\|-p` | attach primary, create if missing (old default, now explicit) |
| `ferry <host> <repo> --new` | force fresh session (unchanged) |
| `ferry <host> [repo] --list\|-l` | list sessions via ssh (unchanged) |
| `ferry <host> <repo> --resume-closed` | atomic claim, unchanged (grid driver) |
| `ferry <host> <repo> --resume-or-new` | claim-or-create, unchanged (grid driver) |
| `ferry <host> --resume [N\|name]` | bare → same fzf picker; N/name → direct attach (unchanged) |
| `ferry <host> <repo> --claude\|-c` | fresh sessions run `claude` (unchanged) |
| `ferry <host> <repo> -- cmd…` | custom startup command (unchanged) |
| `ferry update [host]` | `git pull` local clone + `ssh <host> git -C ~/Repositories/mossferry pull`; prints both versions |
| `ferry doctor [host]` | health checks (see § Health) |
| `ferry --help\|-h` | usage printed locally, no connection (unchanged behavior) |
| `ferry <host> typoo` | `no repo 'typoo' under <base> — pick one below, or run 'ferry <host>' to browse all sessions` + repo list, exit 1 |

`mossferry` is the long form of the same binary; everyday use is **`ferry`**.

Default action is the **picker**. Direct attach-primary is behind `--primary`.
Grid flags (`--resume-closed`, `--resume-or-new`) are unchanged.

**Errors are local.** Before launching mosh, repo-bearing invocations run
`repo-session --validate` over ssh. Unknown repos print the typo error + repo
list on your local terminal and never start mosh (so alternate-screen restore
cannot wipe the message).

## The picker

Runs on the remote, inside the mosh session:

- One fzf list; each row: session name, active-window name, window count,
  attached/detached, current command.
- **Preview panel:** `tmux capture-pane -ep -t <session>` — the session's
  live screen, in color.
- `➕ new session…` → second fzf over directories in `FERRY_REPO_BASE`
  (pre-filtered to `<repo>` when one was given) → create + attach.
- **Zero-session fast path:** `ferry <host> <repo>` with no live sessions
  skips the picker and creates + attaches the primary.
- Esc / Ctrl-C: exit 130; mosh ends; you land back at the local prompt.
- fzf missing on host → plain numbered menu (sessions + `n) new` + `q) quit`).
  Never falls through to a shared session.

## Configuration

`~/.config/mossferry/config` — plain `KEY=value`, shell-sourced. Every key has a
built-in default; environment variables override the file; the file overrides
defaults.

| Key | Default | Where |
|---|---|---|
| `FERRY_REMOTE_BIN` | `.local/bin/repo-session` | remote path of repo-session, relative to remote `$HOME` |
| `FERRY_REPO_BASE` | `$HOME/Repositories` | remote: where repos live |
| `FERRY_DEFAULT_CMD` | `neofetch` | remote: startup command in fresh sessions |
| `FERRY_DEFAULT_HOST` | _(unset)_ | local: host used by bare `ferry` |
| `FERRY_SERVER_TIMEOUT` | `86400` | local: mosh-server self-exit after N seconds clientless |
| `FERRY_REMOTE_REPO` | `Repositories/mossferry` | remote: repo checkout, relative to remote `$HOME` |
| `FERRY_HIDDEN_WINDOW_GLOB` | `_*` | remote: window-name glob skipped for picker labels/previews |

See `config.example` for a ready-to-edit template.

## Composition with ghostty-grid

`ghostty-grid` knows nothing about mossferry; it just runs a command per pane:

```sh
ghostty-grid -8 -- ferry manjaro-remote syndcast --resume-or-new --claude
# everyday driver: 8 panes, reattach existing syndcast sessions, fill the
# rest with new ones running claude

ghostty-grid -8 -- ferry manjaro-remote syndcast --resume-closed
# reattach existing sessions only; leftover panes stay blank
```

## Updating

```sh
ferry update          # uses FERRY_DEFAULT_HOST
ferry update <host>   # explicit host
```

Pulls the local clone (`git pull --ff-only`), then pulls the remote clone
over ssh, and prints `local <v> / remote <v>`.

## Health

```sh
ferry doctor
ferry doctor <host>
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

If you are upgrading from the v1 command name (or the pre-repo zsh shell
functions, or a `.bashrc` block that auto-attaches tmux on `SSH_CONNECTION`):

1. Run `./install.sh` on both machines (back up existing
   `~/.local/bin/repo-session` first if it is a plain file). It installs
   `ferry`/`mossferry`, drops a repo-owned v1-name symlink, and migrates
   the old config dir into `~/.config/mossferry/config` (`MOSHI_` → `FERRY_`;
   old file becomes `config.migrated`).
2. On the laptop: remove the old `mosh()` / helper function blocks from
   `~/.zshrc` (keep a timestamped backup).
3. On the remote: remove the `.bashrc` auto-attach block so plain `ssh`
   lands in a normal shell (not a shared `main` session).
4. Confirm `type ferry` resolves to `~/.local/bin/ferry` and
   `ssh <host> 'echo $TMUX'` prints empty. The old v1 command name should
   no longer resolve on `PATH`.

`install.sh` warns on stderr when it still sees those legacy blocks.

## Open-sourcing

mossferry is built with no personal paths or hardcoded hosts. When you want to open-source it, just add a GitHub remote and push: `git remote add origin <url> && git push -u origin main`.
