---
title: "Servers view"
description: "What is listening on the ferry host, and can the Mac browser reach it?"
section: guide
order: 25
---

# Servers view

A second face in the ferry picker answers: **what is actually running on this
box, and can my Mac browser reach it?** Discovery is read-only. The ferry
reports; it does not supervise processes.

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

## Related

- Example file: `config.example.servers`
- Discovery library: `lib/servers.sh`
- One-shot: `repo-session --servers` / `ferry --list-servers`
