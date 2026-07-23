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

## Fleet on the host

Ferry only gets you there. Once attached, agent CLIs and fleet tools (**agentic-sage**, **status-herald**, **llm-armory**, **token-oracle**, **memory-atlas**) run on the remote host — see [Works with](../works-with.md).

## See also

- [Getting started](../getting-started.md)
- [README — Grok + ferry](../../README.md) (same story; this guide is the docs-kit home for it)
