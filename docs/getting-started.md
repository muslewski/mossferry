---
title: "Getting started"
description: "Install mossferry on laptop and host, set host aliases, and verify with ferry doctor."
section: guide
order: 10
---

# Getting started

**mossferry** is a laptop command that attaches you to a repository’s tmux session on another machine. Everyday binary: **`ferry`**. This page gets both ends installed and checks them.

## 1. Install on the laptop

```sh
npm install -g mossferry    # or: npx mossferry …
# bins: ferry | mossferry | repo-session
ferry --help                # local only; no network
```

Or clone and symlink:

```sh
git clone https://github.com/muslewski/mossferry.git ~/Repositories/mossferry
cd ~/Repositories/mossferry
./install.sh
```

`install.sh` is idempotent: creates `~/.local/bin` and `~/.config/mossferry`, symlinks `bin/mossferry` as both `mossferry` and `ferry`, plus `repo-session`, migrates legacy config when present, and seeds `~/.config/mossferry/config` from `config.example` **only if absent**.

Observed `--help` footer:

```text
mossferry 2.7.4 · the green ferry between your machines
```

## 2. Install on the host

The machine that holds the repos needs the same tools on `PATH` (especially `repo-session` and `tmux`):

```sh
# option A — npm
npm install -g mossferry

# option B — git checkout
git clone https://github.com/muslewski/mossferry.git ~/Repositories/mossferry
cd ~/Repositories/mossferry
./install.sh
```

Default remote layout:

| What | Default |
|------|---------|
| `repo-session` path | `~/.local/bin/repo-session` (`FERRY_REMOTE_BIN=.local/bin/repo-session`) |
| Repos directory | `~/Repositories` (`FERRY_REPO_BASE`) |
| mossferry checkout (for `ferry update`) | `~/Repositories/mossferry` (`FERRY_REMOTE_REPO`) |

## 3. Configure host aliases (laptop)

`~/.config/mossferry/config` — plain `KEY=value`. Environment overrides the file.

```sh
# ~/.config/mossferry/config
FERRY_DEFAULT_HOST=workstation          # placeholder Host name — replace with yours
# FERRY_HOST_CANDIDATES=workstation-lan,workstation
# FERRY_TRANSPORT=mosh                  # or ssh
# FERRY_WRAP=auto                       # grok wrap when local grok exists
```

`workstation` is a **placeholder**. Define a matching `Host` in `~/.ssh/config` (LAN IP, Tailscale name, etc. stay in ssh config — not in ferry).

Bare `ferry`, `ferry doctor`, and `ferry update` resolve a host in this order:

1. Explicit CLI host (always wins)
2. `FERRY_HOST_CANDIDATES` — first name that answers `ssh -o BatchMode=yes -o ConnectTimeout=2 … true`
3. `FERRY_DEFAULT_HOST`

If nothing is set:

```text
mossferry: doctor: no host (pass one, or set FERRY_HOST_CANDIDATES / FERRY_DEFAULT_HOST)
```

Full key list: [Usage](./usage.md) and `config.example`.

## 4. Verify (needs a reachable host)

```sh
ferry doctor workstation
```

Read-only checks: config readable, ssh resolution, BatchMode connect, local mosh, wrap/transport info, remote `repo-session` executable, version match, fzf, mosh-server count, and a short servers summary. Exit **1** if any line is `FAIL`.

Non-TTY tokens stay parse-stable: `ok` / `FAIL` / `info`. On a TTY you get glyphs and a short summary.

Example lines when the host is **not** reachable (host name is a placeholder):

```text
ok config readable: ~/.config/mossferry/config
ok ssh config resolves host not-a-real-host.example
FAIL ssh BatchMode connect to not-a-real-host.example
ok local mosh binary
…
FAIL remote .local/bin/repo-session not executable
FAIL versions: local 2.7.4 / remote unknown
```

**Note:** doctor always looks for a **local mosh** binary, even if you set `FERRY_TRANSPORT=ssh`.

## 5. First hop

```sh
ferry workstation                 # global picker
ferry workstation my-app          # scoped to one repo
ferry workstation my-app -p       # attach/create primary (no picker)
ferry workstation --list          # list only (ssh)
ferry workstation --list-servers  # listeners TSV (ssh)
```

Picker keys (on the host): `enter` attach · `ctrl-x` kill · `ctrl-r` rename · `ctrl-s` servers face · `esc` quit. See [Usage](./usage.md) and [Servers view](./servers-view.md).

If client and remote versions differ, the picker header can show an update hint. Sync both sides:

```sh
ferry update                      # uses default host
ferry update workstation
```

Pulls the local clone (`git pull --ff-only`), then the remote clone over ssh, and prints `local <v> / remote <v>`.

## 6. Detach and come back

Inside the session you are in host tmux. Detach with your tmux binding (stock: `Ctrl-b` `d`). Reattach with the same `ferry` command later. Mosh reconnects through short link loss; ssh does not — but the remote session survives either way.

## Migration (old install names)

If you still have a pre-rename client or a `.bashrc` auto-attach on `SSH_CONNECTION`:

1. Run `./install.sh` on both machines (back up a hand-written `~/.local/bin/repo-session` first if it is not a symlink).
2. On the laptop: remove old helper function blocks from your shell rc (keep a timestamped backup).
3. On the host: remove `.bashrc` auto-attach so plain `ssh` lands in a normal shell.
4. Confirm `type ferry` → `~/.local/bin/ferry` and `ssh <host> 'echo $TMUX'` prints empty.

`install.sh` warns on stderr when it still sees those legacy blocks.

## Next

- [Usage](./usage.md) — full flags, errors, grid drivers
- [Grok + ferry](./guides/grok-and-ferry.md) — wrap, start menu, clipboard
- [Servers view](./servers-view.md) — listeners and Mac reachability
- [Works with](./works-with.md) — fleet tools on the host
- [README](../README.md) — short on-ramp
