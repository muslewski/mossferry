---
title: "Works with"
description: "How mossferry fits the muslewski fleet — ferry lands you on the host where the fleet runs."
section: recipes
order: 5
---

# Works with

**mossferry** is the hop. Sibling tools live (and run) on the **app host** you open with `ferry` — often a headless workstation. Name them in feature docs when a **real** integration exists; this page is the short map.

| Package | Relationship to mossferry | Links |
|---------|---------------------------|--------|
| **agentic-sage** | Passive fleet judge for parallel AI coding sessions. **Optional wire** (`FERRY_SAGE=auto`): when `sage` is on the host PATH, the ferry picker shows sage **facts + judge one-liners** above the pane preview (`sage about --tmux`) and offers **⚖ new judge…** → `sage judge run` (fleet or repo). `FERRY_SAGE=off` disables the wire; neither package hard-depends on the other. | [sage.muslewski.com](https://sage.muslewski.com) · [npm](https://www.npmjs.com/package/agentic-sage) |
| **status-herald** | Curtain cards / status bars for agent panes in tmux. Once ferry attaches you to a session, herald is the status surface inside that pane. | [herald.muslewski.com](https://herald.muslewski.com) · [npm](https://www.npmjs.com/package/status-herald) |
| **llm-armory** | Named executor loadouts (advisor → Grok children). Armory sessions are started **on the host**; ferry + wrap + `ctrl-g` is the laptop path into a Grok-shaped remote session. | [armory.muslewski.com](https://armory.muslewski.com) · [npm](https://www.npmjs.com/package/llm-armory) |
| **token-oracle** | Offline token/cap forecasts used by statuslines and boards on the host. Ferry does not call oracle; it lands you where oracle is wired. | [oracle.muslewski.com](https://oracle.muslewski.com) · [npm](https://www.npmjs.com/package/token-oracle) |
| **memory-atlas** | Code-verified architecture vaults (`*-mind/`). This repo’s understanding lives in `mossferry-mind/`; public guides live in `docs/`. Recollection keeps both honest after ferry-side changes. | [atlas.muslewski.com](https://atlas.muslewski.com) · [npm](https://www.npmjs.com/package/memory-atlas) |

## Contextual edges (not a laundry list)

- **Grok wrap** is a **local client** concern (`FERRY_WRAP` / local `grok` on PATH). The remote start command from picker `ctrl-g` is just `grok` on the host. See [Grok + ferry](./guides/grok-and-ferry.md).
- **Claude / Grok launchers** create sessions on the host where SAGE, herald, armory, and atlas are already installed for day-to-day fleet work.
- There is no hard runtime dependency on the five packages above — they compose by co-location on the host ferry opens. SAGE is the one soft adapter (`FERRY_SAGE`); missing sage is silent classic ferry.

## Rules for authors

1. **Contextual first** — when documenting a feature that displays or depends on a sibling, say so in that page (one clear sentence + link).
2. **Update this table** when you add or remove a real edge.
3. **Do not invent** — if code does not wire it, do not claim it.

## See also

- [Getting started](./getting-started.md)
- [Grok + ferry](./guides/grok-and-ferry.md)
