# mossferry


<p align="center">
  <a href="https://mossferry.muslewski.com"><img src="https://img.shields.io/badge/website-mossferry.muslewski.com-3dff9a?style=flat-square&labelColor=02060c" alt="Website"></a>
</p>

<p align="center">
  <a href="https://mossferry.muslewski.com"><img src="https://raw.githubusercontent.com/muslewski/mossferry-website/main/public/mossferry4.webp" alt="mossferry spore" width="360"></a>
</p>

<p align="center"><b>Site:</b> <a href="https://mossferry.muslewski.com">mossferry.muslewski.com</a></p>

The green ferry between your machines. *Moss* carries the green identity and the
mosh phonetics; *ferry* is the job — carrying you across to your remote tmux
sessions. Short daily command: **`ferry`**.

```
           |>
         __|__               __
      __|_o_o_|__           / _|___ _ _ _ _ _  _
    _|___________|_        |  _/ -_) '_| '_| || |
   \   o   o   o   /       |_| \___|_| |_|  \_, |
 ~~~\_____________/~~~~~~~~~~~~~~~~~~~~~~~~ |__/ ~~
```

<p align="center"><img src="./assets/demo-picker.gif" width="720" alt="ferry picker demo"></p>

---

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

**Local machine** (where you type `ferry`):

```sh
npm install -g mossferry    # or: npx mossferry …
# bins: ferry | mossferry | repo-session
ferry doctor
```

Seeds config on first run if needed; or copy `config.example` → `~/.config/mossferry/config`.

**Remote host** (where tmux sessions live) still needs the same tools on PATH —
install the package there too, or clone + `./install.sh`:

```sh
# option A — npm (same as local)
npm install -g mossferry

# option B — git checkout (symlinks into ~/.local/bin)
git clone <url-or-path> ~/Repositories/mossferry
cd ~/Repositories/mossferry
./install.sh
```

`install.sh` is idempotent: it creates `~/.local/bin` and `~/.config/mossferry`,
symlinks `bin/mossferry` as both `mossferry` and `ferry`, plus `repo-session`,
into `~/.local/bin/`, migrates legacy config when present, and seeds
`~/.config/mossferry/config` from `config.example` **only if absent**.

## Usage

| Command | Behavior |
|---|---|
| `ferry` | uses `FERRY_DEFAULT_HOST` → global picker (error if key unset) |
| `ferry <host>` | fzf picker, all sessions + `➕ new session…` row |
| `ferry <host> <repo>` | fzf picker, that repo's sessions + `➕ new session…` row |
| _(picker keys)_ | `enter=attach · ctrl-x=kill · ctrl-r=rename · ctrl-a/ctrl-g=AI · cycle · esc`; launchers on `➕ new session…` and destination rows |
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

<details><summary>▶ demo</summary>
<p><img src="./assets/demo-help.gif" width="600" alt="ferry --help demo"></p>
</details>

`mossferry` is the long form of the same binary; everyday use is **`ferry`**.

Default action is the **picker**. Direct attach-primary is behind `--primary`.
Grid flags (`--resume-closed`, `--resume-or-new`) are unchanged.

**Errors are local.** Before launching mosh, repo-bearing invocations run
`repo-session --validate` over ssh. Unknown repos print the typo error + repo
list on your local terminal and never start mosh (so alternate-screen restore
cannot wipe the message).

## The picker

Runs on the remote, inside the mosh session:

- **Banner:** green ferry ASCII art sits in the fzf header (top-left), width-
  tiered: wide panes get the boat+figlet lockup (≥52 cols), medium panes get
  the liner with the name on the hull (≥24 cols), and short or narrow panes
  get a one-line `⛴ mossferry`. The main picker's banner uses 40% of terminal
  width (header left of the `right:60%` preview). Set `FERRY_BANNER=off` (or
  `0`) to hide it. Layout is reverse with the header first; list navigation
  wraps (`--cycle`).
- One fzf list; each row: session name, active-window name, window count,
  attached/detached, current command.
- **Preview panel:** `tmux capture-pane -ep -t <session>` — the session's
  live screen, in color.
- `➕ new session…` → second fzf over directories in `FERRY_REPO_BASE`
  (pre-filtered to `<repo>` when one was given) → create + attach.
- Global new-session chain also offers `➕ new repo…` (prompt name, `mkdir` +
  `git init -b main` under `FERRY_REPO_BASE`, then create + attach) and
  `🏠 home session…` (prompt name, empty → `home`; session cwd `$HOME`).
- **AI launchers:** on destination rows (repo / `➕ new repo…` / `🏠 home
  session…`) and on the main picker's `➕ new session…` row, press a configured
  key (default `ctrl-a` → `claude`, `ctrl-g` → `grok`) instead of enter to
  create that session with that start command. Overrides `FERRY_DEFAULT_CMD`,
  `--claude`, and `-- cmd…` for that one creation. Enter keeps today's default.
  On an existing-session row, launcher keys are ignored (list reloads). Configure
  via `FERRY_LAUNCHERS` (`key:command` pairs, comma-separated; empty disables).
  Sub-picker header shows a dynamic hints line from the parsed config. No-fzf
  menu is unaffected (always uses the default command).
- Repo-scoped picker's new-session chain stays pre-filtered — no special rows.
- **Zero-session fast path:** `ferry <host> <repo>` with no live sessions
  skips the picker and creates + attaches the primary.
- Esc / Ctrl-C: exit 130; mosh ends; you land back at the local prompt.
- fzf missing on host → plain numbered menu (sessions + `n) new` + `q) quit`;
  global new-session menu adds `r) new repo` and `h) home session`).
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
| `FERRY_BANNER` | `on` | green ferry art in picker header and `--help` (`off`/`0` hides) |
| `FERRY_LAUNCHERS` | `ctrl-a:claude,ctrl-g:grok` | remote: picker AI-launcher keys (`key:command` pairs; empty disables; `ctrl-x`/`ctrl-r` reserved) |

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
over ssh, and prints `local <v> / remote <v>`. On a TTY the crossing is
shown as step lines (local pull → remote pull) plus a wave strip
`local <v> ~~~⛴~~~ remote <v>` (green on match, red on divergence). Raw
git output is dimmed, not removed. `FERRY_UPDATE_VERBOSE=1` keeps git loud.

## Health

```sh
ferry doctor
ferry doctor <host>
```

Read-only checks (config, ssh resolution, auth, mosh, remote bin, version
match, fzf, lingering mosh-servers, MagicDNS notes). Exit 1 if any check
fails. On a TTY: small ferry banner, green ✓ / red ✗ / dim info glyphs,
end summary, and a dim fix hint (e.g. `ferry update`) when versions
mismatch. Non-TTY keeps the plain `ok` / `FAIL` / `info` tokens for
scripts and tests.

<details><summary>▶ demo</summary>
<p><img src="./assets/demo-doctor.gif" width="600" alt="ferry doctor demo"></p>
</details>

## Ops screens (v2.5.0)

Chrome is TTY-gated via the vendored GREEN-UI-KIT (`lib/green-ui.sh`).
Pipes and CI stay monochrome and parse-stable.

| Surface | Non-TTY (stable tokens) | TTY chrome |
|---|---|---|
| `ferry doctor` | `ok` / `FAIL` / `info` lines | ⛴ banner · glyphs · summary · fix hints |
| `ferry update` | `local <v> / remote <v>` | step checklist · wave strip |
| `--help` | sectioned body + version footer | green section labels |
| validate typo | exact `repo-session: no repo…` + list, exit 1 | dim capped list + `did you mean …?` |
| `install.sh` | `symlink` / `seeded` action lines | MEDIUM hull · ✓ steps · ready panel · PATH check |

Errors are unified as `mossferry:` (client) or `repo-session:` (remote),
with a red ✗ glyph when stderr is a TTY. Missing `lib/green-ui.sh` never
kills the tool — plain fallbacks apply.

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
