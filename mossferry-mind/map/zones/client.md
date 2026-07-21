---
type: zone
summary: "Local ferry CLI (bin/mossferry, npm aliases ferry|mossferry): load FERRY_* config, mosh/ssh launch of repo-session, pre-validate typos over ssh, doctor and update ops chrome."
tags: [cli, client, mosh, ssh]
status: seeded
created: 2026-07-21
updated: 2026-07-21
verifiedAt: unverified
owns:
  routes: []
  testids: []
  globs:
    - "bin/mossferry"
  tools: []
depends:
  - "[[green-ui]]"
invariants: []
skills: []
related:
  - "[[repo-session]]"
  - "[[install-config]]"
sources: []
---

## What this is

The **local client** half of mossferry. Runs where you type `ferry`: resolves
the repo root through symlinks, sources `lib/green-ui.sh` (or plain fallbacks),
loads config with **env > `~/.config/mossferry/config` > built-in defaults**,
then either runs local ops (`doctor`, `update`, `--help`) or launches the
remote `repo-session` over **mosh** (interactive) or **ssh** (`--list`).

## Anchors

- `bin/mossferry` — sole owned surface; npm `bin` also maps `ferry` → this file.
- Boundary: everything that must not require a remote tmux server (config
  parse, version, doctor checks, update pull, local error lines prefixed
  `mossferry:`).

## Invariants

None claimed yet on seed. README load-bearing behaviors to verify later:

- Repo-bearing mosh launches run `repo-session --validate` over ssh first so
  unknown repos never enter mosh alternate screen.
- Missing `lib/green-ui.sh` must not kill the tool (inline fallbacks).

## Lineage

Inferred from README architecture diagram + `bin/mossferry` header/comments on
2026-07-21 atlas-seed pass. Not yet stamp-verified against code.
