---
title: "Documentation"
description: "Attach to a remote repo’s tmux session in one command — install, usage, servers view, and fleet siblings."
section: home
order: 0
---

# mossferry documentation

**mossferry** opens a remote repository’s tmux session from your laptop in one command (`ferry`), over mosh or ssh, with an fzf picker. Remote brain: `repo-session`.

Site: [mossferry.muslewski.com](https://mossferry.muslewski.com) · npm: [`mossferry`](https://www.npmjs.com/package/mossferry)

## Words the tool uses

| Word | Means |
|------|--------|
| **host** | The machine you hop to — an ssh `Host` alias from config, not an IP |
| **repo** | One basename under `FERRY_REPO_BASE` (default `~/Repositories`) |
| **session** | A tmux session on the host |
| **picker** | fzf (or numbered menu) UI that runs **on the host** inside the hop |
| **attach** | `tmux attach` to a chosen session |
| **servers face** | Second picker face (`ctrl-s`): listeners / Mac reachability — see [Servers view](./servers-view.md) |

## Start here

Reading order matches the sidebar:

| Path | For |
|------|-----|
| [Getting started](./getting-started.md) | Install laptop + host → config → `ferry doctor` |
| [Command reference](./command-reference.md) | Full flags, combinations, exit codes, real output |
| [Configuration](./configuration.md) | Every `FERRY_*` key, env vars, defaults |
| [Usage](./usage.md) | Compact flag map and picker summary |
| [Quoting and containment](./quoting-and-containment.md) | Safe repo names, remote argv quoting, literal session match, status gaps |
| [Troubleshooting](./troubleshooting.md) | Symptom fixes, full `ferry doctor`, [macOS client](./troubleshooting.md#macos-client), test-harness rules |
| [Servers view](./servers-view.md) | Listeners, Mac reachability, fix plans |
| [Grok + ferry](./guides/grok-and-ferry.md) | `FERRY_WRAP`, start menu, mosh vs clipboard |
| [Safety roadmap](./safety-roadmap.md) | Door vs building; planned safety nits |
| [Works with](./works-with.md) | Fleet siblings on the host ferry opens |

## What it does

```
┌──────────── laptop ───────────┐         ┌──────────── host ─────────────┐
│  bin/mossferry (ferry)        │  mosh   │  bin/repo-session             │
│  - parse args / config        │ ──ssh──▶│  - fzf (or menu) session picker│
│  - launch mosh or ssh         │         │  - create / attach / claim     │
│  - update, doctor             │         │  - all tmux logic              │
└───────────────────────────────┘         └───────────────────────────────┘
```

- **Laptop:** `ferry` / `mossferry` — host selection, transport, wrap, doctor, update.
- **Host:** `repo-session` — picker, banners, AI start menu, session lifecycle.
- **Default hop:** mosh (roam). Set `FERRY_TRANSPORT=ssh` when you need a plain ssh hop.

## Where other knowledge lives

| Kind | Location |
|------|----------|
| **Public product docs** | `docs/` (this tree) |
| **Architecture mind (Atlas)** | [`mossferry-mind/`](../mossferry-mind/) — zones, decisions, specs, plans |
| **Human-oriented README** | [`README.md`](../README.md) |
| **Changelog** | [`CHANGELOG.md`](../CHANGELOG.md) |

Agent design specs and implementation plans live in the mind vault (`mossferry-mind/specs/`, `mossferry-mind/plans/`), not under `docs/superpowers/` for new work.
