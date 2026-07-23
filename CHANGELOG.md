# Changelog

All notable changes to mossferry are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]


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

