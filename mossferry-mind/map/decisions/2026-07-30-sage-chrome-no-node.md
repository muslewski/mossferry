---
type: decision
summary: "Picker sage chrome parses about --json with awk, never node -e — hermetic HOME and desk nvm shims must not empty preview."
status: active
date: 2026-07-30
tags: [repo-session, sage, hermetic, tests]
related:
  - "[[repo-session]]"
  - "[[tests]]"
  - "[[2026-07-30-hermetic-home-no-node-shim]]"
  - "[[2026-07-30-survivors-reconcile]]"
---

## Context

t45 failed on desk PATH (`out=[] sage_log=[about --tmux demo --json]`) while
the same commit passed under cold PATH. Product used `node -e` after
`sage about --json`; test `HOME` is hermetic; desk `~/.local/bin/node` nvm
shim then exits 127.

## Decision

`print_picker_preview` extracts `found` / `facts` / `judge` with small awk
helpers (`_ferry_json_str_field`, `_ferry_json_bool_true`). No Node for chrome.

## Consequences

- t45 forces a broken node ahead of PATH and still expects chrome.
- Suite verdict matches under desk PATH and `/usr/bin:/bin:/usr/local/bin`.
- Full JSON edge cases (escaped quotes in facts) may need a real parser later;
  sage about contract strings are plain enough for awk field split.
