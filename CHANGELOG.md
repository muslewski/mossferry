# Changelog

All notable changes to mossferry are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]


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

