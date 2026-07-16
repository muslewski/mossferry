# picker AI launchers — design spec

**Date:** 2026-07-17 · **Status:** approved · **Version target:** 2.3.0

## Problem
Creating a session always starts it with `FERRY_DEFAULT_CMD` (neofetch) unless a flag was passed at launch. The user wants to keep that default, but ALSO — at destination-pick time — press a key to open the selected destination (existing repo, new repo, or home session) directly with an AI CLI (`claude`, `grok`). Must be configurable: this ships open source and other people have other CLIs.

## Behavior

**Config** — new key `FERRY_LAUNCHERS`, default `"ctrl-a:claude,ctrl-g:grok"`. Comma-separated `key:command` pairs. `command` may contain spaces/args but not commas (split on FIRST colon). Valid keys: `ctrl-<letter>`, `alt-<letter>`, `f1`–`f12` (fzf-bindable; bare letters are impossible — they type into the fzf query). `ctrl-x` and `ctrl-r` are reserved for kill/rename and are skipped if configured. Empty value disables the feature entirely. Invalid pairs are silently skipped.

**Where the keys work** — pressing a launcher key instead of enter selects the highlighted row AND arms the launcher command as that session's start command:
- The destination sub-picker (global new-session chain): existing repo rows, `➕ new repo…`, `🏠 home session…`.
- The `➕ new session…` row of the main picker, BOTH global and repo-scoped (scoped creates directly in that repo with the launcher command; global proceeds into the sub-picker with the launcher armed — a subsequent launcher key there re-arms/overrides).
- On an existing-session row of the main picker: ignored, list reloads (same as ctrl-x/ctrl-r on the new-session row today).

**Precedence** — an armed launcher overrides `FERRY_DEFAULT_CMD`, `--claude`, and `-- cmd…` for that one creation (pick-time intent beats launch-time flags). Enter keeps today's behavior exactly.

**Hints** — the sub-picker's header (under the banner) gains a dynamically generated hints line: `enter=<FERRY_DEFAULT_CMD> · ctrl-a=claude · ctrl-g=grok` (built from the parsed config, not hardcoded). Main-picker hints line stays as-is (README documents the keys). With `FERRY_LAUNCHERS` empty, all headers and `--expect` lists are exactly today's.

**No-fzf fallback menu** — unaffected (degraded mode keeps default command; documented).

**LIB exports** — `parse_launchers` (reads `FERRY_LAUNCHERS` into parallel arrays `LAUNCHER_KEYS` / `LAUNCHER_CMDS`, applying the validity + reserved-key rules) and `launcher_cmd <key>` (prints the command for a key, prints nothing/exit 1 if unknown).

## Acceptance
- t29 (LIB): default config → `parse_launchers` yields keys `ctrl-a ctrl-g`, cmds `claude grok`; `launcher_cmd ctrl-g` → `grok`.
- t30 (LIB): `FERRY_LAUNCHERS="ctrl-x:evil,banana:claude,alt-c:claude code"` → ctrl-x skipped (reserved), banana skipped (invalid), alt-c → `claude code` (args survive the first-colon split).
- t31: with a launcher armed, the created session's start command is the launcher command — asserted via the fake-tmux log (home-session and repo paths both covered), and enter/no-launcher still produces `FERRY_DEFAULT_CMD`.
- t32 (LIB): `FERRY_LAUNCHERS=""` → `parse_launchers` yields nothing; `launcher_cmd ctrl-a` exits nonzero.
- Existing t1–t28, m1–m16, install tests: green, assertions unmodified.
- `config.example` documents `FERRY_LAUNCHERS` with the default and the pair syntax; README picker section documents the keys and precedence.
- Manual checklist (user): ctrl-a on a repo row opens it in claude; ctrl-g on `🏠 home session…` opens home in grok; enter still gives neofetch; scoped `➕ new session…` + ctrl-a works.
