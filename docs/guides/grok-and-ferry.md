---
title: "Grok + ferry"
description: "Keep ferry as the entrypoint: FERRY_WRAP / grok wrap on the laptop, ctrl-g / ctrl-a launchers on the remote picker."
section: guide
order: 20
---

# Grok + ferry (Mac client → headless host)

Keep **`ferry`** as the entrypoint. Do not replace it with raw `grok wrap ssh`.

Two layers must not be confused:

| Layer | Who | What |
|-------|-----|------|
| `ferry` on Mac | **local** | mosh/ssh (+ optional `grok wrap`) into remote `repo-session` |
| picker `ctrl-g` | **remote** | create session whose start command is `grok` |
| picker `ctrl-a` | **remote** | same, but `claude` |
| enter | **remote** | `FERRY_DEFAULT_CMD` (default `neofetch`) |

## Local: `FERRY_WRAP` / `grok wrap`

AI launchers only set the **remote** start command. Clipboard OSC 52 and dirty-disconnect restore need **`grok wrap` on the laptop** around the whole mosh/ssh hop.

With default **`FERRY_WRAP=auto`**, ferry runs `grok wrap mosh …` / `grok wrap ssh …` whenever local `grok` is on PATH — so you keep typing `ferry`, press `ctrl-g` for a Grok session, and wrap is already under you.

```sh
# on the Mac (once)
curl -fsSL https://x.ai/cli/install.sh | bash   # provides `grok wrap`

# optional — force wrap on, or prefer SSH for clipboard reliability
# echo 'FERRY_WRAP=auto' >> ~/.config/mossferry/config
# echo 'FERRY_TRANSPORT=ssh' >> ~/.config/mossferry/config

ferry                          # same as always
# in picker: ctrl-g on ➕ new / repo / 🏠 home → remote grok session
ferry doctor                   # reports local grok wrap + transport
```

| Key | Default | Meaning |
|-----|---------|---------|
| `FERRY_WRAP` | `auto` | Prefix interactive transport with `grok wrap` when local `grok` exists (`auto` / `on` / `off`). Not used for `--list`. |
| `FERRY_TRANSPORT` | `mosh` | Interactive hop: `mosh` (roam) or `ssh` (better OSC 52 with wrap). |
| `FERRY_LAUNCHERS` | `ctrl-a:claude,ctrl-g:grok` | Remote picker AI-launcher keys (`key:command` pairs; empty disables; `ctrl-x` / `ctrl-r` reserved). |

Set `FERRY_WRAP=off` to disable wrap.

## Remote: picker AI launchers

On destination rows (repo / `➕ new repo…` / `🏠 home session…`) and on the main picker's `➕ new session…` row, press a configured launcher key instead of enter to create that session with that start command. Overrides `FERRY_DEFAULT_CMD`, `--claude`, and `-- cmd…` for that one creation. Enter keeps the default. On an existing-session row, launcher keys are ignored (list reloads).

## mosh and clipboard

Many mosh builds **strip OSC 52**, so wrap cannot invent clipboard bytes that never arrive. Use `FERRY_TRANSPORT=ssh` when you need reliable Grok → local clipboard, or keep host-side yank pipes (e.g. tmux → `pbcopy`).

## Voice, mic, and Ctrl+Space (why they feel broken)

**`ctrl-g` starts Grok on the remote host** (Manjaro). Your **microphone is on the Mac**. Ferry/mosh/ssh only carry a terminal stream — not audio devices.

| What you want | Where it must run | Ferry hop? |
|---------------|-------------------|------------|
| Grok **voice** / push-to-talk / mic | **Local Mac** `grok` (or Grok desktop) | No — use local Grok |
| Grok **coding in a repo** on Manjaro | Remote `grok` in tmux | Yes — `ferry` + `ctrl-g` |
| Clipboard OSC 52 | Local wrap + preferably `FERRY_TRANSPORT=ssh` | Yes — wrap layer |

So if you hop with ferry, open Grok, and **Ctrl+Space does nothing / mic is dead**, that is expected over a remote TUI session:

1. The process that would open the mic is **on Manjaro**, not on the Mac.
2. Terminal multiplexers (tmux) and mosh often **eat or remap** local chords (Ctrl+Space is also a common IME / OS binding).
3. “Voice command” paths that open a **host-side** or **cloud** channel may still partially work while hardware PTT fails — that asymmetry is normal.

**Practical split**

```text
Mac local:   grok          → voice, mic, Ctrl+Space, clipboard experiments
Mac → host:  ferry …       → long coding sessions, fleet tools, remote logs
```

Do not expect ferry to make remote Grok hear your laptop mic. If you need both, run voice **locally** and keep ferry for remote work sessions.

## Session names: `hermes-3` vs ferry vs Hermes

Ferry does **not** name Grok sessions `hermes-3`.

| Name you see | What it is |
|--------------|------------|
| `syndcast`, `syndcast-2`, … | Classic ferry repo sessions (`repo`, `repo-N`) |
| Name you typed for **🏠 home session** | e.g. you entered `hermes` → later free names may be `hermes-2`, `hermes-3` |
| Real tmux `ccops-…` | Hermes **coding-ops** jobs on the host |
| Picker display `hermes:running:…` | Ferry **badge** for `ccops-*` (display only — attach target is still the real `ccops-…` name) |

If the **tmux session name** is literally `hermes-3`, you (or a home-session create) chose that stem earlier — or Hermes ops created a related session. Check with `tmux ls` on Manjaro. Ferry’s `ctrl-g` only sets the **start command** to `grok`; the session name still comes from the repo / home naming rules above.

## Fleet on the host

Ferry only gets you there. Once attached, agent CLIs and fleet tools (**agentic-sage**, **status-herald**, **llm-armory**, **token-oracle**, **memory-atlas**) run on the remote host — see [Works with](../works-with.md).

## See also

- [Getting started](../getting-started.md)
- [README — Grok + ferry](../../README.md) (same story; this guide is the docs-kit home for it)
