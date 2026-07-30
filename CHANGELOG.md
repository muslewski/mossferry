# Changelog

All notable changes to mossferry are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2.8.0] — 2026-07-30

### Changed

- **Invalid repo names are rejected on the laptop before any ssh.** A token
  outside `A–Z a–z 0–9 . _ -`, or path-shaped (`/`, `\`, `..`), prints
  `repo-session: invalid repo name '…'` and exits **1** with no network attempt.
  Previously a typo often surfaced as a DNS error (`Could not resolve hostname …`),
  which looked like a network problem. Host `repo-session` uses the same rule.
- **`doctor` short-circuits after a failed BatchMode connect.** Remaining remote
  probes are skipped (info: `remote checks skipped — ssh BatchMode connect failed`)
  instead of blocking on an unreachable host. Exit stays **1** when connect fails.
  Every doctor ssh probe also uses BatchMode + ConnectTimeout=5.
- **Remote argv is fully shell-quoted** on ssh list/validate hops and on mosh
  (`bash -lc '…'`). OpenSSH’s bare-space join no longer splits repo names or flags
  that contain spaces or metacharacters once they pass the local shape gate.
- **Session match is fixed-string** for scoped lists (repo dots are not regex).
  Scoped `--list` validates that the repo directory exists; create cleans an empty
  orphan directory after a failed `git init`.
- **Help and examples use neutral placeholders** (`workstation`, `my-app`) instead
  of personal host/repo names. Ferry help leads with a command index; primary
  usage line is `mossferry <host>`.

### Added

- **Servers face** in the picker (`ctrl-s`): live listeners merged from process
  discovery and optional `servers.tsv` declarations, Mac reachability, and
  `ctrl-f` fix plans (recipes for previews / tunnels for services — never a
  silent rebind). One-shots: `repo-session --servers` / `--servers --json`,
  client `ferry <host> --list-servers` / `--list-servers --json`. Doctor prints
  a best-effort servers summary (info only; discovery errors never fail doctor
  alone).
- **fleet-devlog v1** — shared, **opt-in**, **local-only** developer log (no
  network). Off by default; enable with `FLEET_DEVLOG=1` or
  `~/.config/fleet-devlog/config.json` `{"enabled":true}`. Writes under
  `$XDG_STATE_HOME/fleet-devlog/` (fail-open; never changes command exit codes).
  `--no-devlog` anywhere in ferry argv disables emit for that run (not a parsed
  flag — as first token it is still treated as the host).

### Fixed

- **`install.sh` failures exit nonzero** when `mkdir` / `ln` / `cp` fail (no
  silent partial install).
- **UTF-8 BOM** is stripped before sourcing config and `VERSION` so a BOM-saved
  file no longer breaks version reads.
- **Sage picker chrome** parses `sage about` JSON with awk (not `node -e`) so a
  broken/missing node on PATH cannot empty the preview under hermetic or desk
  PATH layouts.

### Docs

- Public docs expanded: README around one-command remote attach; command
  reference and configuration from verified flags; troubleshooting by symptom
  (including doctor and test-harness contract); quoting/containment; servers
  view; neutral examples throughout.

## [2.7.4] — 2026-07-29

### Added

- **Grok dual-wallet badge** in the picker: when a pane runs Grok, display
  `g:delieta:…` / `g:muslewski:…` and cmd `grok[delieta]` by reading
  `GROK_HOME` from the pane process (Linux `/proc`). Makes company vs personal
  wallets visible so attach never guesses wrong. Personal start-menu names still
  live only in user config.
- **Optional agentic-sage wire** (`FERRY_SAGE=auto` default): when `sage` is on
  the remote PATH, the picker preview shows sage facts + judge one-liners above
  the pane capture, and **⚖ new judge…** creates a session via
  `sage judge run --fleet` or `--repo`. `FERRY_SAGE=off` restores classic ferry.
  One-liners are produced by sage (not ferry). See works-with / design
  `2026-07-24-ferry-sage-wire-design`.

### Fixed

- **Frozen picker sessions that could not be killed**: modern fzf (0.36+) already
  shell-quotes placeholders. The kill/rename binds used `n="{1}"`, which
  expanded to `n="'name'"` — `kill-session` then targeted a session literally
  named `'name'` (with quotes), failed silently (`|| true`), and the row stayed
  after reload. Binds now take the full line `{}` and tab-split field 1 (also
  preserves trailing-space names that `{1}` would strip). `picker_kill` strips
  one layer of wrapping quotes as defense-in-depth.
- **Picker cycle wrap duplicated the list**: pressing up onto `➕ new session…`
  ran `capture-pane -t` with an empty field-6 target, so the preview mirrored
  the picker itself (looked like duplicate sessions). Preview now guards
  `[ -n {6} ]` and shows a create hint on that row.
- **Picker kill of oddly-named sessions**: earlier fix quoted `n="{1}"` for
  trailing spaces; that interacted badly with fzf’s auto-quoting (see above).
  Rename still rejects invalid names; scoped repo filter tolerates trailing
  whitespace so those sessions still appear under `ferry … <repo>`.

### Changed

- **Nested start-command menu** on create (`FERRY_START_MENU`, default
  `claude,grok`): after picking a destination you choose **default (no AI)** or
  an AI CLI. Optional `FERRY_LAUNCHERS` hotkeys are **empty by default** (prefer
  the menu). Personal profile names stay in user config only — not in shipped
  defaults.

## [2.7.3] — 2026-07-23

### Added

- **Picker update nudge**: when client and remote `VERSION` differ, the fzf
  header (and numbered menu) shows a subtle line
  `↑ update  client X · remote Y  →  ferry update` so hoppers notice without
  digging through doctor/stderr.

## [2.7.2] — 2026-07-23

### Changed

- **Picker kill is instant and in-place**: `ctrl-x` no longer exits fzf or asks
  `y`+Enter. One keystroke kills the focused session and reloads the list so you
  can spam kills across ~20 sessions without UI teardown. Optional
  `FERRY_KILL_CONFIRM=1` restores single-key y/N. Rename (`ctrl-r`) also reloads
  in place.

## [2.7.1] — 2026-07-23

### Added

- **Public product documentation** under `docs/` (docs-kit frontmatter, sidebar `_meta.json`, `docs:check` / `docs:health`)
- **`docs/works-with.md`** — fleet sibling map with honest interop edges
- **Contextual fleet mentions** in feature docs where integrations are real
- **Recollection soft-nudge** for docs health (memory-atlas `atlas-recollection` + docs-kit)

See [`docs/index.md`](docs/index.md) for the documentation hub.

## [2.7.0] — 2026-07-22

### Added

- **`FERRY_WRAP`** (`auto`/`on`/`off`, default `auto`): interactive ferry hops
  run under local `grok wrap` when the Grok CLI is on PATH — Mac clipboard OSC 52
  interception + dirty TUI restore without abandoning `ferry` for raw
  `grok wrap ssh`. Orthogonal to picker AI launchers (`ctrl-g` still only sets
  the remote start command to `grok`).
- **`FERRY_TRANSPORT`** (`mosh`/`ssh`, default `mosh`): optional interactive
  ssh path for better OSC 52 with wrap when mosh would strip clipboard sequences.
- Doctor reports wrap availability and transport preference.
- Tests m17–m20 (wrap on/off, ssh transport, --list never wraps).

## [2.6.0] — 2026-07-21

### Added

- npm package `mossferry` with bins `ferry`, `mossferry`, `repo-session`
- Open-source community health files (CONTRIBUTING, CoC, SECURITY, issue/PR templates)

