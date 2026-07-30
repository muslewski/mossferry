---
title: "Usage"
description: "ferry and repo-session flags, picker behaviour, detach/reattach, and real error messages."
section: guide
order: 15
---

# Usage

**mossferry** is the laptop hop; **repo-session** is the host brain. You almost always type **`ferry`**. This page is the command reference. For install and first config, see [Getting started](./getting-started.md).

## Commands (laptop)

| Command | What happens |
|---------|----------------|
| `ferry` | Resolve host via `FERRY_HOST_CANDIDATES` / `FERRY_DEFAULT_HOST`, open global picker |
| `ferry <host>` | Global session picker on that host |
| `ferry <host> <repo>` | Picker scoped to that repo basename under `FERRY_REPO_BASE` |
| `ferry <host> <repo> --primary` / `-p` | Attach primary session, create if missing |
| `ferry <host> <repo> --new` | Fresh session (`repo`, `repo-2`, …) |
| `ferry <host> <repo> --claude` / `-c` | New sessions start `claude` (default start is `neofetch`) |
| `ferry <host> [repo] --list` / `-l` | List sessions over **ssh**, exit (no mosh, no wrap) |
| `ferry <host> --list-servers` | List listeners (maps to remote `--servers`); add `--json` |
| `ferry <host> --resume` | Same as global picker |
| `ferry <host> --resume N\|name` | Direct attach by index or exact session name |
| `ferry <host> <repo> --resume-closed` | Atomic claim of one **existing** session (grid driver) |
| `ferry <host> <repo> --resume-or-new` | Claim existing or create until the grid fills |
| `ferry <host> <repo> -- cmd…` | Custom start command for newly created sessions |
| `ferry update [host]` | `git pull --ff-only` local clone, then remote clone over ssh; print both versions |
| `ferry doctor [host]` | Read-only health checks; exit 1 if any `FAIL` |
| `ferry --help` / `-h` | Usage printed **locally** (no connection) |

`mossferry` is the long form of the same binary as `ferry`.

### Help footer (observed)

```text
mossferry 2.7.4 · the green ferry between your machines
```

### Default action is the picker

Nothing attaches a shared `main` session implicitly. Direct attach-primary is **`--primary`**.

## Commands (host / remote brain)

| Command | What happens |
|---------|----------------|
| `repo-session` | Global picker |
| `repo-session <repo>` | Scoped picker |
| `repo-session --list` | List sessions (same row shape as laptop `--list`) |
| `repo-session --servers` | 14-column TSV listeners; `--json` for agents |
| `repo-session --validate <repo>` | Exit 0 if directory exists under `FERRY_REPO_BASE`; no tmux |
| `repo-session --help` | Usage (includes servers-face chords) |

The laptop client runs `repo-session` for you over mosh/ssh. You only call it directly when debugging on the host.

## Picker

Runs **on the host** inside the interactive hop.

| Key | Action |
|-----|--------|
| `enter` | Attach selected session |
| `➕ new session…` | Nested destination pick → start menu (`FERRY_START_MENU`, default `claude,grok`) |
| `ctrl-x` | Kill session, stay in picker (instant). `FERRY_KILL_CONFIRM=1` for single-key y/N |
| `ctrl-r` | Rename, stay in picker |
| `ctrl-s` | Toggle servers face |
| `esc` / Ctrl-C | Quit; hop ends (exit 130) |

**Preview:** `tmux capture-pane` of the selected session (colour). **Banner:** green ferry art in the fzf header when `FERRY_BANNER` is on (default). **No fzf:** numbered menu (`n` new, `q` quit; global create also offers new-repo / home-session).

**AI launchers:** optional `FERRY_LAUNCHERS` (`key:command` pairs). Empty by default. Reserved: `ctrl-x`, `ctrl-r`, `ctrl-s`, `ctrl-f`. On an existing-session row, launcher keys reload the list (no attach).

**Grok wrap** is laptop-side (`FERRY_WRAP`), not a picker key. See [Grok + ferry](./guides/grok-and-ferry.md).

**Client help gap:** `ferry --help` does not list `ctrl-s` / servers-face chords; `repo-session --help` does. Trust the remote help for picker keys.

## Session list format

From `repo-session --list` / `ferry <host> --list`:

```text
1) my-app           bash                   2w attached bash
2) my-app-2         bash                   1w detached bash
```

Fields: index, session name, active window label, window count (`Nw`), `attached` or `detached`, current command.

## Servers one-shot

```sh
# on the host
repo-session --servers
repo-session --servers --json

# from the laptop (ssh)
ferry <host> --list-servers
ferry <host> --list-servers --json
```

14 TSV columns:

```text
port  state  id  class  label  bind  pid  comm  repo  owner  mac_state  mac_url  health  restart
```

Details: [Servers view](./servers-view.md).

## Detach and reattach

1. **Detach:** normal tmux detach inside the session (stock prefix `Ctrl-b` then `d`). Ferry does not redefine tmux keys.
2. **Client end:** mosh or ssh returns you to the local shell. Remote panes keep running.
3. **Reattach:** `ferry <host>` (pick) or `ferry <host> <repo> --primary`.

With **mosh**, a blip can reconnect the hop without a new login (until `FERRY_SERVER_TIMEOUT` clientless seconds; default 86400). With **ssh**, a dropped link ends the client immediately; re-run `ferry`.

## Errors and empty states

| Message / situation | Meaning | What to do |
|---------------------|---------|------------|
| `mossferry: doctor: no host (pass one, or set FERRY_HOST_CANDIDATES / FERRY_DEFAULT_HOST)` | No host argument and no config default | Pass a host or set config |
| Bare `ferry` with no default host | Prints usage on stderr, exits **1** | Set `FERRY_DEFAULT_HOST` or pass `<host>` |
| `repo-session: no repo '…' under … — pick one below…` | Basename missing under `FERRY_REPO_BASE` | Fix the name, or `ferry <host>` to browse all |
| `repo-session: invalid repo name '…'` | Token fails `^[A-Za-z0-9._-]+$` or looks path-shaped (`/`, `..`, spaces) | Use a simple basename |
| `repo-session: --primary requires a <repo>` | Flag without repo | Pass the repo basename |
| `repo-session: --new requires a <repo>` | Same | Pass the repo basename |
| `FAIL ssh BatchMode connect to …` (doctor) | Cannot ssh without a password prompt | Fix keys / `~/.ssh/config` |
| `FAIL local mosh binary missing` (doctor) | No `mosh` on laptop PATH | Install mosh, or note doctor still checks this when `FERRY_TRANSPORT=ssh` |
| `info remote fzf missing — numbered menu fallback available` | Host has no fzf | Usable; plain menu instead of fzf |
| Picker with zero sessions for a repo | Fast path creates primary and attaches | Expected; message: `no live sessions for <repo> — created primary` |
| Version skew header in picker | Client and remote package versions differ | `ferry update` or `ferry update <host>` |

## Repo name rules

`_ferry_repo_token_ok` (used by validate, create, list-scoped, claim):

- Allowed: letters, digits, `.`, `_`, `-` only (`^[A-Za-z0-9._-]+$`)
- Rejected: empty, spaces, quotes, `/`, `\`, any `..` substring, absolute paths
- After join with `FERRY_REPO_BASE`, `realpath` must stay under the base when `realpath` exists

Remote argv for the hop is built with `printf %q` so OpenSSH’s space-joining cannot split tokens — but **invalid repo names are still rejected** before attach.

Full observed tables (refusals, quoting samples, session match, status gaps): [Quoting and containment](./quoting-and-containment.md).

## Grid drivers (composition)

mossferry does not embed a terminal grid. Tools like `ghostty-grid` just run a command per pane:

```sh
ghostty-grid -8 -- ferry workstation my-app --resume-or-new --claude
ghostty-grid -8 -- ferry workstation my-app --resume-closed
```

`--resume-closed`: each pane claims a distinct **existing** session; extras stay blank.  
`--resume-or-new`: same, then creates sessions until every pane has one.

## Config keys (summary)

Full template: `config.example`. Env overrides file; file overrides built-in defaults.

| Key | Default | Side |
|-----|---------|------|
| `FERRY_REMOTE_BIN` | `.local/bin/repo-session` | remote path relative to `$HOME` |
| `FERRY_REPO_BASE` | `$HOME/Repositories` | remote repo parent |
| `FERRY_DEFAULT_CMD` | `neofetch` | start command for new sessions |
| `FERRY_DEFAULT_HOST` | _(unset)_ | bare `ferry` / doctor / update |
| `FERRY_HOST_CANDIDATES` | _(empty)_ | comma-separated aliases; first BatchMode-reachable wins |
| `FERRY_SERVER_TIMEOUT` | `86400` | mosh-server clientless self-exit (seconds) |
| `FERRY_REMOTE_REPO` | `Repositories/mossferry` | remote clone for `ferry update` |
| `FERRY_BANNER` | `on` | picker / help art (`off` / `0` hides) |
| `FERRY_START_MENU` | `claude,grok` | nested create menu; empty disables |
| `FERRY_LAUNCHERS` | _(empty)_ | optional `key:command` hotkeys |
| `FERRY_WRAP` | `auto` | local `grok wrap` when `grok` on PATH |
| `FERRY_TRANSPORT` | `mosh` | interactive hop: `mosh` or `ssh` |
| `FERRY_SAGE` | `auto` | optional sage wire when `sage` on host PATH |

## Developer logging

Opt-in, **local-only** event log shared with sibling fleet tools. Off by default.

- Enable: `FLEET_DEVLOG=1` (or `true` / `on` / `yes`), or `~/.config/fleet-devlog/config.json` with `{"enabled": true}`
- Disable: `FLEET_DEVLOG=0` / `false` / `off` / `no`, or `--no-devlog`
- Path: `${XDG_STATE_HOME:-$HOME/.local/state}/fleet-devlog/events.jsonl`
- Never records prompts, file contents, secrets, or free-form paths. No network uploader.

Delete: `rm -rf ~/.local/state/fleet-devlog`

## See also

- [Getting started](./getting-started.md)
- [Quoting and containment](./quoting-and-containment.md)
- [Servers view](./servers-view.md)
- [Grok + ferry](./guides/grok-and-ferry.md)
- [README](../README.md)
