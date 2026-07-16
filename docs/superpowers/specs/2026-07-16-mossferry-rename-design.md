# mossferry rename — design spec

**Date:** 2026-07-16
**Status:** approved
**Why:** "moshi" collides hard (Kyutai Moshi speech model ★10k+ owning PyPI/crates; getmoshi.app — a mobile SSH/mosh terminal in the same space). Research verified **mossferry** is CLEAN on npm, crates.io, PyPI, Homebrew, AUR, and GitHub.

## The brand

**mossferry** — the green ferry between your machines. *Moss* carries the green identity and the mosh/moshi phonetics; *ferry* is the job: carrying you across to your remote tmux sessions. Identity color: green. Short daily command: **`ferry`**.

## Decisions

| Decision | Choice |
|---|---|
| Binary | `bin/moshi` → `bin/mossferry` (git mv, history preserved) |
| Commands installed | `mossferry`, `ferry` (both symlink to the same binary), `repo-session` |
| `moshi` command | removed at install (full rename, no legacy alias — user decision) |
| `bin/repo-session` | keeps its name (internal component, invoked only by mossferry) |
| Config | `~/.config/mossferry/config`; env/key prefix `MOSHI_*` → `FERRY_*` |
| Config migration | install.sh: if old `~/.config/moshi/config` exists and new one doesn't, transform prefixes into the new path and rename the old file to `config.migrated` |
| Version | `2.0.0` (breaking: command + env prefix) |
| Messages | client messages prefix `mossferry:`; hints say `ferry` (e.g. "run 'ferry <host>' to browse all sessions", "run 'ferry update'"); `repo-session:` prefix stays for the remote brain |
| README | full rebrand: green ferry story, name-origin section, usage tables around `ferry`, open-sourcing one-liner kept |
| Historical docs | `docs/` specs/plans keep saying moshi — they are history, not lies |
| Repo dirs | `~/Repositories/moshi` → `~/Repositories/mossferry` on both machines (advisor migration; Mac re-points its git remote, no re-clone) |
| Internal test hooks | `REPO_SESSION_LIB`, `REPO_SESSION_TMUXBIN`, `FAKE_*` unchanged (not user-facing) |

## Acceptance

- `git grep -iE '\bmoshi\b' -- bin tests install.sh config.example README.md` → empty.
- Full test suite green with names/prefixes updated; `--client-version` assertions read VERSION dynamically (2.0.0).
- After migration: `ferry --help`, `ferry <host> --list`, `ferry doctor`, `ferry update`, typo error, grid driver all work; `moshi` prints command-not-found.
- Mac `ghostty-grid --help` composition examples updated moshi → ferry (outside repo, advisor migration step, user approved).
