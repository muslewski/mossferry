---
title: "Getting started"
description: "Install mossferry on laptop and host, set config, and verify with ferry doctor."
section: guide
order: 10
---

# Getting started

Two sides: the **laptop** (where you type `ferry`) and the **remote host** (where tmux sessions live). Both need the package on PATH.

## 1. Install (local machine)

```sh
npm install -g mossferry    # or: npx mossferry …
# bins: ferry | mossferry | repo-session
ferry doctor
```

Seeds config on first run if needed. Or copy `config.example` → `~/.config/mossferry/config`.

## 2. Install (remote host)

Same tools must be on PATH on the host — npm or clone + `install.sh`:

```sh
# option A — npm
npm install -g mossferry

# option B — git checkout (symlinks into ~/.local/bin)
git clone https://github.com/muslewski/mossferry.git ~/Repositories/mossferry
cd ~/Repositories/mossferry
./install.sh
```

`install.sh` is idempotent: creates `~/.local/bin` and `~/.config/mossferry`, symlinks bins, migrates legacy config when present, and seeds config **only if absent**.

## 3. Minimal config

`~/.config/mossferry/config` — plain `KEY=value`. Environment overrides the file.

Typical laptop:

```sh
# ~/.config/mossferry/config
FERRY_DEFAULT_HOST=manjaro-remote   # or your ssh host alias
# FERRY_WRAP=auto                   # default: grok wrap when local grok exists
# FERRY_TRANSPORT=mosh              # use ssh for more reliable Grok clipboard
```

See the README configuration table for every key. AI launchers and wrap are covered in [Grok + ferry](./guides/grok-and-ferry.md).

## 4. First hop

```sh
ferry                          # uses FERRY_DEFAULT_HOST → global picker
ferry <host>                   # all sessions + ➕ new session…
ferry <host> <repo>            # that repo's sessions (zero-session → create primary)
ferry doctor                   # local health
ferry doctor <host>            # local + remote checks
```

Picker keys (remote): `enter` attach · `ctrl-x` kill (instant, no confirm — spam to clear many sessions) · `ctrl-r` rename · `ctrl-a`/`ctrl-g` AI launchers · cycle · esc. Kill stays in the picker (no teardown). Set `FERRY_KILL_CONFIRM=1` for single-key y/N confirm.

If local and remote mossferry versions differ, the picker header shows a subtle
`↑ update  client X · remote Y  →  ferry update` line (stderr still gets a one-line
warn). Run `ferry update` (or `ferry update <host>`) to sync.

## 5. Update both sides

```sh
ferry update                   # FERRY_DEFAULT_HOST
ferry update <host>
```

Pulls local clone, then remote clone over ssh, and prints `local <v> / remote <v>`.

## Next

- [Grok + ferry](./guides/grok-and-ferry.md) — wrap, launchers, mosh vs ssh
- [Works with](./works-with.md) — fleet tools on the host you land on
- [README](../README.md) — full usage table, picker details, ghostty-grid composition
