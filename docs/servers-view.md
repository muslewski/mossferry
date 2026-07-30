---
title: "Servers view"
description: "What is listening on the ferry host, and can the Mac browser reach it?"
section: guide
order: 25
---

# Servers view

The picker’s **servers face** (`ctrl-s`) answers: **what is listening on this
host, and can a Mac browser reach it?** Here “server” means a **listener**
(port / process), not the remote machine — that machine is always the
**host**. Discovery is read-only. Ferry reports; it does not supervise
processes by default.

**Platform:** live discovery uses Linux `ss -ltnp` and `/proc` inside
`lib/servers.sh`. It runs on the **host** (or via `ferry <host> --list-servers`
over ssh). A stock macOS userland has neither `ss` nor `/proc` — do not expect
the servers face to work if `repo-session --servers` is run on a bare Mac.
## How to open it

| Surface | How |
|---------|-----|
| Interactive picker | `ctrl-s` toggles sessions ↔ servers (header shows the face) |
| One-shot (remote) | `repo-session --servers` · `--servers --json` |
| One-shot (client) | `ferry <host> --list-servers` · `--list-servers --json` |

**Chords (servers face):** `enter` = copy Mac URL when `mac_state=reachable`
(OSC52; never opens a browser) · `ctrl-f` = print fix plan · `ctrl-s` =
back to sessions · `esc` = quit.

## Declaration format (TSV)

Declarations are **tab-separated lines**, not YAML or JSON. mossferry is
zero-dependency bash: `yq` and `jq` are not assumed. Parse with
`while IFS=$'\t' read -r …`.

Locations, merged in order (**later wins per port**):

1. `~/.config/mossferry/servers.tsv`
2. `<repo>/.ferry/servers.tsv` for repos under `FERRY_REPO_BASE`

Copy [`config.example.servers`](../config.example.servers) as a starting
template.

```
# port	id	class	label	mac	health
# class: spine|docker|dev|preview|db|agent|infra
# mac:   ok|prefer-ts|never
8791	freellmapi	infra	FreeLLMAPI	never	http://127.0.0.1:8791/health
3000	syndcast-next	dev	Syndcast app	ok	-
```

- Blank lines and `#` comment lines are skipped.
- `-` means "not set".
- Unknown extra columns are ignored so the format can grow.

## Declarations never assert liveness

A declaration contributes `label`, `class`, and `mac` policy only. Live
`ss` always wins on `bind` and `pid`. A declared port with **no** listener
becomes state `declared-missing` — the most useful row: the thing you think
is running is not.

## Row model (14 columns)

```
port  state  id  class  label  bind  pid  comm  repo  owner  mac_state  mac_url  health  restart
```

### `state` vocabulary

| Value | Meaning |
|-------|---------|
| `LISTEN` | Live listener (or live agent child with `port=-`) |
| `declared-missing` | Declared, no listener |
| `FOREIGN` | Listener occupies a declared port but cwd/repo disagrees |

### `mac_state` vocabulary

| Value | Meaning |
|-------|---------|
| `reachable` | Bound on all-interfaces (or a non-loopback host IP); Mac URL available |
| `loopback-only` | Bound to `127.0.0.1` / `::1` — up ≠ Mac-reachable |
| `reserved` | Port on the denylist and/or `mac=never` (includes FreeLLMAPI **8791**) |
| `unknown` | Not enough data |

Primary `mac_url` is never a bare `http://127.0.0.1:…`. Prefer
`preview-url` / Tailscale when present.

Reserved ports (imported from `preview-serve`):  
`8791 3001 5432 6379 27017 8080 5173 3000`.

## Fix plan (`ctrl-f`) — state machine, not kill-all

| Condition | Action |
|-----------|--------|
| `reachable` | `none` — show Mac URL |
| `loopback-only` + `preview`/`dev` | `recipe` — print `preview-serve <cwd> <port>` |
| `loopback-only` + `db`/`spine`/`agent` | `tunnel` — print `ssh -L` snippet; **never rebind** |
| `reserved` | `refuse` — FreeLLMAPI badge for 8791 |
| `declared-missing` | `declare` — show declaration; never auto-start |

`FERRY_SERVERS_FIX` defaults **off**. A recipe is printed only; execution
requires the switch explicitly on. Databases and spine services never receive
a rebind recipe.

## Detached agent children

Armory children that write the Agent Status Provider directory appear as
`class=agent` rows (`port=-`). Directory resolution (read-only):

1. `$AGENT_STATUS_DIR`
2. `$XDG_RUNTIME_DIR/agent-status`
3. `$HOME/.local/state/agent-status`

Missing directory ⇒ zero agent rows, exit 0. No armory dependency.

## Related

- Library: `lib/servers.sh`
- Example: `config.example.servers`
