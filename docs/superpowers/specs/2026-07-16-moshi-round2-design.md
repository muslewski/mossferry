# moshi round 2 — design spec

**Date:** 2026-07-16
**Status:** approved (user-tested round 1 and requested these three changes)
**Baseline:** repo at `12cf4e6` (round-1 refactor + update repair live on both machines)

## Problems (from first real-world use)

1. **No session management in the picker.** Kill and rename require dropping to raw tmux.
2. **Pre-tmux errors are invisible.** `moshi <host> typoo` prints its error remotely, but
   mosh's alternate-screen restore wipes it — the user lands back at their prompt with no
   trace. Same disease `--list` had before it was routed via ssh.
3. **`_curtain` pollutes the picker.** status-herald's per-tab curtain makes a hidden
   window named `_curtain` the *active* window of covered sessions, so the picker's
   window-name column shows `_curtain` instead of the Claude label, and the live preview
   shows herald's status card instead of the session's real screen.

## Decisions

| Decision | Choice |
|---|---|
| Kill/rename UX | fzf keybinds in the one picker: Enter=attach, ctrl-x=kill (y/N confirm), ctrl-r=rename (prompt); header documents keys; list reloads after actions so they chain |
| Error visibility | client-side pre-validation: new `repo-session --validate <repo>` mode, called by moshi over ssh (ControlMaster-warm) before launching mosh; errors print locally, mosh never starts |
| `_curtain` | display-level hidden-window rule, zero herald coupling: config `MOSHI_HIDDEN_WINDOW_GLOB` (default `_*`); name column AND preview fall back to the first non-hidden window |
| Fallback menu | unchanged (attach/new/quit) — keybind actions are fzf-only, documented in help |
| Version | bump to 1.1.0 at merge (first feature release) |

## Behavior

### Picker actions (fzf path only)
- `fzf --expect=ctrl-x,ctrl-r` with header `enter=attach · ctrl-x=kill · ctrl-r=rename · esc=quit`.
- ctrl-x on a session row → `kill <name>? [y/N]` read from the tty → `tmux kill-session -t =<name>` → picker reloads.
- ctrl-r on a session row → `new name: ` read from the tty → `tmux rename-session -t =<name> <new>` → picker reloads.
- Action keys on the `➕ new session…` row: ignored, picker reloads.
- Esc/cancel semantics unchanged (exit 130).
- Applies identically to global and repo-scoped pickers.

### `--validate <repo>` (repo-session) + pre-validation (moshi)
- `repo-session --validate <repo>`: dispatched before any tmux call; exit 0 if
  `$MOSHI_REPO_BASE/<repo>` is a directory; else the existing typo error + repo list on
  stderr, exit 1. Never invokes tmux.
- moshi: any invocation that carries a repo token (first non-flag arg after host) and will
  launch mosh first runs `ssh <host> <remote_bin> --client-version <v> --validate <repo>`.
  Exit 0 → launch mosh exactly as today. Nonzero → relay the validation output, exit 1,
  no mosh. `--list` and repo-less invocations skip validation (already visible / nothing
  to validate). Grid flags are covered: a typo'd `--resume-or-new` now fails loud and local.

### Hidden-window display rule
- New config key `MOSHI_HIDDEN_WINDOW_GLOB` (default `_*`), env-overridable like all keys.
- In `build_session_rows`: if the session's active window name matches the glob, display
  the name of the first non-matching window instead; if every window matches, keep the
  active name. Window count stays truthful.
- Rows gain a trailing preview-target field (`<session>:<window-index>` of the displayed
  window); the fzf preview capture-panes that target, so covered sessions preview their
  real content, not the curtain card.

## Out of scope
- status-herald itself: untouched (the `_`-prefix convention is the contract).
- Fallback-menu kill/rename.
- Attaching to a covered session still shows the curtain first (herald's keypress-reveal
  handles it — that is herald UX, not moshi's).
