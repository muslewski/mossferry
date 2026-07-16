# moshi Refactor Implementation Plan

> **For agentic workers:** This plan is executed via the LLM armory (`armory grok-high`) per `using-llm-armory` — Grok 4.5 executor children in worktrees, native Claude monitors, Fable advisor merges. Tasks 1–3 are file-disjoint and may run as ≤3 concurrent children. Phase 2 (migration) is advisor-executed with user confirmation. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Rebuild the moshi/repo-session stack as a config-driven, open-source-ready repo where the default action is an fzf session picker and nothing ever silently attaches `main`.

**Architecture:** Two-part tool unchanged in shape — `bin/moshi` (local client, launches mosh/ssh) and `bin/repo-session` (remote brain, owns all tmux logic). Both read `~/.config/moshi/config`; installed paths are symlinks into this repo, so `git pull` is deploy.

**Tech Stack:** bash (both scripts), tmux 3.6b, mosh 1.4, fzf (remote, with menu fallback), plain-bash test harness with fake `tmux`/`mosh`/`ssh` stubs.

**Spec:** `docs/superpowers/specs/2026-07-16-moshi-refactor-design.md` (approved). The spec is the requirements authority; this plan pins contracts and tests.

## Global Constraints

- Every script: `#!/usr/bin/env bash`, `set -u`; no `set -e` in repo-session (matches baseline; deliberate exit codes).
- **No personal paths** — no literal `/home/kento` or `/Users/muslewski` anywhere; only `$HOME`-derived defaults and config keys.
- **Baseline flags preserved byte-for-byte:** `--new`, `--list|-l`, `--resume|-R [N|name]`, `--resume-closed`, `--resume-or-new`, `--claude|-c`, `--help|-h`, `-- cmd…`.
- **New surface:** `--primary|-p` and `--client-version <v>` (repo-session); `update [host]`, `doctor [host]` subcommands (moshi).
- **Default action = picker.** Nothing ever attaches or creates `main` implicitly. Typo'd repo exits 1.
- `VERSION` at repo root, initial content `1.0.0`. Each script resolves its repo root via `$(dirname "$(readlink -f "$0")")/..`.
- Config precedence: **environment > config file > built-in default.** Mechanism: snapshot pre-set `MOSHI_*` vars, source config, restore snapshot.
- Config keys (complete set): `MOSHI_REMOTE_BIN` (default `.local/bin/repo-session`), `MOSHI_REPO_BASE` (default `$HOME/Repositories`), `MOSHI_DEFAULT_CMD` (default `neofetch`), `MOSHI_DEFAULT_HOST` (no default), `MOSHI_SERVER_TIMEOUT` (default `86400`), `MOSHI_REMOTE_REPO` (default `Repositories/moshi`).
- Testability hooks: `REPO_SESSION_TMUXBIN` (exists in baseline, keep); `REPO_SESSION_LIB=1` / `MOSHI_LIB=1` — when set, the script defines its functions and `return 0` without running `main`. `MOSHI_NO_FZF=1` forces the numbered-menu fallback.
- Tests: `tests/run.sh` runs every `tests/test-*.sh`; plain bash, no framework; nonzero exit on any failure; each test prints `ok <name>` or `FAIL <name>`.
- Executor contract: commit after each green step; append progress lines to untracked `PROGRESS.md`; final line `RESULT: ok|partial|failed — commits: <n> — <summary>`.

## File Map

| Path | Owner | Responsibility |
|---|---|---|
| `bin/repo-session` | Task 1 | remote brain: picker, attach/create, claim logic, version warn |
| `tests/fake-tmux`, `tests/test-repo-session.sh` | Task 1 | tmux stub + repo-session tests |
| `bin/moshi` | Task 2 | local client: arg translation, config, mosh/ssh launch, update, doctor |
| `tests/fake-bin/mosh`, `tests/fake-bin/ssh`, `tests/test-moshi.sh` | Task 2 | client stubs + tests |
| `tests/run.sh` | Task 1 | test runner (Task 2/3 tests auto-discovered by glob) |
| `install.sh`, `config.example`, `README.md`, `tests/test-install.sh` | Task 3 | install/symlink, config template, docs |
| `VERSION`, `.gitignore` | Advisor (pre-flight) | committed before dispatch |
| `zsh/moshi.zsh` | Advisor (Phase 2) | deleted after Mac migration (baseline artifact) |

## Phase 0: Advisor pre-flight (no children)

- [ ] Commit `VERSION` (content: `1.0.0`) and `.gitignore` (content: `.claude/worktrees/` and `PROGRESS.md`) to main.
- [ ] Commit this plan to `docs/superpowers/plans/`.
- [ ] `armory --dry-run grok-high` — expect `GROK_MODEL=grok-4.5`, `GROK_EFFORT=high`.
- [ ] Repo clean (`git status --short` empty).

---

### Task 1: `bin/repo-session` v2 + test harness  (child A, worktree `moshi-repo-session-v2`)

**Files:**
- Modify: `bin/repo-session` (full rewrite; baseline is the file's current committed state)
- Create: `tests/fake-tmux`, `tests/test-repo-session.sh`, `tests/run.sh`

**Interfaces:**
- Consumes: `VERSION` at repo root (committed in Phase 0); baseline claim-block logic (preserve).
- Produces (relied on by Task 2's arg translation and Phase 2 verification):
  - CLI: `repo-session [--client-version <v>] [<repo>] [--primary|-p] [--new] [--list|-l] [--resume|-R [N|name]] [--resume-closed] [--resume-or-new] [--claude|-c] [--help|-h] [-- cmd…]`
  - Exit codes: `0` success, `1` usage/typo error, `130` picker cancelled.
  - With `REPO_SESSION_LIB=1`: sourcing defines `load_config`, `build_session_rows`, `own_version`, `main` and returns 0.
  - `build_session_rows [repo]`: one line per live session (scoped to repo when given):
    `<session>\t<window_name>\t<N>w\t<attached|detached>\t<current_command>` (tab-separated; field 1 must be the bare session name — fzf preview and attach both consume `{1}`).

**Behavior contract (binding):**
1. **Arg parse** = baseline parser plus: `--primary|-p` → `primary=1`; `--client-version` → consume next token into `client_version`; unknown `-*` → `repo-session: ignoring unknown flag '<flag>'` on stderr, continue (baseline ignored silently — warning is the upgrade).
2. **Config:** `load_config` sources `~/.config/moshi/config` if readable, with env-over-file precedence per Global Constraints. Uses `MOSHI_REPO_BASE`, `MOSHI_DEFAULT_CMD`. `$base` and the `${startcmd:-neofetch}` defaults in the baseline become `$MOSHI_REPO_BASE` / `${startcmd:-$MOSHI_DEFAULT_CMD}`.
3. **Version:** `own_version` reads `<repo-root>/VERSION`, prints `unknown` if missing. If `client_version` set, non-empty, and ≠ own: stderr `moshi: client <a> / remote <b> — run 'moshi update'`. Absent flag → silent (old clients mid-migration).
4. **Typo:** repo given but `$MOSHI_REPO_BASE/<repo>` not a directory → stderr `repo-session: no repo '<repo>' under <base> — pick one below, or run 'moshi <host>' to browse all sessions` + one repo per line indented; `exit 1`. No tmux invocation on this path.
5. **Default action (no mode flags):** the picker — global when no repo, scoped when repo given. **Zero-session fast path:** repo given, no live sessions → print `no live sessions for '<repo>' — created primary` and create+attach primary directly (identical tmux calls to `--primary`-when-missing).
6. **Picker:** rows = `build_session_rows` + final literal row `➕ new session…`. With fzf (`command -v fzf` and `MOSHI_NO_FZF` unset): `fzf --ansi --delimiter='\t' --preview '<TMUXBIN> capture-pane -ep -t {1}' --preview-window=right:60%`. Selecting a session → `exec attach -t <name>` (exact `=` match). Selecting new-session row → second fzf over directories of `$MOSHI_REPO_BASE` (pre-filtered to `<repo>` when given) → create (lock-guarded, honoring `--claude`/`-- cmd…`) + attach. fzf cancel → `exit 130`. Without fzf: numbered menu (sessions, `n) new session…`, `q) quit`) reading one line from stdin; same outcomes.
7. **`--primary`:** attach `=$repo` if alive, else lock-guarded create + attach — exactly the baseline default block, relocated behind the flag.
8. **Claim block** (`--resume-closed` / `--resume-or-new`): preserve committed baseline logic verbatim — flock, `@claim_ts` TTL 25s, two-pass takeover with `attach -d` — with exactly one change: blank fallback becomes `exec "${SHELL:-/bin/bash}" -l` (the `env -u SSH_CONNECTION` workaround dies; `.bashrc` fix lands in Phase 2 before this deploys).
9. **`--resume` / `--list` / `--help`:** baseline behavior, except bare `--resume` routes to the picker (§6) instead of `choose-tree`, and help text gains `--primary` + picker-default wording.

**Steps:**
- [ ] **1. Write `tests/fake-tmux`** — records every invocation as one line of `$*` appended to `$FAKE_TMUX_LOG`; answers `list-sessions` by printing `$FAKE_TMUX_SESSIONS` (newline-separated names); `has-session -t <x>` exits 0 iff name (stripped of `=`) appears in `$FAKE_TMUX_SESSIONS`; `display-message` prints canned values from `$FAKE_TMUX_META` (format: `name|window|meta` per line); `attach`/`new-session`/`set-option`/`send-keys` just log. Must be executable.
- [ ] **2. Write `tests/test-repo-session.sh` with these cases, run it, verify every case FAILS against the committed baseline:**
    | # | Arrange + act | Assert |
    |---|---|---|
    | t1 | `FAKE_TMUX_SESSIONS=""; repo-session nope` (no such dir under a `mktemp -d` base) | exit 1; stderr contains `no repo 'nope'`; log has no `new-session` |
    | t2 | `repo-session --client-version 0.0.1 --list` (any sessions) | stderr contains `run 'moshi update'` |
    | t3 | same with `--client-version $(cat VERSION)` | stderr does NOT contain `moshi update` |
    | t4 | `repo-session myrepo --primary`, `FAKE_TMUX_SESSIONS=""`, dir exists | log contains `new-session -d -s myrepo` then `attach -t myrepo` |
    | t5 | `repo-session myrepo` (default action), no sessions, dir exists | same tmux calls as t4; stdout contains `created primary` |
    | t6 | `MOSHI_NO_FZF=1 repo-session myrepo` with sessions `myrepo`+`myrepo-2`, stdin `2\n` | log ends with attach of `myrepo-2` |
    | t7 | `MOSHI_NO_FZF=1 repo-session` global, `FAKE_TMUX_SESSIONS=""`, stdin `q\n` | exit 130; no attach in log (zero-session global picker offers only new/quit) |
    | t8 | `REPO_SESSION_LIB=1 source bin/repo-session; build_session_rows` with 2 canned sessions | two tab-separated rows, field 1 = session names |
    | t9 | `repo-session --bogus --list` | stderr contains `ignoring unknown flag '--bogus'`; list still prints |
    | t10 | `repo-session myrepo --resume-closed` with one detached session | log contains `set-option … @claim_ts` and `attach -d -t` |
    | t11 | `MOSHI_REPO_BASE=<custom> repo-session <repo-in-custom> --primary` | works against custom base (config precedence) |
    | t12 | `MOSHI_NO_FZF=1 repo-session` global, no sessions, base has dir `myrepo`, stdin `n\n1\n` | log contains `new-session -d -s myrepo` then attach (fallback new-session chain) |
- [ ] **3. Write `tests/run.sh`** — `for t in tests/test-*.sh; do bash "$t" || fail=1; done; exit ${fail:-0}`.
- [ ] **4. Implement `bin/repo-session` per the behavior contract** until `bash tests/test-repo-session.sh` is fully green. Commit at each green milestone (parser+config, typo+version, primary+fast-path, picker, claim-block port).
- [ ] **5. Run `tests/run.sh`** — expect exit 0. Commit.

---

### Task 2: `bin/moshi` client + tests  (child B, worktree `moshi-client`, concurrent with Task 1)

**Files:**
- Create: `bin/moshi`, `tests/fake-bin/mosh`, `tests/fake-bin/ssh`, `tests/test-moshi.sh`

**Interfaces:**
- Consumes: repo-session CLI contract from Task 1's Interfaces block (do not read its code; the contract above is authoritative). `VERSION` at repo root.
- Produces: `moshi` CLI per spec §6; `MOSHI_LIB=1` sourcing defines `load_config`, `own_version`, `usage`, `main`.

**Behavior contract (binding):**
1. Subcommand dispatch before anything else: `update`, `doctor`, `--help|-h` (or zero args with no `MOSHI_DEFAULT_HOST` → usage to stderr, exit 1; zero args WITH it → treat as `moshi $MOSHI_DEFAULT_HOST`).
2. Remaining argv: first token = host; `-h|--help` anywhere → local usage, exit 0, no connection. `--list|-l` anywhere → `ssh <host> <MOSHI_REMOTE_BIN> --client-version <v> <args…>` and exit. Everything else → `mosh --server="MOSH_SERVER_NETWORK_TMOUT=<MOSHI_SERVER_TIMEOUT> mosh-server" <host> -- <MOSHI_REMOTE_BIN> --client-version <v> <args…>`. Argument order after the remote bin: `--client-version <v>` first, then user args verbatim (repo, flags, `-- cmd…` untouched).
3. `update [host]`: host defaults to `MOSHI_DEFAULT_HOST` (error if neither). `git -C <repo-root> pull --ff-only`, then `ssh <host> git -C <MOSHI_REMOTE_REPO> pull --ff-only`, then print `local <v-local> / remote <v-remote>` (remote version via `ssh <host> cat <MOSHI_REMOTE_REPO>/VERSION`).
4. `doctor [host]`: one `ok/FAIL/info` line per check, exit 1 if any FAIL: config readable (info if absent — defaults in use); `ssh -G <host>` resolves; `ssh -o BatchMode=yes -o ConnectTimeout=5 <host> true`; local `mosh` binary; remote `<MOSHI_REMOTE_BIN>` executable; local vs remote VERSION match; remote `fzf` present (info-level if missing — fallback exists); remote `pgrep -c mosh-server` count (info); MagicDNS (info: whether `<host>`'s HostName is an IP).
5. Usage text: rewrite of the baseline `moshi_help` heredoc updated to the new surface — picker defaults, `--primary`, `update`, `doctor`, grid examples preserved verbatim from baseline (the `ghostty-grid -8 --` lines).
**Steps:**
- [ ] **1. Write `tests/fake-bin/mosh` and `tests/fake-bin/ssh`** — each appends `$0 $*` as one line to `$FAKE_NET_LOG` and exits 0 (ssh prints `1.0.0` when args contain `cat` and `VERSION`, to satisfy update/doctor).
- [ ] **2. Write `tests/test-moshi.sh`, verify all cases FAIL (bin/moshi absent):** every case runs with `PATH=tests/fake-bin:$PATH`, `HOME=$(mktemp -d)`, and `FAKE_NET_LOG` set.
    | # | Act | Assert |
    |---|---|---|
    | m1 | `moshi h repo --primary` | log line starts `mosh --server=MOSH_SERVER_NETWORK_TMOUT=86400 mosh-server h -- .local/bin/repo-session --client-version 1.0.0 repo --primary` |
    | m2 | `moshi h --list` | log line starts with `ssh h`; no `mosh` line |
    | m3 | config file sets `MOSHI_SERVER_TIMEOUT=111`; env `MOSHI_SERVER_TIMEOUT=222` | mosh line contains `TMOUT=222` (env wins); rerun without env → `111` |
    | m4 | config sets `MOSHI_DEFAULT_HOST=hh`; run bare `moshi` | mosh line targets `hh`, no repo arg |
    | m5 | bare `moshi`, no config | exit 1; stderr contains `usage` |
    | m6 | `moshi --help` | exit 0; stdout contains `moshi <host>`; log file empty |
    | m7 | `moshi h repo -c -- htop` | args after repo preserved in order: `repo -c -- htop` |
    | m8 | `moshi update h` | log has `git -C` line via ssh; stdout contains `local 1.0.0 / remote 1.0.0` |
- [ ] **3. Implement `bin/moshi` per contract** until green; commit per milestone (dispatch+config, launch translation, update, doctor, usage).
- [ ] **4. Run `tests/run.sh`** (runner from Task 1 if merged; else `bash tests/test-moshi.sh` alone) — green. Commit.

---

### Task 3: `install.sh`, `config.example`, `README.md`  (child C, worktree `moshi-install-docs`, concurrent)

**Files:**
- Create: `install.sh`, `config.example`, `README.md`, `tests/test-install.sh`

**Interfaces:**
- Consumes: file layout + config keys from Global Constraints (not other tasks' code).
- Produces: `install.sh` (idempotent, no args); `config.example` (verbatim below).

**Behavior contract (binding):**
1. `install.sh`: resolve repo root from its own path; `mkdir -p ~/.local/bin ~/.config/moshi`; `ln -sf <repo>/bin/moshi <repo>/bin/repo-session` into `~/.local/bin/`; copy `config.example` → `~/.config/moshi/config` **only if absent**; print one line per action; warn (stderr) if `~/.zshrc` still contains `moshi()` or a `mosh()` wrapper, or `~/.bashrc` contains a tmux auto-attach on `SSH_CONNECTION` — pointing at the migration section of README. Exit 0 even with warnings.
2. `config.example` — exact content:
    ```sh
    # moshi configuration — every key is optional; environment variables override.
    #MOSHI_REMOTE_BIN=".local/bin/repo-session"  # repo-session path, relative to remote $HOME
    #MOSHI_REPO_BASE="$HOME/Repositories"        # remote: where repos live
    #MOSHI_DEFAULT_CMD="neofetch"                # remote: startup command in fresh sessions
    #MOSHI_DEFAULT_HOST=""                       # local: host used by bare `moshi`
    #MOSHI_SERVER_TIMEOUT="86400"                # local: mosh-server self-exit after N s clientless
    #MOSHI_REMOTE_REPO="Repositories/moshi"      # remote: repo checkout, relative to remote $HOME
    ```
3. `README.md` sections, in order: what it is (two-part diagram); install (remote: clone+`./install.sh`; local: `git clone <host>:Repositories/moshi ~/Repositories/moshi && cd ~/Repositories/moshi && ./install.sh`); usage (the spec §6 command table, copied); the picker (spec §7 summary); configuration (the six keys); composition with ghostty-grid (baseline example commands verbatim); updating (`moshi update`); health (`moshi doctor`); testing (`tests/run.sh`); **Open-sourcing** — verbatim: *"moshi is built with no personal paths or hardcoded hosts. When you want to open-source it, just add a GitHub remote and push: `git remote add origin <url> && git push -u origin main`."*
**Steps:**
- [ ] **1. Write `tests/test-install.sh`, verify FAIL:** run `install.sh` with `HOME=$(mktemp -d)`: asserts symlinks exist and `readlink` targets are inside the repo; config seeded once; second run exits 0 and does not overwrite a modified config; a fake `$HOME/.zshrc` containing `moshi()` triggers the stderr warning.
- [ ] **2. Implement all three files per contract** until green. Commit per file.

---

## Phase 1 gate (advisor)

- [ ] Receipts from all three monitors say `RESULT: ok`.
- [ ] Review each `git diff main...HEAD` (contract conformance, no personal paths: `git grep -nE '/home/kento|/Users/muslewski'` must be empty).
- [ ] Merge sequentially (`git merge --no-ff`), running `tests/run.sh` on main after each merge; remove worktrees.
- [ ] Bump nothing — `VERSION` stays `1.0.0` until first post-migration change.

## Phase 2: Migration (advisor + user confirmation; each step backed up)

- [ ] **M1 (manjaro):** remove the `.bashrc` auto-attach block (the `[[ -z "$TMUX" && -n "$SSH_CONNECTION" ]] … tmux new-session -A -s main` lines, ~138–143) after `cp ~/.bashrc ~/.bashrc.bak.$(date +%s)`. Verify: `ssh manjaro-remote 'echo $TMUX'` prints empty and lands in a plain shell. **Must precede M2** — v2's blank fallback no longer clears `SSH_CONNECTION`.
- [ ] **M2 (manjaro):** `./install.sh`. Old `~/.local/bin/repo-session` file is replaced by the symlink — back it up first: `cp ~/.local/bin/repo-session ~/.local/bin/repo-session.pre-v2`. Old Mac zsh `moshi()` (no `--client-version`) keeps working against v2 by design (contract §3).
- [ ] **M3 (Mac):** `git clone manjaro-remote:Repositories/moshi ~/Repositories/moshi && ~/Repositories/moshi/install.sh`; confirm `~/.local/bin` precedes system paths in PATH.
- [ ] **M4 (Mac):** `cp ~/.zshrc ~/.zshrc.bak.$(date +%s)`, then delete the `mosh()`, `moshi()`, `moshi_help()` function blocks (currently lines 46–114 — match by content, not line numbers). `exec zsh`, verify `type moshi` → `~/.local/bin/moshi`.
- [ ] **M5 (Mac):** rewrite `~/.ssh/config` manjaro blocks to spec §8 exactly (backup first). Verify: `ssh -G manjaro-remote | grep -E 'controlmaster|serveraliveinterval'`.
- [ ] **M6 (manjaro, user confirms — kills any live mosh windows):** review `pgrep -a mosh-server`, then `pkill mosh-server` at a moment with no grid open.
- [ ] **M7 (manjaro, user confirms):** retire `~/.local/bin/repo-session.bak*` and `.prediag` (history now lives in git).
- [ ] **M8 verification checklist:** `moshi manjaro-remote` → global picker with preview; `moshi manjaro-remote syndcast` → scoped picker; `moshi manjaro-remote nope` → exit 1 + repo list; `moshi manjaro-remote syndcast --primary` → direct attach; `moshi manjaro-remote --list` → two-name list; `ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-or-new --claude` → 8 distinct sessions; `moshi update` prints matching versions; `moshi doctor manjaro-remote` all ok; new mosh-server processes carry `MOSH_SERVER_NETWORK_TMOUT` in their env (`tr '\0' '\n' </proc/<pid>/environ | grep TMOUT`).

## Deferred (explicitly not in this plan)

- GitHub publication (README documents the one-liner).
- Sound-hook stack, ghostty-grid: untouched.
- `zsh/moshi.zsh` deletion from the repo happens as part of M4's commit (baseline artifact superseded by `bin/moshi`).
