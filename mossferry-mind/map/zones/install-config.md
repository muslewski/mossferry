---
type: zone
summary: "Install and packaging surface: install.sh (symlink ferry/mossferry/repo-session into ~/.local/bin, seed/migrate config), config.example FERRY_* keys (START_MENU + optional LAUNCHERS, snapshot/restore keys), package.json npm bins, VERSION."
tags: [install, config, npm, packaging]
status: active
created: 2026-07-21
updated: 2026-10-15
verifiedAt: 55a2999b
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

`config.example` documents the two snapshot/restore keys (`FERRY_STATE_DIR`,
`FERRY_RESTORE_STAGGER`); keep-count, load ceiling and resume command are fixed. The timer itself is installed by
`repo-session --snapshot-install` (systemd user units), not by `install.sh`.

Also ships `config.example.servers` (TSV declaration template for the
servers view — not YAML; zero-dep bash parse).

How mossferry gets onto a machine and how runtime knobs are documented.

- **`install.sh`** — idempotent git-checkout install: `~/.local/bin` symlinks
  (`ferry`, `mossferry`, `repo-session`), config dir, legacy MOSHI→FERRY
  migration, seed `config` only if absent; TTY chrome via green-ui.
  **Exit honesty:** `mkdir` / `ln` / `cp` failures print `install: …` and
  exit nonzero — never report success after a failed step (tested:
  `mkdir failure exits nonzero`).
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
- `config.example` documents `REPO_SESSION_TMUXBIN` as the escape hatch for hosts
  where tmux is not at `/usr/bin/tmux` (macOS Homebrew: `/opt/homebrew/bin/tmux`).
  Commented-out entries only — this file is copied to `~/.config/mossferry/config`.
  See [[2026-07-30-macos-bash32-portability]].
- `install.sh` symlinks `repo-session` onto the laptop with **no OS branch**, so a
  laptop-only Mac gets a binary that needs host-side tools. That is why the tmux
  preflight has to be actionable rather than a raw ENOENT.

## Lineage

README Install / Configuration / Migration sections + file headers on
2026-07-21 atlas-seed pass.
