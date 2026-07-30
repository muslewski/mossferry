# mossferry

<p align="center">
  <a href="https://mossferry.muslewski.com"><img src="https://img.shields.io/badge/website-mossferry.muslewski.com-3dff9a?style=flat-square&labelColor=02060c" alt="Website"></a>
  <a href="https://www.npmjs.com/package/mossferry"><img src="https://img.shields.io/npm/v/mossferry?style=flat-square" alt="npm"></a>
  <a href="https://github.com/muslewski/mossferry/discussions"><img src="https://img.shields.io/badge/discussions-join-3dff9a?style=flat-square&labelColor=02060c" alt="Discussions"></a>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT">
</p>

**mossferry** opens a remote repository’s tmux session from your laptop in one command, over mosh or ssh, with an fzf picker.

You sit at one machine; the repo and its long-running panes live on another. You want to be inside that session in tmux, leave and come back, and survive a dropped network link without losing the work. Everyday command: **`ferry`**.

Site: [mossferry.muslewski.com](https://mossferry.muslewski.com)

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

## Happy path

Two sides: **laptop** (where you type `ferry`) and **host** (where tmux and the repos live). Both need the package on `PATH`.

### 1. Install (runnable anywhere)

```sh
npm install -g mossferry    # bins: ferry | mossferry | repo-session
# or clone the repo and run ./install.sh on that machine
ferry --help                # printed locally; no network
```

`ferry --help` ends with a version line like:

```text
mossferry 2.7.4 · the green ferry between your machines
```

### 2. Configure hosts (laptop)

`~/.config/mossferry/config` is plain `KEY=value` (seeded from `config.example` on first install if missing). Put **ssh config aliases** here — not hard-coded IPs:

```sh
# ~/.config/mossferry/config
FERRY_DEFAULT_HOST=workstation          # placeholder — your Host alias in ~/.ssh/config
# optional: try LAN first, then a remote alias
# FERRY_HOST_CANDIDATES=workstation-lan,workstation
```

`workstation` is a **placeholder**. Point it at a real `Host` entry in `~/.ssh/config`. mossferry only tries the names you list.

### 3. Install on the host (needs a real machine)

Same package on the machine that owns the repos:

```sh
npm install -g mossferry
# or: clone + ./install.sh  → symlinks ferry/mossferry/repo-session into ~/.local/bin
```

Remote defaults expect `repo-session` at `~/.local/bin/repo-session` and repos under `~/Repositories` (`FERRY_REPO_BASE`).

### 4. Check, list, attach (needs a reachable host)

```sh
ferry doctor workstation          # read-only health; exit 1 if any FAIL
ferry workstation --list          # every tmux session on the host (ssh, no mosh)
ferry workstation                 # global session picker → enter attaches
ferry workstation my-app          # picker scoped to that repo (basename under FERRY_REPO_BASE)
```

Without a configured host, doctor fails locally (no connection attempted):

```text
mossferry: doctor: no host (pass one, or set FERRY_HOST_CANDIDATES / FERRY_DEFAULT_HOST)
```

Bare `ferry` uses `FERRY_HOST_CANDIDATES` (first BatchMode-reachable) or `FERRY_DEFAULT_HOST`. If neither is set, it prints usage on stderr and exits 1.

### 5. Detach and reattach

Inside a session you are in **tmux on the host**. Detach with your normal tmux binding (stock is `Ctrl-b` then `d`). The panes keep running.

Come back later:

```sh
ferry workstation                 # pick the session again
ferry workstation my-app -p       # attach/create the primary session for my-app
```

---

## What you meet, in order

| Step | What runs | Where |
|------|-----------|--------|
| Config | `~/.config/mossferry/config` + `~/.ssh/config` | laptop |
| Hop | `ferry` → mosh (default) or ssh → `repo-session` | laptop → host |
| Pick | fzf (or numbered menu if fzf missing) | host, inside the hop |
| Attach | `tmux attach` to the chosen session | host |
| Detach | tmux detach; mosh/ssh client ends | host → laptop |
| Reattach | `ferry` again | laptop |

```
┌──────────── laptop ───────────┐         ┌──────────── host ─────────────┐
│  bin/mossferry (ferry)        │  mosh   │  bin/repo-session             │
│  - args / config / doctor     │ ──ssh──▶│  - picker, create, attach     │
│  - launch mosh or ssh         │         │  - all tmux logic             │
└───────────────────────────────┘         └───────────────────────────────┘
```

Installed paths from `./install.sh` are **symlinks into the clone**, so `git pull` (or `ferry update`) is deploy.

---

## List and pick sessions

Non-interactive list (remote, via ssh from the laptop):

```sh
ferry workstation --list
ferry workstation my-app --list
```

On the host itself, the same shape comes from `repo-session --list`. Rows look like:

```text
1) my-app           bash                   2w attached bash
2) my-app-2         bash                   1w detached bash
3) other-repo       claude                 2w attached claude
```

Columns: index, session name, active window, window count, attached/detached, current command.

**Interactive picker** (default when you omit list flags): runs on the host inside mosh/ssh.

| Key | Action |
|-----|--------|
| `enter` | attach |
| `➕ new session…` | nested create flow (destination → start menu) |
| `ctrl-x` | kill session (instant; stays in picker). `FERRY_KILL_CONFIRM=1` for y/N |
| `ctrl-r` | rename (stays in picker) |
| `ctrl-s` | toggle **servers** face (see below) |
| `esc` | quit picker (exit 130 → hop ends) |

Start menu defaults to `claude,grok` (`FERRY_START_MENU`). Optional hotkeys: `FERRY_LAUNCHERS` (empty by default). `ctrl-x` / `ctrl-r` / `ctrl-s` / `ctrl-f` are reserved.

**Zero sessions for a repo:** `ferry workstation my-app` creates and attaches the primary session (named like the repo) instead of showing an empty list.

**Repo typos** are checked over ssh with `repo-session --validate` **before** mosh starts, so the error stays on your laptop terminal:

```text
repo-session: no repo 'typoo' under ~/Repositories — pick one below, or run 'ferry <host>' to browse all sessions
```

---

## Servers view

Second face of the picker (**servers face**, toggle with `ctrl-s`): **what is listening on the host, and can a Mac browser reach it?** Discovery is read-only.

| Surface | Command / key |
|---------|----------------|
| In picker | `ctrl-s` sessions ↔ servers |
| One-shot on host | `repo-session --servers` · `--servers --json` |
| One-shot from laptop | `ferry workstation --list-servers` · `--list-servers --json` |

Each TSV row has **14 fields** (tab-separated), in this order:

```text
port  state  id  class  label  bind  pid  comm  repo  owner  mac_state  mac_url  health  restart
```

Example shape (values illustrative; live output depends on the host):

```text
8787	LISTEN	-	dev	python3	0.0.0.0	12345	python3	my-app	-	reachable	http://workstation.example:8787/	-	-
5432	LISTEN	-	db	postgres	127.0.0.1	1652	postgres	-	-	loopback-only	-	-	-
8791	LISTEN	-	docker	-	0.0.0.0	-	-	-	-	reserved	-	-	unless-stopped
```

Servers-face chords: `enter` = copy Mac URL when `mac_state=reachable` (OSC 52; does not open a browser) · `ctrl-f` = print fix plan · `ctrl-s` = back to sessions.

Full row model, declarations, and fix-plan rules: [docs/servers-view.md](./docs/servers-view.md).

---

## Why mosh (and when only ssh is available)

Default interactive transport is **mosh** (`FERRY_TRANSPORT=mosh`).

| Transport | What you get | Tradeoff |
|-----------|--------------|----------|
| **mosh** (default) | Roaming reconnect after Wi‑Fi blips / sleep; remote `mosh-server` can self-exit after `FERRY_SERVER_TIMEOUT` seconds clientless (default **86400**) | Many mosh builds strip OSC 52, so clipboard bridge via `grok wrap` is unreliable |
| **ssh** (`FERRY_TRANSPORT=ssh`) | Ordinary `ssh -t` hop; better OSC 52 with local `grok wrap` | Drop the link and the client dies; **tmux on the host keeps running** — re-run `ferry` to attach again |

The long-running work is always in **remote tmux**. Mosh protects the *hop*; ssh does not. Either way, detach/reattach is safe for the session itself.

`--list` and `--list-servers` always use **ssh**, never mosh, and never `grok wrap`.

---

## Limitations

- **External binaries.** Ferry launches `ssh`, `mosh`, `tmux`, and optionally `fzf` / `grok`. It does not vendor them. Behaviour is whatever those tools do on each end.
- **Both ends must be installed.** Laptop needs `ferry`; host needs `repo-session` on the path configured by `FERRY_REMOTE_BIN` (default `.local/bin/repo-session` under remote `$HOME`), plus tmux.
- **Repo name charset.** CLI repo tokens must match `^[A-Za-z0-9._-]+$`: no spaces, no quotes, no `/`, no `..`, no absolute paths. Invalid tokens print `repo-session: invalid repo name '…'` and never start mosh. Remote argv is still `printf %q`-quoted so unusual characters in *other* arguments cannot break the ssh command line.
- **Doctor always checks for a local `mosh` binary**, even when `FERRY_TRANSPORT=ssh`. An ssh-only laptop can still see `FAIL local mosh binary missing` until mosh is installed or you accept that check as noise.
- **Servers-face fix chords** (`ctrl-f` and enter-to-copy) are detailed in `repo-session --help` and [Servers view](./docs/servers-view.md); `ferry --help` lists `ctrl-s` to open that face.
- **Not a sandbox.** Same OS user on the host can reach other sessions’ files. See [docs/safety-roadmap.md](./docs/safety-roadmap.md).
- **No hosted CI** for this project. Verify locally with `bash tests/run.sh` and the docs commands below.

---

## Docs

| Page | For |
|------|-----|
| [Getting started](./docs/getting-started.md) | Install both sides, doctor, update |
| [Command reference](./docs/command-reference.md) | Full flags, combinations, exit codes, real output |
| [Configuration](./docs/configuration.md) | Every `FERRY_*` key and env var |
| [Usage](./docs/usage.md) | Compact flag map and picker summary |
| [Quoting and containment](./docs/quoting-and-containment.md) | Safe repo names, remote argv quoting, session match |
| [Troubleshooting](./docs/troubleshooting.md) | Symptom fixes, doctor, test harness |
| [Servers view](./docs/servers-view.md) | Listeners, Mac reachability, fix plans |
| [Grok + ferry](./docs/guides/grok-and-ferry.md) | `FERRY_WRAP`, start menu, mosh vs clipboard |
| [Safety roadmap](./docs/safety-roadmap.md) | Door vs building; planned safety nits |
| [Works with](./docs/works-with.md) | Fleet tools on the host you land on |

Architecture notes live in [`mossferry-mind/`](./mossferry-mind/) (Atlas vault), not under `docs/`.

Local docs gate (from a clone next to `docs-kit`):

```sh
node ../docs-kit/bin/docs-kit.mjs check docs/
node ../docs-kit/bin/docs-kit.mjs health docs/
```

---

## Testing

```sh
bash tests/run.sh
PATH=/usr/bin:/bin:/usr/local/bin bash tests/run.sh   # require the same verdict
```

Plain bash harness with fake `tmux` / `mosh` / `ssh` stubs. No `jq`, `bats`, or `shellcheck` required. Nonzero exit on any failure. Skips must print `SKIP …` with a reason — never silent green. Contributor contract: [docs/troubleshooting.md](./docs/troubleshooting.md#test-harness-contributors).

---

## Composition with ghostty-grid

mossferry does not embed a terminal grid. Drivers such as **`ghostty-grid`** only run a command per pane; the atomic claim flags fill those panes with distinct remote sessions:

```sh
ghostty-grid -8 -- ferry workstation my-app --resume-or-new --claude
# 8 panes: reattach existing my-app sessions, fill the rest with new ones running claude

ghostty-grid -8 -- ferry workstation my-app --resume-closed
# reattach existing only; leftover panes stay blank
```

`--resume-closed` claims one **existing** session per caller (atomic). `--resume-or-new` does the same, then creates sessions until every pane has one. See [Usage](./docs/usage.md#grid-drivers-composition) and [Command reference](./docs/command-reference.md).

---

## Open-sourcing

mossferry is built with no personal paths or hardcoded hosts. Config takes **ssh aliases** you choose (`FERRY_DEFAULT_HOST`, `FERRY_HOST_CANDIDATES`); defaults are portable (`~/Repositories`, `~/.local/bin/repo-session`). When you want a public remote for your own fork or mirror:

```sh
git remote add origin <url>
git push -u origin main
```

Self-host without npm: clone on laptop and host, run `./install.sh` on each side, set `FERRY_DEFAULT_HOST` to a real `Host` from `~/.ssh/config`, then `ferry doctor <host>`.

---

## Community

- **Website:** [mossferry.muslewski.com](https://mossferry.muslewski.com)
- **Questions:** [Discussions](https://github.com/muslewski/mossferry/discussions)
- **Bugs:** [Issues](https://github.com/muslewski/mossferry/issues/new/choose)
- **Contributing:** [CONTRIBUTING.md](./CONTRIBUTING.md) · [Code of Conduct](./CODE_OF_CONDUCT.md) · [Security](./SECURITY.md) · [Support](./SUPPORT.md)
