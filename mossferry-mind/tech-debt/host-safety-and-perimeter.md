---
type: debt
summary: "Mossferry is the door (session hop), not the building — host AI-agent safety, secrets, sandboxes, and trust tiers stay on Manjaro/work-kb; ferry only stays flexible for LAN vs Tailscale and quiet presentation."
tags: [security, perimeter, lan, tailscale, agents, secrets]
status: open
created: 2026-07-24
updated: 2026-07-24
severity: medium
effort: "ongoing (product nits here; host model in work-kb)"
related:
  - "[[client]]"
  - "[[install-config]]"
sources:
  - "work-kb tech-debt ai-agent-host-safety (2026-07-23 research)"
  - "operator morning hygiene pass 2026-07-24"
---

## What's deferred (for mossferry product)

Mossferry remains a **thin door**: mosh/ssh + picker + tmux attach. It must **not** become a multi-tenant isolator, secret manager, or agent sandbox.

Deferred product-adjacent nits only:

- Optional `FERRY_PREVIEW=off|names|capture` for screen-share privacy
- Docs cross-link: full host AI safety lives in **work-kb** `ai-agent-host-safety`, not ferry core
- Keep personal start-menu wallets (`grok-delieta`, etc.) **out** of repo defaults forever

## What is already product (flexible OSS)

| Concern | Ferry role | Operator config |
|---------|------------|-----------------|
| LAN vs Tailscale (or any path) | `FERRY_HOST_CANDIDATES` first reachable; explicit CLI host wins | `~/.ssh/config` Host aliases (LAN IP, TS IP, MagicDNS — never hard-coded in mossferry) |
| Quiet new panes | `FERRY_DEFAULT_CMD=true` (or `clear`) | `~/.config/mossferry/config` |
| Single fixed host | `FERRY_DEFAULT_HOST` | same |
| Transport | `FERRY_TRANSPORT=mosh\|ssh` | same |

Example (home first, roam fallback) — **names only**, paths in ssh config:

```bash
# ~/.config/mossferry/config
FERRY_HOST_CANDIDATES="manjaro,manjaro-remote"
FERRY_DEFAULT_CMD="true"

# ~/.ssh/config
# Host manjaro          → LAN
# Host manjaro-remote   → Tailscale
```

## Why this boundary

Same research as work-kb host safety:

1. Agent blast radius / YOLO damage → vendor sandbox + worktrees (not ferry)
2. Lethal trifecta (untrusted content + secrets + egress) → host policy
3. Supply chain / MCP / skills → host trust tiers
4. Ambient secrets in bashrc → host hygiene
5. Ferry picker hide-lists and `demo$` prompts are **not** security boundaries

## Non-goals

- Docker-per-session as mossferry architecture
- Auto-detecting private IPs in the ferry binary (too environment-specific; breaks OSS users)
- Migrating live tmux sockets for “privacy”
- Shipping operator wallet names in defaults

## Operator pointer

Host day-1/week-1 checklist: `~/Repositories/work-kb/work-kb-mind/tech-debt/ai-agent-host-safety.md`
