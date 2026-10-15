---
title: "Command reference"
description: "Verified ferry and repo-session flags, combinations, exit codes, and real output — grouped by task."
section: reference
order: 20
---

# Command reference

**mossferry** is a terminal tool that attaches you to a repository’s tmux session on another machine over mosh or ssh. You type **`ferry`** on the laptop; the host runs **`repo-session`**.

This page documents what the binaries on this tree actually do. Every flag, message, and exit code below was produced by running `./bin/mossferry` and `./bin/repo-session` (or is quoted from their `--help` after that run). For install and first config, see [Getting started](./getting-started.md). For every config key, see [Configuration](./configuration.md).

## Happy path (copy-paste)

Laptop (after `~/.config/mossferry/config` has `FERRY_DEFAULT_HOST` or you pass a host):

```sh
ferry --help                    # local only; exit 0; ends with version line
ferry doctor workstation        # read-only health; exit 1 if any FAIL
ferry workstation --list        # ssh list of every tmux session; then exit
ferry workstation               # mosh/ssh hop → global picker → enter attaches
ferry workstation my-app -p     # attach or create the primary session for my-app
```

On the host (no ferry hop):

```sh
repo-session --help
repo-session --validate my-app  # exit 0 when $FERRY_REPO_BASE/my-app exists
repo-session --list             # numbered session list
repo-session my-app -p          # attach/create primary
```

Observed help footer (both binaries):

```text
mossferry 2.7.4 · the green ferry between your machines
```

There is **no** `--version` flag. The first non-subcommand token is treated as a **host** by `ferry`, so `ferry --version` is not version output.

---

## Primary commands (index)

| You type | Side | What happens |
|----------|------|----------------|
| `ferry <host>` | laptop | Interactive hop; global session picker on host |
| `ferry <host> <repo>` | laptop | Same hop; picker scoped to that repo basename |
| `ferry <host> <repo> -p` / `--primary` | laptop | Attach primary session, create if missing |
| `ferry <host> --list` / `-l` | laptop | **ssh** only; list sessions; no mosh/wrap |
| `ferry <host> --list-servers` [`--json`] | laptop | **ssh** only; maps to remote `--servers` |
| `ferry doctor [host]` | laptop | Read-only checks; exit **1** if any `FAIL` |
| `ferry update [host]` | laptop | `git pull --ff-only` local clone + remote; print versions |
| `ferry --help` / `-h` | laptop | Usage on stdout; **no network**; exit 0 |
| `repo-session` / `repo-session <repo>` | host | Global or scoped picker |
| `repo-session <repo> -p` | host | Attach/create primary |
| `repo-session --list` | host | List sessions; exit 0 (empty list is still 0) |
| `repo-session --servers` [`--json`] | host | 14-column listener TSV (or JSON array) |
| `repo-session --validate <repo>` | host | Directory check under `FERRY_REPO_BASE`; no tmux |

`mossferry` is the same file as `ferry` (`package.json` bins both point at `bin/mossferry`).

---

## Configuring hosts and the repository base

| Concern | Key / default | Side |
|---------|---------------|------|
| Default host for bare `ferry` / doctor / update | `FERRY_DEFAULT_HOST` (unset) | laptop |
| Prefer LAN then remote | `FERRY_HOST_CANDIDATES` (empty) — first `ssh -o BatchMode=yes -o ConnectTimeout=2 … true` that works | laptop |
| Where repos live | `FERRY_REPO_BASE` → `$HOME/Repositories` | host (client shape-gates tokens; existence via remote `--validate`) |
| Path to host brain | `FERRY_REMOTE_BIN` → `.local/bin/repo-session` (relative to remote `$HOME`) | laptop → remote |

Host resolution order for bare `ferry`, `ferry doctor`, and `ferry update`:

1. Explicit CLI host (always wins when present)
2. First reachable name in `FERRY_HOST_CANDIDATES`
3. `FERRY_DEFAULT_HOST`

When nothing resolves:

```text
mossferry: doctor: no host (pass one, or set FERRY_HOST_CANDIDATES / FERRY_DEFAULT_HOST)
```

```text
mossferry: update: no host (pass one, or set FERRY_HOST_CANDIDATES / FERRY_DEFAULT_HOST)
```

Both exit **1**. Bare `ferry` with no default prints **usage on stderr** and exits **1**.

Put machine addresses only in `~/.ssh/config` `Host` entries. Ferry tries the **alias names** you configure, not hard-coded IPs.

Full key table: [Configuration](./configuration.md). Repo name shape and path containment: [Quoting and containment](./quoting-and-containment.md).

---

## Listing and picking

### List sessions

```sh
# host
repo-session --list
repo-session my-app --list

# laptop (ssh; never mosh, never grok wrap)
ferry workstation --list
ferry workstation my-app --list
```

**Side effects:** none (read-only tmux query). Does not attach.

**Observed row shape** (fields: index, session name, window label, window count, attached/detached, command):

```text
1) my-app           bash                   2w detached bash
2) my-app-2         bash                   1w attached bash
```

**Empty states** (exit **0**):

```text
no my-app sessions yet
```

```text
no tmux sessions running
```

**Scoped list on missing repo** (exit **1**) — same message family as `--validate`:

```text
repo-session: no repo 'nosuch' under <FERRY_REPO_BASE> — pick one below, or run 'ferry <host>' to browse all sessions
```

(followed by a directory listing of basenames under the base).

### Interactive picker

Default when you omit `--list` / `--primary` / `--new` / claim flags:

| Key | Action |
|-----|--------|
| `enter` | Attach selected session |
| `➕ new session…` | Nested destination pick → start menu (`FERRY_START_MENU`, default `claude,grok`) |
| `ctrl-x` | Kill session, stay in picker (instant). `FERRY_KILL_CONFIRM=1` → single-key y/N |
| `ctrl-r` | Rename, stay in picker |
| `ctrl-s` | Toggle servers face |
| `esc` / Ctrl-C | Quit; hop ends (exit **130** from the remote picker path) |

**Preview:** `tmux capture-pane` of the selected session. **Banner:** green ferry art when `FERRY_BANNER` is on (default). **No fzf:** numbered menu (`n` new, `q` quit).

**AI launchers:** optional `FERRY_LAUNCHERS` (`key:command` pairs). Empty by default. Reserved: `ctrl-x`, `ctrl-r`, `ctrl-s`, `ctrl-f`; terminal aliases `ctrl-m` (Enter), `ctrl-j`, `ctrl-i` (Tab), `ctrl-h` (Backspace), `ctrl-c`, `ctrl-z` are ignored. On an existing-session row a launcher key attaches, same as Enter.

**Zero sessions for a scoped repo** (fast path — creates and attaches primary):

```text
no live sessions for my-app — created primary
```

**Version skew** (warn only; never blocks). Ferry always prepends `--client-version <local VERSION>` on the remote command. Observed:

```text
mossferry: client 9.9.9 / remote 2.7.4 — run 'ferry update'
```

### First token is the host (trap)

`ferry` only special-cases `update`, `doctor`, `-h`/`--help` before taking `$1` as host. Flags are **not** global:

```sh
ferry --list                 # host becomes "--list" → mosh/ssh error (not a session list)
ferry --help                 # ok: help is special-cased
```

Always pass the host first: `ferry workstation --list`.

---

## Attaching, detaching, reattaching

### Direct attach / create

| Command | Requires `<repo>` | Creates if missing | Session name |
|---------|-------------------|--------------------|--------------|
| `--primary` / `-p` | yes | yes (primary = basename) | `repo` |
| `--new` | yes | always fresh | `repo`, then `repo-2`, `repo-3`, … |
| bare picker scoped | yes (optional) | only zero-session fast path | primary name |
| `--resume` bare | no | no | picker |
| `--resume N` | no (optional scope) | no | Nth in list (1-based) |
| `--resume name` | no | no | exact literal name (`tmux attach -t =name`) |
| `--resume-closed` | yes | no | one claimed existing; else blank shell |
| `--resume-or-new` | yes | yes when none left to claim | claim or new |

**Start command for new sessions:**

1. `-- cmd...` after a double-dash, if present  
2. else `--claude` / `-c` → `claude`  
3. else `FERRY_DEFAULT_CMD` (default `neofetch`)

`--claude` and `-- cmd` only affect **newly created** sessions, not attach to an existing one.

**Missing repo on create flags** (exit **1**):

```text
repo-session: --primary requires a <repo>
repo-session: --new requires a <repo>
repo-session: --resume-closed/--resume-or-new require a <repo>
```

**Invalid / missing names** — see [Quoting and containment](./quoting-and-containment.md). Shape rejection:

```text
repo-session: invalid repo name 'bad name'
```

### Resume by index or name

```sh
repo-session --resume 1          # 1-based index into global list
repo-session --resume my-app-2   # exact name; literal match
ferry workstation --resume my-app-2
```

Missing index / name (exit **1**):

```text
no session #999. available:
  1) conventions
  2) my-app
  …
```

```text
no session named nosuchsession999. available:
  conventions
  my-app
  …
```

**Unadvertised alias:** `-R` is accepted as `--resume` in `repo-session` (same parsing). Not listed in `--help`.

### Grid claim modes

For multi-pane drivers (for example `ghostty-grid`), not for everyday single attach:

```sh
ghostty-grid -8 -- ferry workstation my-app --resume-or-new --claude
ghostty-grid -8 -- ferry workstation my-app --resume-closed
```

Creating a session works without a TTY (headless `repo-session <repo> -p` still runs `new-session` / `send-keys`). **Attaching** needs a real terminal: without one, tmux prints `open terminal failed: not a terminal` after create.

| Flag | Behaviour |
|------|-----------|
| `--resume-closed` | Atomic claim of one **existing** session per caller (flock + `@claim_ts`, 25s TTL). Prefers detached; else takes over an attached session. No free session → message `no <repo> sessions left to resume — blank shell` and a plain login shell. |
| `--resume-or-new` | Same claim, then creates `repo` / `repo-N` until a session is obtained so every pane can fill. |

### Detach and reattach

1. **Detach:** normal tmux detach inside the session (stock prefix `Ctrl-b` then `d`). Ferry does not redefine tmux keys.  
2. **Client end:** mosh or ssh returns you to the local shell. Remote panes keep running.  
3. **Reattach:** `ferry <host>` (pick) or `ferry <host> <repo> --primary`.

With **mosh**, a short blip can reconnect without a new login until `FERRY_SERVER_TIMEOUT` clientless seconds (default `86400`). With **ssh**, a dropped link ends the client immediately; re-run `ferry`. Remote tmux survives either transport.

### Transport and wrap (interactive hops only)

| Setting | Effect |
|---------|--------|
| `FERRY_TRANSPORT=mosh` (default) | `mosh --server="MOSH_SERVER_NETWORK_TMOUT=… mosh-server" <host> -- bash -lc '<quoted repo-session…>'` |
| `FERRY_TRANSPORT=ssh` | `ssh -t <host> '<quoted repo-session…>'` |
| other value | Interactive launch errors: `unknown FERRY_TRANSPORT='…' (want mosh\|ssh)`; doctor marks `FAIL` |
| `FERRY_WRAP=auto` (default) | Prefix hop with `grok wrap` when `grok` is on PATH |
| `FERRY_WRAP=on` | Same, but stderr warning if grok missing, then hop without wrap |
| `FERRY_WRAP=off` | Never wrap |

`--list`, `--list-servers`, `doctor`, and `update` never use wrap. `--list` / `--list-servers` always use ssh.

Repo-bearing launches run two gates before mosh:

1. **Local shape** — `_ferry_repo_token_ok` on the laptop (shared with the host). Invalid tokens print `repo-session: invalid repo name '…'` and exit **1** with **no** ssh.
2. **Remote existence** — `repo-session --validate <repo>` over ssh. Missing basenames print `no repo '…'` and exit **1** without opening a hop.

---

## Snapshot and restore (host)

```sh
repo-session --snapshot-install            # systemd user timer: snapshot every 60 s (prints a crontab line without systemd)
repo-session --snapshot-install --remove   # turn it off
repo-session --snapshot                    # one snapshot now
repo-session --restore --dry-run           # what a restore would do
repo-session --restore                     # restore every pre-boot session that is not live, in the foreground
```

A snapshot records every tmux window: session, window name, folder and, for windows running Claude Code, the conversation id. The id comes from `~/.claude/sessions/<pid>.json`, which Claude Code deletes when the process ends, so it is joined by tmux pane id while the session is alive.

After a reboot the picker shows **`♻ restore N sessions from <day time>`** above `➕ new session…`:

- **enter** opens a multi-select of those sessions, all selected, with a preview of their windows. **tab** toggles, **enter** restores them in the background (log: `~/.local/state/mossferry/restore.log`), **esc** goes back.
- **ctrl-x** on the row dismisses it for that snapshot. Nothing is killed.
- The numbered fallback menu shows the same row as `r)`.

Restore recreates each session with its windows and folders. Claude windows get `claude --resume <id>`; every other window gets `FERRY_DEFAULT_CMD`, never the command that was running before. Resumes are spaced out and wait for load (see [configuration](configuration.md#snapshot-and-restore-host)). Then every executable in `~/.config/mossferry/restore.d/` runs in name order, with the snapshot path as `$1` and the restored session names in `FERRY_RESTORED_SESSIONS`. Use those hooks for anything outside tmux: containers, dev servers.

## Servers view

### One-shot

```sh
# host
repo-session --servers
repo-session --servers --json

# laptop (ssh; --list-servers rewritten to --servers on the remote)
ferry workstation --list-servers
ferry workstation --list-servers --json
```

**Side effects:** read-only discovery (`ss`, declarations, optional agent-status). Does not start or stop processes by default.

**14 TSV columns** (tab-separated; column count verified = 14):

```text
port  state  id  class  label  bind  pid  comm  repo  owner  mac_state  mac_url  health  restart
```

Illustrative LISTEN row (host sanitized):

```text
3000	LISTEN	-	dev	node	0.0.0.0	1234	node	my-app	-	reachable	http://HOST:3000/	-	-
```

`--json` prints a JSON **array** of objects with those same keys (hand-rolled; no `jq` required to emit).

**Errors:**

```text
repo-session: --json requires --servers
```

exit **1** (`--json` alone, or `--list --json`).

### Picker servers face

| Key | Action |
|-----|--------|
| `ctrl-s` | Toggle sessions ↔ servers |
| `enter` | Copy Mac URL when `mac_state=reachable` (OSC 52; does not open a browser) |
| `ctrl-f` | Print fix plan; execute recipe only if `FERRY_SERVERS_FIX=on` (default **off** — print only) |
| `esc` | Quit |

Details, declaration TSV, and `mac_state` vocabulary: [Servers view](./servers-view.md).

### Doctor servers summary

`ferry doctor` ends with info lines only (never changes pass/fail by themselves): reserved port list, and a remote count like `N LISTEN · M declared-missing · K foreign`.

---

## Installation and diagnostics

### Install

```sh
npm install -g mossferry
# bins: ferry | mossferry | repo-session

# or from a clone
./install.sh
```

`install.sh` is idempotent (exit **0** even when printing migration warnings):

- ensures `~/.local/bin` and `~/.config/mossferry`
- symlinks `bin/mossferry` as both `mossferry` and `ferry`, plus `repo-session`
- seeds `~/.config/mossferry/config` from `config.example` **only if absent**
- leaves an existing config file unchanged

### `ferry doctor [host]`

Read-only. Exit **1** if any check is `FAIL`, else **0**. Non-TTY lines use stable tokens `ok` / `FAIL` / `info`. Full check table, known gaps (no `--json`, no remote tmux check, BOM vs hop), and symptom playbook: [Troubleshooting](./troubleshooting.md).

Checks performed (in order):

1. Config readable (or `info` if absent)  
2. `ssh -G` resolves host  
3. `ssh -o BatchMode=yes -o ConnectTimeout=5` connect  
4. Local `mosh` binary (**always** checked, even when `FERRY_TRANSPORT=ssh`)  
5. Local `grok wrap` availability vs `FERRY_WRAP`  
6. `FERRY_TRANSPORT` is `mosh` or `ssh`  
7. Remote `FERRY_REMOTE_BIN` executable  
8. Local vs remote `VERSION` match  
9. Remote `fzf` (info if missing)  
10. Remote `mosh-server` count (info)  
11. HostName / MagicDNS note (info)  
12. Mac-reachable host, reserved ports, servers summary (info)

Observed on an unreachable placeholder host (paths abbreviated):

```text
ok config readable: ~/.config/mossferry/config
ok ssh config resolves host not-a-real-host.example
FAIL ssh BatchMode connect to not-a-real-host.example
ok local mosh binary
…
FAIL remote .local/bin/repo-session not executable
FAIL versions: local 2.7.4 / remote unknown
info remote fzf missing — numbered menu fallback available
info remote mosh-server count: 0
…
info reserved ports: 8791 3001 5432 6379 27017 8080 5173 3000
info servers: 0 LISTEN · 0 declared-missing · 0 foreign
```

Bad transport:

```text
FAIL FERRY_TRANSPORT=bad (want mosh|ssh)
```

### `ferry update [host]`

1. `git pull --ff-only` in the **local** mossferry clone (`REPO_ROOT` next to the binary)  
2. Over ssh: `git -C $FERRY_REMOTE_REPO pull --ff-only` (default remote path `Repositories/mossferry` under remote `$HOME`)  
3. Print local and remote `VERSION` contents  

Needs a resolvable host. Does not open a session.

### Validate (host / preflight)

```sh
repo-session --validate my-app
# exit 0: silent success when directory exists
# exit 1: invalid name or missing directory (+ basename listing when missing)
```

Used automatically by the laptop client for shape-valid repo tokens on interactive hops (after the local charset gate).

---

## Combinations that matter

| Combination | Result |
|-------------|--------|
| `<repo> --primary` | Attach `repo` or create with startcmd, then attach |
| `<repo> --new --claude` | Fresh `repo-N` starting `claude` |
| `<repo> --new -- bash -l` | Fresh session; start command is `bash -l` |
| `<repo> --primary` when session already exists | Attach only; does **not** re-send start command |
| `--list` with `<repo>` | Scoped list; still validates repo first |
| `--list` without `<repo>` | All sessions on the host |
| `--resume` without arg | Same as default picker |
| `--resume-closed` without free sessions | Blank login shell (exit path is `exec` shell) |
| `--resume-or-new` when none free | Creates next free name under the repo |
| `--list-servers --json` on laptop | Remote gets `--servers --json` |
| `--client-version` mismatch | Stderr nudge + picker header; continues |
| Interactive hop + `FERRY_WRAP=auto` + local `grok` | `grok wrap mosh|ssh …` |
| `ferry --list` (no host) | Host token is `--list` — fails at transport, not list |

---

## Unadvertised and internal flags

| Flag | Where | Notes |
|------|-------|-------|
| `-R` | `repo-session` | Alias for `--resume`; not in `--help` |
| `--client-version V` | both | Set by ferry on every remote invocation; advertised in `repo-session --help` only |
| `--picker-rows`, `--picker-preview`, `--picker-kill`, `--picker-rename` | `repo-session` | fzf bind helpers; not user-facing |
| `--picker-servers-*`, `--picker-face-*` | `repo-session` | Servers-face reload/preview/header helpers |
| `--no-devlog` | `ferry` argv scan only | Disables fleet-devlog when present **anywhere** in argv for the emit check; **not** stripped — if it is the first token it becomes the host name |
| `FERRY_LIB=1` / `REPO_SESSION_LIB=1` | source mode | Library load for tests; not a CLI flag |
| `FERRY_UPDATE_VERBOSE` | env | When set, `ferry update` does not hide git pull output behind a temp file on a TTY |

Unknown flags on `repo-session`:

```text
repo-session: ignoring unknown flag '--cycle'
```

then processing continues (may open the picker if nothing else was selected).

---

## Exit codes (observed)

| Situation | Code |
|-----------|------|
| `--help` | 0 |
| `--validate` success | 0 (no stdout) |
| `--validate` missing/invalid | 1 |
| `--list` with zero or more sessions | 0 |
| `--list` scoped to missing repo | 1 |
| `--servers` / `--servers --json` | 0 |
| `--json` without `--servers` | 1 |
| `--primary` / `--new` / claim without `<repo>` | 1 |
| `--resume` bad index/name | 1 |
| Picker cancel (esc) | 130 (remote path) |
| `ferry` no host | 1 |
| `ferry doctor` any FAIL / no host | 1 |
| `ferry doctor` all ok | 0 |
| `ferry update` no host | 1 |
| Pre-validate failure on hop | 1 (local; no mosh) |

Interactive attach success typically ends inside `tmux`/`mosh` (process image replaced or long-running); the shell only sees an exit code after detach/quit.

---

## Errors and empty states (quick table)

| Message | Meaning | Next step |
|---------|---------|-----------|
| `doctor: no host…` / `update: no host…` | No CLI host and no config default | Pass host or set `FERRY_DEFAULT_HOST` / candidates |
| Bare `ferry` → usage on stderr | Same | Same |
| `no repo '…' under …` | Basename missing under base | Fix name or `ferry <host>` global picker |
| `invalid repo name '…'` | Token fails `^[A-Za-z0-9._-]+$` or path-shaped | Use a simple basename |
| `--primary requires a <repo>` (and siblings) | Flag without repo | Pass repo basename |
| `--json requires --servers` | JSON only with servers one-shot | Add `--servers` |
| `FAIL ssh BatchMode connect…` | Cannot passwordless ssh | Fix keys / ssh config |
| `FAIL local mosh binary missing` | No `mosh` on laptop PATH | Install mosh (still checked under `FERRY_TRANSPORT=ssh`) |
| `info remote fzf missing…` | Host has no fzf | Numbered menu still works |
| `client X / remote Y — run 'ferry update'` | Version skew | `ferry update <host>` on both sides |
| `ignoring unknown flag '…'` | Typo or internal-only flag | Check `--help`; continue if intentional |

---

## What this tool does not do

- Does **not** embed a terminal grid (pair with an external grid driver if needed).  
- Does **not** supervise or restart host processes by default (servers view is discovery; recipes run only with `FERRY_SERVERS_FIX=on`).  
- Does **not** open a Mac browser from the servers face (copies a URL when reachable).  
- Does **not** publish logs; developer logging is opt-in and local-only ([Configuration](./configuration.md#developer-logging)).  
- Does **not** accept a global `--version` flag.  
- Does **not** treat a leading flag as a global option on `ferry` (host is positional).

---

## See also

- [Getting started](./getting-started.md)  
- [Configuration](./configuration.md)  
- [Usage](./usage.md) (shorter flag tables)  
- [Quoting and containment](./quoting-and-containment.md)  
- [Servers view](./servers-view.md)  
- [Grok + ferry](./guides/grok-and-ferry.md)  
- [README](../README.md)  
