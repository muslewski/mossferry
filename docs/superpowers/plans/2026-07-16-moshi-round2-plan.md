# moshi Round 2 Implementation Plan

> **For agentic workers:** Executed via LLM armory (`armory grok-high`) — two concurrent file-disjoint Grok 4.5 children. Spec: `docs/superpowers/specs/2026-07-16-moshi-round2-design.md` (requirements authority, read fully). Round-1 Global Constraints still bind: `docs/superpowers/plans/2026-07-16-moshi-refactor-plan.md` §Global Constraints.

**Goal:** Picker kill/rename keybinds, locally-visible pre-tmux errors via `--validate`, and a hidden-window display rule that stops `_curtain` polluting names and previews.

**Additional global constraints for this round:**
- Existing tests t1–t12 / m1–m9 keep passing with assertions unmodified (stubs may be extended, never weakened). Exception: t8's row-format assertion may be updated for the new trailing preview-target field — that is the only sanctioned assertion change.
- New config key `MOSHI_HIDDEN_WINDOW_GLOB` default `_*` (env > file > default, like all keys).
- Interactive prompts (kill confirm, rename input) read from `/dev/tty`, never stdin (stdin may be the fzf pipe).
- VERSION stays `1.0.0` during children's work; advisor bumps to `1.1.0` at merge.

## File ownership (two concurrent children)

| Child | Files |
|---|---|
| **A: repo-session** (worktree `moshi-r2-repo-session`) | `bin/repo-session`, `tests/fake-tmux`, `tests/test-repo-session.sh`, `config.example` |
| **B: moshi client** (worktree `moshi-r2-client`) | `bin/moshi`, `tests/fake-bin/ssh`, `tests/test-moshi.sh`, `README.md` |

Interface between them (contract, not code): `repo-session --validate <repo>` → exit 0 silent when `$MOSHI_REPO_BASE/<repo>` is a directory; else stderr `repo-session: no repo '<repo>' under <base> — pick one below, or run 'moshi <host>' to browse all sessions` + indented repo list, exit 1; never touches tmux.

---

### Task A: repo-session — validate mode, hidden-window rule, picker keybinds

**Behavior contract (binding, on top of spec §Behavior):**
1. `--validate <repo>` parse + dispatch FIRST (before help/list/resume), no tmux calls on either path. Missing arg → usage error, exit 1.
2. `build_session_rows`: rows become `<session>\t<display_window_name>\t<N>w\t<attached|detached>\t<cmd>\t<preview_target>` where display window = active window unless its name matches `MOSHI_HIDDEN_WINDOW_GLOB` (bash `[[ name == $glob ]]`), in which case the first non-matching window (by index) supplies name + preview target; all-matching → active window as-is. `preview_target` = `<session>:<window_index>`.
3. fzf picker: preview command targets the row's preview_target field; `--expect=ctrl-x,ctrl-r`; `--header` documents the keys. Picker runs in a loop: kill (confirmed `y` on /dev/tty → `kill-session -t =<name>`), rename (non-empty name from /dev/tty → `rename-session -t =<name> <new>`), action-on-new-row, and declined confirm all reload; Enter attaches; cancel exits 130. Empty rename input → reload without renaming.
4. Testability: expose `validate_repo`, `build_session_rows`, `picker_kill <name>` (no confirm — confirm lives in the interactive wrapper), `picker_rename <old> <new>` via `REPO_SESSION_LIB=1`.
5. `config.example`: add commented `#MOSHI_HIDDEN_WINDOW_GLOB="_*"` line with a one-line comment (display rule: skip hidden windows in picker names/previews).

**Tests (add to tests/test-repo-session.sh; fake-tmux extended to log kill-session/rename-session and to serve per-window name lists via a new env `FAKE_TMUX_WINDOWS` — format `session:idx:name` lines):**
| # | Act | Assert |
|---|---|---|
| t13 | `repo-session --validate goodrepo` (dir exists) | exit 0, no output, no tmux calls in log |
| t14 | `repo-session --validate nope` | exit 1, stderr has `no repo 'nope'` + repo list, no tmux calls |
| t15 | LIB: `build_session_rows` with session whose active window is `_curtain` and second window `Syndcast Backlog` | row shows `Syndcast Backlog`, preview_target = that window's `session:index` |
| t16 | LIB: same but ALL windows hidden | active window name kept as-is |
| t17 | LIB: `MOSHI_HIDDEN_WINDOW_GLOB="zzz*"` env override | `_curtain` displayed (glob respected) |
| t18 | LIB: `picker_kill s1` | fake log has `kill-session -t =s1` |
| t19 | LIB: `picker_rename s1 newname` | fake log has `rename-session -t =s1 newname` |
| t8 (update) | existing row test | passes with 6-field format |

Steps: extend fake-tmux → write failing t13–t19 (+t8 update) → implement → green (`bash tests/test-repo-session.sh` then `bash tests/run.sh`) → commit per milestone (validate, hidden-rule, keybinds).

---

### Task B: moshi client — pre-validation + docs

**Behavior contract (binding):**
1. Detect repo token: first non-flag argument after host (same tokenization the launch path already uses). If present AND the invocation will launch mosh (i.e. not `--list`, not `--help`, not `update`/`doctor`): run `ssh <host> <MOSHI_REMOTE_BIN> --client-version <v> --validate <repo>` first. Exit 0 → proceed to mosh exactly as today (unchanged argv). Nonzero → relay the captured validation output to stderr, exit 1, never launch mosh.
2. Help text: add one line for the picker keys (`enter=attach · ctrl-x=kill · ctrl-r=rename`) and one for `--validate` being internal/automatic.
3. `README.md`: usage section gains the keybind line; configuration section gains `MOSHI_HIDDEN_WINDOW_GLOB`; a short "Errors are local" note explains pre-validation. No other README changes.

**Tests (add to tests/test-moshi.sh; fake ssh stub extended: when args contain `--validate`, exit per `FAKE_SSH_VALIDATE_EXIT` (default 0), printing `no repo 'X'` to stderr when nonzero):**
| # | Act | Assert |
|---|---|---|
| m10 | `FAKE_SSH_VALIDATE_EXIT=1 moshi h typoo` | exit 1; stderr contains `no repo`; log has ssh `--validate` line and NO mosh line |
| m11 | `moshi h goodrepo --primary` (validate exit 0) | log shows ssh `--validate` line THEN mosh line with unchanged argv (m1-style assertions) |
| m12 | `moshi h --list` | no `--validate` line in log (skip rule) |
| m13 | `moshi h` (bare picker) | no `--validate` line (no repo to validate) |

Steps: extend stub → failing m10–m13 → implement → green (`bash tests/test-moshi.sh`) → commit per milestone (validate call, help, README).

---

## Advisor gate (after both receipts)
- Verify each worktree: child A `bash tests/test-repo-session.sh`; child B `bash tests/test-moshi.sh`; both `bash -n`, personal-path grep empty, diff scope = owned files only.
- Merge `--no-ff` sequentially, `bash tests/run.sh` green on main after each.
- Bump `VERSION` to `1.1.0`, commit, `moshi update` on the Mac (twice if the running binary predates a fix — bootstrap rule).
- Live checks: `moshi manjaro-remote typoo` shows the error locally; picker shows Claude labels instead of `_curtain` with real-content previews; ctrl-x/ctrl-r work; grid driver unchanged.
