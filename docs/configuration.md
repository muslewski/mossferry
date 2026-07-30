---
title: "Configuration"
description: "Every FERRY_* key and environment variable mossferry reads — defaults, side, and malformed behaviour."
section: reference
order: 21
---

# Configuration

**mossferry** reads plain `KEY=value` pairs from `~/.config/mossferry/config` (sourced as shell). **Environment variables override the file; the file overrides built-in defaults.** Every key is optional.

Template in the repo: [`config.example`](../config.example). Seeded by `./install.sh` **only when the config file is absent**.

Load order (both `ferry` and `repo-session`):

1. Snapshot any `FERRY_*` already set in the environment  
2. Apply built-in defaults  
3. `source ~/.config/mossferry/config` if readable  
4. Restore the env snapshot so pre-set vars win  

Malformed lines in the config file are ordinary shell source errors (the file is not a custom parser). Prefer simple `KEY=value` assignments without logic.

---

## Host and paths

| Key | Default | Side | When unset / empty | Malformed / notes |
|-----|---------|------|--------------------|-------------------|
| `FERRY_DEFAULT_HOST` | empty | laptop | Bare `ferry` / `doctor` / `update` need an explicit host or candidates | Any string is tried as an ssh `Host` alias |
| `FERRY_HOST_CANDIDATES` | empty | laptop | Skip multi-host probe; fall through to `FERRY_DEFAULT_HOST` | Comma-separated aliases; first that answers `ssh -o BatchMode=yes -o ConnectTimeout=2 <name> true` wins. Spaces after commas are fine if the file is valid shell |
| `FERRY_REMOTE_BIN` | `.local/bin/repo-session` | laptop → remote | Default path relative to remote `$HOME` | Absolute path also accepted by doctor’s `test -x`. Client runs this path over ssh/mosh |
| `FERRY_REPO_BASE` | `$HOME/Repositories` | host (primary); client for understanding | Repos are basenames under this directory | Containment is defined **relative to this base**. After join, `realpath` must stay under the base when `realpath` exists. Empty or nonsense base → `--validate` / scoped list fail with `no repo '…' under …` |
| `FERRY_REMOTE_REPO` | `Repositories/mossferry` | laptop (`update`, doctor VERSION) | Relative to remote `$HOME` for `git -C` and `cat …/VERSION` | Wrong path → doctor `FAIL versions: local … / remote unknown`; update remote pull fails |

### Repository base and containment

A **repo token** is a single path segment under `FERRY_REPO_BASE`:

- Allowed shape: `^[A-Za-z0-9._-]+$`  
- Rejected: empty, spaces, quotes, `/`, `\`, any `..` substring, absolute paths  

Observed rejection:

```text
repo-session: invalid repo name 'bad name'
```

Missing directory (shape ok):

```text
repo-session: no repo 'nosuchrepo999' under <FERRY_REPO_BASE> — pick one below, or run 'ferry <host>' to browse all sessions
```

Full tables and argv quoting: [Quoting and containment](./quoting-and-containment.md).

---

## Transport and wrap (laptop)

| Key | Default | Side | Values | Behaviour |
|-----|---------|------|--------|-----------|
| `FERRY_TRANSPORT` | `mosh` | laptop | `mosh`, `ssh` (case-insensitive) | Interactive hop only. Other values → launch error `unknown FERRY_TRANSPORT='…' (want mosh\|ssh)`; doctor emits `FAIL` |
| `FERRY_SERVER_TIMEOUT` | `86400` | laptop | integer seconds | Passed as `MOSH_SERVER_NETWORK_TMOUT` to mosh-server (clientless self-exit). Not used for pure ssh hops |
| `FERRY_WRAP` | `auto` | laptop | `auto`, `on`/`1`/`true`/`yes`, `off`/`0`/`false`/`no` | `auto`: wrap with `grok wrap` when `grok` is on PATH. `on`: same but warns if missing. `off`: never wrap. Applies only to interactive mosh/ssh, not `--list` / doctor / update |

Doctor always checks for a **local mosh binary**, even when `FERRY_TRANSPORT=ssh`.

---

## Sessions and picker (host)

| Key | Default | Side | When unset / empty | Notes |
|-----|---------|------|--------------------|-------|
| `FERRY_DEFAULT_CMD` | `neofetch` | host | Used as start command for new sessions when neither `--claude` nor `-- cmd` is set | Any shell command string sent via `tmux send-keys` |
| `FERRY_START_MENU` | `claude,grok` | host | Empty string disables the nested create menu | Comma-separated start commands after ➕ destination pick; first row is always “default (no AI)” = `FERRY_DEFAULT_CMD` |
| `FERRY_LAUNCHERS` | empty | host | Feature off (menu only) | `key:command` pairs, comma-separated; first colon splits. Reserved keys: `ctrl-x`, `ctrl-r`, `ctrl-s`, `ctrl-f` |
| `FERRY_BANNER` | `on` | both | — | `off` or `0` hides green ferry art in `--help` and the picker |
| `FERRY_HIDDEN_WINDOW_GLOB` | `_*` | host | — | Windows matching this glob are skipped in picker names/previews (default hides underscore-prefixed windows) |
| `FERRY_KILL_CONFIRM` | `0` (off) | host | Instant kill on `ctrl-x` | Set to `1` for single-key y/N confirm before kill |
| `FERRY_SAGE` | `auto` | host | — | `auto`/`on`: wire agentic-sage when `sage` is on PATH (picker preview one-liners + judge entry). `off`: hard-off even if installed |

---

## Servers view

| Key | Default | Side | Notes |
|-----|---------|------|-------|
| `FERRY_SERVERS_RESERVED` | `8791 3001 5432 6379 27017 8080 5173 3000` | host (+ doctor info) | Space-separated ports treated as reserved / denylist for Mac reachability (includes FreeLLMAPI **8791**) |
| `FERRY_SERVERS_DECL` | unset | host | Optional colon-separated extra declaration file paths, merged with defaults |
| `FERRY_SERVERS_FIX` | `off` | host | `on` allows ctrl-f recipes to execute; default prints only |
| `FERRY_SERVERS_SS_FIXTURE` | unset | host (tests) | When set, listener lines come from stdin instead of live `ss` |
| `FERRY_SERVERS_EXPECT_REPO_<port>` | unset | host | Stronger FOREIGN detection for a port |

Declaration files (later wins per port):

1. `~/.config/mossferry/servers.tsv`  
2. `<repo>/.ferry/servers.tsv` under `FERRY_REPO_BASE`  

Format: [Servers view](./servers-view.md), template [`config.example.servers`](../config.example.servers).

Agent child rows also read (read-only, if present):

1. `$AGENT_STATUS_DIR`  
2. `$XDG_RUNTIME_DIR/agent-status`  
3. `$HOME/.local/state/agent-status`  

---

## Developer logging (opt-in, local only)

Shared **fleet-devlog v1** emitter (`lib/fleet-devlog.sh`). Off by default. Fail-open. No network uploader. Never records prompts, file contents, secrets, or free-form paths.

| Control | Default | Behaviour |
|---------|---------|-----------|
| `FLEET_DEVLOG` | unset (off) | `1`/`true`/`on`/`yes` enable; `0`/`false`/`off`/`no` disable (checked first) |
| `~/.config/fleet-devlog/config.json` | absent | Only exact objects `{"enabled":true}` or `{"enabled":false}` after whitespace strip enable/disable; anything else → off |
| `--no-devlog` in argv | — | Disables emit when present in `DEVLOG_ARGV` (ferry snapshots all argv). **Not** a parsed CLI flag: if it is the first token, ferry treats it as the **host** |
| `FLEET_CORR` | unset | Optional correlation token allowed into the log join key |
| `XDG_STATE_HOME` | unset → `$HOME/.local/state` | Log root: `${XDG_STATE_HOME:-$HOME/.local/state}/fleet-devlog/` |
| `XDG_CONFIG_HOME` | unset → `$HOME/.config` | Machine config path for fleet-devlog |

Event file: `…/fleet-devlog/events.jsonl` (rotated when large; hand-rolled JSON, no `jq`).

Delete local data:

```sh
rm -rf ~/.local/state/fleet-devlog
```

---

## Other environment variables

| Variable | Default | Who | Purpose |
|----------|---------|-----|---------|
| `HOME` | from environment | both | Config paths, default `FERRY_REPO_BASE`, remote path joins |
| `XDG_CONFIG_HOME` | `$HOME/.config` | both | Alternate config root for fleet-devlog machine config |
| `XDG_STATE_HOME` | `$HOME/.local/state` | both | fleet-devlog + agent-status fallback |
| `XDG_RUNTIME_DIR` | system | host | Preferred agent-status directory parent |
| `AGENT_STATUS_DIR` | unset | host | Override agent-status root for servers view |
| `SHELL` | `/bin/bash` fallback | host | Blank-shell fallback after exhausted `--resume-closed` |
| `FERRY_LIB` | unset | `mossferry` | `1` → source as library (tests); skip `main` |
| `REPO_SESSION_LIB` | unset | `repo-session` | `1` → define helpers only |
| `FERRY_UPDATE_VERBOSE` | unset | laptop | When set, `ferry update` shows full git pull output on a TTY |
| `GREEN_UI_FORCE_TTY` / `GREEN_UI_MODE` | unset | both | green-ui kit: force TTY glyphs / mode for tests and chrome |
| `TMUX` / tmux binary | system | host | All attach/list operations need a working `tmux` on the host |

---

## Config file location

| Path | Role |
|------|------|
| `~/.config/mossferry/config` | Main `FERRY_*` keys |
| `~/.config/mossferry/servers.tsv` | Optional servers declarations |
| `<repo>/.ferry/servers.tsv` | Per-repo declarations under `FERRY_REPO_BASE` |
| `~/.config/fleet-devlog/config.json` | Devlog machine enable switch only |
| `config.example` (in clone) | Documented defaults (commented) |
| `config.example.servers` (in clone) | Sample servers TSV |

Example minimal laptop config:

```sh
# ~/.config/mossferry/config
FERRY_DEFAULT_HOST=workstation
# FERRY_HOST_CANDIDATES=workstation-lan,workstation
# FERRY_TRANSPORT=mosh
# FERRY_WRAP=auto
```

Example host-oriented overrides (often the same file on the host):

```sh
FERRY_REPO_BASE="$HOME/Repositories"
FERRY_DEFAULT_CMD=neofetch
FERRY_START_MENU=claude,grok
FERRY_BANNER=on
```

---

## What configuration does not cover

- **SSH identity and addresses** — live in `~/.ssh/config`, not ferry.  
- **tmux keybindings** — stock tmux (or your own `tmux.conf`); ferry does not ship a tmux conf.  
- **Hosted CI** — verification is local (`npm test`, `npm run docs:check`, `npm run docs:health`).  

---

## See also

- [Command reference](./command-reference.md)  
- [Getting started](./getting-started.md)  
- [Servers view](./servers-view.md)  
- [Quoting and containment](./quoting-and-containment.md)  
