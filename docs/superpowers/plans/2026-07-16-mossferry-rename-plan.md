# mossferry Rename Implementation Plan

> **For agentic workers:** One sequential armory child (the rename is cross-cutting — no parallel split). Spec: `docs/superpowers/specs/2026-07-16-mossferry-rename-design.md` (authority). Round-1 Global Constraints still bind (`docs/superpowers/plans/2026-07-16-moshi-refactor-plan.md`).

**Goal:** Rename the tool to mossferry (short command `ferry`), rebrand README, FERRY_* config prefix, version 2.0.0 — with the full test suite proving nothing else changed.

### Task: the rename child (worktree `mossferry-rename`)

**In scope (whole repo except docs/ and .gitignore):**
- `git mv bin/moshi bin/mossferry`; `git mv tests/test-moshi.sh tests/test-mossferry.sh`.
- All `MOSHI_*` env/config keys → `FERRY_*` (bin/mossferry, bin/repo-session, tests, config.example). Internal hooks `REPO_SESSION_LIB`, `REPO_SESSION_TMUXBIN`, `MOSHI_LIB`→`FERRY_LIB`, `MOSHI_NO_FZF`→`FERRY_NO_FZF`; `FAKE_*` unchanged.
- Config path `~/.config/moshi/config` → `~/.config/mossferry/config` in both binaries.
- Client message prefix `moshi:` → `mossferry:`; user-facing hints say `ferry` (typo hint: "run 'ferry <host>' to browse all sessions"; version drift: "run 'ferry update'"). `repo-session:` prefix unchanged.
- Usage/help heredocs rebranded (`mossferry <host> …`, note "`ferry` is the short command", grid examples use `ferry`).
- `install.sh`: symlinks `mossferry` + `ferry` + `repo-session`; removes a `~/.local/bin/moshi` symlink if it resolves into this repo; config migration per spec (transform MOSHI_→FERRY_ into new path, old file → `config.migrated`); zshrc/bashrc warnings updated to say ferry.
- `config.example`: FERRY_* keys, one-line header mentioning env > file > default.
- `README.md`: full rebrand per spec (green ferry story at top, name-origin section, install, usage table with `ferry`, picker + keybinds, configuration, updating/health, testing, open-sourcing one-liner verbatim from current README).
- `VERSION`: `2.0.0`.

**Tests:** every existing test updated mechanically (command paths, env prefixes, expected strings). `--client-version` assertions must read `$(cat VERSION)` — fix any hardcoded `1.x`. New: t20 `install`-side not needed; add m14: fake run asserts the mosh line uses `--client-version 2.0.0` (dynamic read proves VERSION wiring); i-test (test-install.sh): assert both `mossferry` and `ferry` symlinks exist and a stale `moshi` symlink into the repo is removed; config-migration case (old moshi config with MOSHI_DEFAULT_HOST → new path has FERRY_DEFAULT_HOST, old renamed `.migrated`).

**Verify:** `bash tests/run.sh` green; `bash -n` both binaries + install.sh; `git grep -iE '\bmoshi\b' -- bin tests install.sh config.example README.md` empty; `git grep -E '/home/kento|/Users/muslewski' -- bin tests install.sh config.example README.md` empty.

### Advisor migration (after merge, in order)
1. manjaro: merge --no-ff, suite green, worktree removed. Then `mv ~/Repositories/moshi ~/Repositories/mossferry` and run `~/Repositories/mossferry/install.sh` (re-points dangling symlinks, adds `ferry`, drops `moshi`, migrates config).
2. Mac: `git remote set-url origin manjaro-remote:Repositories/mossferry`, `mv ~/Repositories/moshi ~/Repositories/mossferry`, run `install.sh`.
3. Mac: update `ghostty-grid` --help example lines moshi → ferry (user approved; backup first).
4. Verify: `ferry --help`; `ferry manjaro-remote --list`; `ferry doctor manjaro-remote`; `ferry update`; `ferry manjaro-remote typoo` (local error, hint says ferry); `command -v moshi` fails; live picker row check via LIB.
5. Update Claude memory files (moshi → mossferry).
