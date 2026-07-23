---
title: "Documentation"
description: "The green ferry between your machines — install, picker, Grok wrap, and fleet siblings."
section: home
order: 0
---

# mossferry documentation

**mossferry** is the green ferry between your machines. Local `ferry` opens remote tmux sessions over mosh/ssh with an fzf picker; remote `repo-session` owns attach/create/claim. Everyday command: **`ferry`**.

Site: [mossferry.muslewski.com](https://mossferry.muslewski.com) · npm: [`mossferry`](https://www.npmjs.com/package/mossferry)

## Start here

| Path | For |
|------|-----|
| [Getting started](./getting-started.md) | Install local + remote → config → `ferry doctor` |
| [Grok + ferry](./guides/grok-and-ferry.md) | `FERRY_WRAP`, picker `ctrl-g` / `ctrl-a`, mosh vs ssh clipboard |
| [Works with](./works-with.md) | Fleet siblings on the host ferry lands you on |

## What it does

```
┌──────────── local ────────────┐         ┌──────────── remote ───────────┐
│  bin/mossferry                │  mosh   │  bin/repo-session             │
│  - parse args / config        │ ──ssh──▶│  - fzf (or menu) session picker│
│  - launch mosh or ssh         │         │  - create / attach / claim     │
│  - optional grok wrap         │         │  - all tmux logic              │
│  - update, doctor             │         │                                │
└───────────────────────────────┘         └───────────────────────────────┘
```

- **Local:** `ferry` / `mossferry` — host selection, transport, wrap, doctor, update.
- **Remote:** `repo-session` — picker, banners, AI launchers, session lifecycle.
- **Signature (2.7.0):** `FERRY_WRAP` / `grok wrap` under interactive hops; picker launchers default `ctrl-a` → `claude`, `ctrl-g` → `grok`.

## Where other knowledge lives

| Kind | Location |
|------|----------|
| **Public product docs** | `docs/` (this tree) |
| **Architecture mind (Atlas)** | [`mossferry-mind/`](../mossferry-mind/) — zones, decisions, **specs**, **plans** |
| **Human-oriented README** | [`README.md`](../README.md) |
| **Changelog** | [`CHANGELOG.md`](../CHANGELOG.md) |

Agent design specs and implementation plans live in the mind vault (`mossferry-mind/specs/`, `mossferry-mind/plans/`), not under `docs/superpowers/` for new work.
