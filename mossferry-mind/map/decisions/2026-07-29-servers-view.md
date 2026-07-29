---
type: decision
summary: "Servers view is a second face inside run_picker; merge key is (port, pid); declaration format is TSV not YAML."
status: active
created: 2026-07-29
updated: 2026-07-29
related:
  - "[[repo-session]]"
  - "[[client]]"
  - "[[install-config]]"
---

## Context

Fleet research (`work-kb` g04–g07) needed a way to see what is actually
listening on the desk — syndcast, render, FreeLLMAPI, postgres, detached
armory children — and whether a Mac browser can reach it. Wrong URLs and
loopback binds share one symptom; the picker only listed tmux sessions.

## Decisions

### 1. Face inside `run_picker`, not a second binary

The interactive UI is already one function (`run_picker`) with self-reentry
helpers (`--picker-rows` / `--picker-preview` / `--picker-kill` /
`--picker-rename`). A servers face reuses that pattern (`ctrl-s` toggle,
`--picker-servers-*`, `--servers` one-shot). A second binary would duplicate
config load, banner, and fzf lifecycle for no gain. Cite: mossferry/g04.

### 2. Merge key is `(port, pid)`, not a name

Names are not unique and not stable across restarts and worktrees. Six
discovery layers (ss, systemd user, docker, tmux pane tree, /proc cwd,
declarations) merge on port (and pid where relevant). Declarations never
assert liveness. Cite: mossferry/g05.

### 3. TSV declarations, not YAML/JSON

`yq` and `jq` are absent on the target host; mossferry is zero-dependency
bash. TSV parses with `while IFS=$'\t' read`. YAML in bash is a well-known
way to get a subtly wrong parser. Cite: host constraints 2026-07-29; g05
YAML recommendation overruled.

## Safety properties

- Port **8791** is always reserved (FreeLLMAPI); never a primary Mac URL.
- `servers_fix_plan` returns `tunnel` for `db`/`spine`, never a rebind recipe.
- `FERRY_SERVERS_FIX` defaults off.
- Agent-status directory is read-only; missing dir ⇒ zero rows.

## See also

- Spec surface: `docs/servers-view.md`, `lib/servers.sh`
- Reachability failure modes: mossferry/g07
- Render preflight honesty: mossferry/g06
