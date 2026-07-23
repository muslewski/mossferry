---
type: zone
summary: "Install and packaging surface: install.sh (symlink ferry/mossferry/repo-session into ~/.local/bin, seed/migrate config), config.example FERRY_* keys (START_MENU + optional LAUNCHERS), package.json npm bins, VERSION."
tags: [install, config, npm, packaging]
status: seeded
created: 2026-07-21
updated: 2026-07-23
verifiedAt: unverified
owns:
  routes: []
  testids: []
  globs:
    - "install.sh"
    - "config.example"
    - "package.json"
    - "VERSION"
  tools: []
depends:
  - "[[green-ui]]"
invariants: []
skills: []
related:
  - "[[client]]"
  - "[[repo-session]]"
sources: []
---

## What this is

How mossferry gets onto a machine and how runtime knobs are documented.

- **`install.sh`** — idempotent git-checkout install: `~/.local/bin` symlinks
  (`ferry`, `mossferry`, `repo-session`), config dir, legacy MOSHI→FERRY
  migration, seed `config` only if absent; TTY chrome via green-ui.
- **`config.example`** — commented `FERRY_*` template (remote bin, repo base,
  default cmd/host, mosh timeout, banner, `FERRY_START_MENU`, optional
  `FERRY_LAUNCHERS`). Defaults ship generic CLI names only; personal profiles
  belong in the user's config file.
- **`package.json`** — npm publish metadata; bins map `ferry`/`mossferry`/
  `repo-session`; `files` whitelist for the package tarball.
- **`VERSION`** — single-line version string used by client/remote and
  `ferry update` version strip.

## Anchors

Globs list the four packaging/config entry files (not the whole docs tree).
Runtime config *file* lives outside the repo (`~/.config/mossferry/config`).

## Invariants

None claimed on seed. Install contract from README:

- Symlinks point into the clone so `git pull` is deploy.
- Config seed never overwrites an existing user config.

## Lineage

README Install / Configuration / Migration sections + file headers on
2026-07-21 atlas-seed pass.
