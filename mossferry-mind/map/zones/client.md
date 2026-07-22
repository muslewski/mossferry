---
type: zone
summary: "Local ferry CLI (bin/mossferry): FERRY_* config, mosh/ssh launch of repo-session, optional grok wrap, pre-validate over ssh, doctor/update."
tags: [cli, client, mosh, ssh, grok-wrap]
status: active
created: 2026-07-21
updated: 2026-07-22
verifiedAt: unverified
owns:
  routes: []
  testids: []
  globs:
    - "bin/mossferry"
  tools: []
depends:
  - "[[green-ui]]"
invariants:
  - "Interactive transport only: FERRY_WRAP may prefix mosh/ssh with grok wrap; --list/doctor/update never wrap."
  - "AI launchers (ctrl-g) are remote startcmd only — wrap is always local-side around the whole hop."
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
remote `repo-session` over **mosh** (default) or **ssh** (`FERRY_TRANSPORT` /
`--list`).

## Anchors

- `bin/mossferry` — sole owned surface; npm `bin` also maps `ferry` → this file.
- `launch_remote` / `_ferry_run_transport` / `_ferry_should_wrap` — interactive hop.
- Boundary: everything that must not require a remote tmux server (config
  parse, version, doctor checks, update pull, local error lines prefixed
  `mossferry:`).

## Invariants

- Repo-bearing interactive launches run `repo-session --validate` over ssh first
  so unknown repos never enter the alternate screen.
- Missing `lib/green-ui.sh` must not kill the tool (inline fallbacks).
- `FERRY_WRAP=auto` (default) prefixes interactive mosh/ssh with `grok wrap`
  only when local `grok` is on PATH; `--list` is never wrapped.
- Picker `ctrl-g` → remote start command `grok` lives in `[[repo-session]]`;
  it does **not** re-wrap mid-session. Wrap is decided at connect time on the client.

## Grok clipboard path

Mac needs the Grok CLI installed for wrap. mosh often strips OSC 52 — use
`FERRY_TRANSPORT=ssh` when Grok→local clipboard must be reliable, or host-side
yank pipes (tmux → pbcopy).

## Lineage

Seed 2026-07-21; wrap/transport added 2026-07-22 (2.7.0).
