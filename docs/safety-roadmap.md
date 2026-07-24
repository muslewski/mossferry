---
title: "Safety roadmap"
description: "What mossferry is responsible for today, what stays on the host, and safety-oriented features coming later."
section: guides
order: 20
---

# Safety roadmap

**Coming soon** — more safety-oriented product surfaces. This page is the honest boundary today plus the direction we will ship without turning the ferry into a security product.

## Boundary (load-bearing)

| Layer | Role |
|-------|------|
| **mossferry** | The **door** — pick a host, hop mosh/ssh, attach/create remote tmux |
| **Host OS + agent tools** | The **building** — secrets, sandboxes, firewalls, trust tiers for AI sessions |

Same Linux user on the host can still reach other sessions’ files. Ferry never pretends otherwise.

### What ferry already helps with (not “security theater”)

- **Flexible paths home:** `FERRY_HOST_CANDIDATES` — prefer LAN when reachable, fall back to Tailscale/remote aliases (IPs stay in *your* `~/.ssh/config`)
- **Quiet new panes:** `FERRY_DEFAULT_CMD=true` (or `clear`) — less identity paint on shared screens
- **Explicit transport:** `FERRY_TRANSPORT=mosh|ssh` — you choose roam vs clipboard-friendly hop
- **Personal start menu** stays in *your* config (wallets/profiles) — never forced into OSS defaults

### What is **not** ferry’s job

- Agent sandboxes / YOLO blast radius
- Secret stores or stripping tokens from agent env
- Multi-tenant isolation between panes
- Treating picker hide-lists or cosmetic prompts as security boundaries

Host-level AI-agent operating model (research snapshot, day-1 hygiene) lives with the operator’s host docs — for this author’s fleet: work-kb *ai-agent-host-safety* debt; product mind: [`mossferry-mind/tech-debt/host-safety-and-perimeter.md`](../mossferry-mind/tech-debt/host-safety-and-perimeter.md).

## Coming soon (product nits, optional)

Planned when they stay thin and optional — no mandatory Docker-per-session architecture:

| Idea | Intent |
|------|--------|
| **`FERRY_PREVIEW=off\|names\|capture`** | Screen-share / stream mode: hide pane previews or scrub names |
| **Safer share defaults** | Documented recipe for titles-off + quiet start + banner optional |
| **Doctor tips** | Surface “host safety is outside ferry” + optional link to sibling tools (e.g. agentic-sage guard is host-side) |
| **Docs recipes** | Home-LAN first, travel-TS first — same candidates pattern, different order |

Nothing here changes the rule: **secrets and agent trust tiers stay on the host.**

## Related

- [Getting started](./getting-started.md) — install + `ferry doctor`
- [Grok + ferry](./guides/grok-and-ferry.md) — wrap / transport
- [Works with](./works-with.md) — fleet siblings *on the host* ferry lands you on
- [SECURITY.md](../SECURITY.md) — vulnerability reporting + local secrets hygiene
