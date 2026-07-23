---
type: decision
summary: "Create path uses nested start menu (FERRY_START_MENU) over hotkey-only AI launchers; personal profile names stay out of shipped defaults."
status: active
created: 2026-07-23
updated: 2026-07-23
related:
  - "[[repo-session]]"
  - "[[install-config]]"
---

## Context

Picker AI entry used only `FERRY_LAUNCHERS` hotkeys (`ctrl-a:claude`,
`ctrl-g:grok`). Power users stacked private multi-profile launchers into
that string. For an open-source default surface that is (a) hard to discover,
(b) privacy-risky if personal command names leak into docs/examples, and
(c) not scalable past a few chords.

## Decision

1. **Primary create UX** is a nested fzf/menu after destination pick:
   first row **default (no AI)** = `FERRY_DEFAULT_CMD`, then each entry from
   `FERRY_START_MENU` (default `claude,grok` — generic only).
2. **`FERRY_LAUNCHERS`** remains as *optional* hotkeys; default is **empty**
   so new installs are menu-first.
3. Personal wallet/profile command names live only in the user's
   `~/.config/mossferry/config`, never in repo defaults or OSS examples.

## Kill-path companion fix

fzf binds must use `n="{1}"` (quoted). Unquoted `n={1}` drops trailing
spaces in the shell assignment, so `kill-session -t =name` silently fails
for session names with trailing/embedded whitespace. Rename validates the
same name grammar as create.
