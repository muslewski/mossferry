# Plan 12: Add a root CLAUDE.md distilling the codebase invariants into an executor contract

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 88cd1f4..HEAD -- CLAUDE.md`
> The in-scope file `CLAUDE.md` does not exist yet, so this diff is normally
> empty — that is expected. The REAL drift risk here is the *source excerpts*
> quoted in "Current state": this whole file's job is to describe those lines
> accurately, so before writing, spot-check each cited `file:line` against the
> live code. On any mismatch, treat it as a STOP condition (see below) — do NOT
> document a claim that no longer matches the code.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

This repo is organized around four hard invariants (portability targets, the
`set -u`/no-`set -e` idiom, the non-TTY byte-stable token law, and the deliberate
two-script duplication). Those invariants live scattered across inline comments,
the README, and the missing-lib fallback blocks — there is no single contract
file. Every new agent editing the repo re-derives them from scratch or silently
violates one, and because the tests *enforce* the invariants, a violating change
fails **opaquely** (a byte-diff assertion, not a clear "you broke the token law"
message). A concise root `CLAUDE.md` gives any agent (this session's model or a
cheaper one with zero context) the contract up front, so violations are caught in
the head instead of in a confusing test failure. This is pure documentation — one
new file, no source logic changes, so it is safe and high-leverage for an
agent-driven repo.

## Current state

There is **no** `CLAUDE.md` or `AGENTS.md` at the repo root (verified: `ls
CLAUDE.md AGENTS.md` → none). `plans/` exists but is empty. The invariants this
plan documents are all live in the code today; the excerpts below are the exact
current lines (verified at commit `88cd1f4`). Quote/summarize these accurately —
do not invent.

Files and their roles:

- `bin/mossferry` — LOCAL client (config, mosh/ssh launch, `doctor`, `update`,
  `--help`). Also symlinked as `ferry`.
- `bin/repo-session` — REMOTE brain (fzf/numbered picker, create/attach, atomic
  grid claim, all tmux logic).
- `lib/green-ui.sh` — vendored TTY chrome kit.
- `install.sh` — symlink installer; links `bin/*` into `~/.local/bin`, seeds config.

### Excerpts (exact, at commit 88cd1f4)

**`set -u` on, `set -e` off** — `bin/mossferry:4` and `bin/repo-session:17` are
each `set -u`. Neither file contains `set -e` (the only nearby match is a comment
at `bin/mossferry:312`: `# Local pull (no set -e; branch may lack upstream mid-development).`).

**Array-guard idiom** — `bin/repo-session:199`:
```
for k in "${LAUNCHER_KEYS[@]+"${LAUNCHER_KEYS[@]}"}"; do
```

**Linux-by-design primitives in repo-session** — `mapfile` at `bin/repo-session:367`:
```
mapfile -t names < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
```
and util-linux `flock` at `bin/repo-session:476` / `bin/repo-session:481`:
```
  flock 9
...
  flock -u 9
```

**Doctor token emitter** — `bin/mossferry:431-455` (non-TTY prints the bare token):
```
  # Emit one check line. kind = ok|FAIL|info. Non-TTY: exact tokens. TTY: glyph + line.
  _doc_emit() {
    local kind=$1
    shift
    local msg="$*"
    checks=$((checks + 1))
    if (( chrome )); then
      case "$kind" in
        ok)
          printf '%s%s%s ok %s\n' "${UI_G-}" "${UI_OK-OK}" "${UI_Z-}" "$msg"
          ;;
        FAIL)
          printf '%s%s%s FAIL %s\n' "${UI_R-}" "${UI_ERR-XX}" "${UI_Z-}" "$msg"
          ;;
        info)
          printf '%sinfo %s%s\n' "${UI_D-}" "$msg" "${UI_Z-}"
          ;;
        *)
          printf '%s %s\n' "$kind" "$msg"
          ;;
      esac
    else
      printf '%s %s\n' "$kind" "$msg"
    fi
  }
```

**Update version line** — `bin/mossferry:397-398` (printed on stdout, always):
```
  # Parse-token law: non-TTY (and always) print the slash form on stdout.
  printf 'local %s / remote %s\n' "$v_local" "$v_remote"
```

**`repo-session: no repo` error** — `bin/repo-session:315-317`:
```
  if [[ ! -d "$dir" ]]; then
    # Exact first-line token (tests + client pre-validate assert this).
    echo "repo-session: no repo '${r}' under ${FERRY_REPO_BASE} — pick one below, or run 'ferry <host>' to browse all sessions" >&2
```

**Client error prefix** — `bin/mossferry:101-108` (non-TTY plain `mossferry:` prefix):
```
# Client error line: always `mossferry:` prefix; red ✗ when TTY.
_ferry_err() {
  if ui_tty 2>/dev/null; then
    printf '%s%s%s mossferry: %s\n' "${UI_R-}" "${UI_ERR-✗}" "${UI_Z-}" "$*" >&2
  else
    printf 'mossferry: %s\n' "$*" >&2
  fi
}
```

**Banner "keep in sync" comments (deliberate duplication)** — `bin/mossferry:192-197`:
```
# ASCII ferry art for --help (and shared brand with remote picker).
# Keep in sync with bin/repo-session (deliberate duplication — both scripts stay self-contained).
# Keep in sync with bin/repo-session (deliberate duplication — both scripts stay self-contained).
# Optional arg = available display columns; default COLUMNS / tput / 80.
# Tiers: off→nothing; rows<18→SMALL; width≥52→WIDE; width≥24→MEDIUM; else SMALL.
ferry_banner() {
```
and `bin/repo-session:215-219`:
```
# ASCII ferry art for picker header / --help / no-fzf menu.
# Keep in sync with bin/mossferry (deliberate duplication — both scripts stay self-contained).
# Optional arg = available display columns; default COLUMNS / tput / 80.
# Tiers: off→nothing; rows<18→SMALL; width≥52→WIDE; width≥24→MEDIUM; else SMALL.
ferry_banner() {
```
(Note: `bin/mossferry` lines 193 and 194 are an identical duplicated comment line
in the live source. This is a pre-existing cosmetic quirk — it is OUT OF SCOPE
for this plan; do not "fix" it. Describe the duplication invariant, not this typo.)

**Missing-lib fallback** — `bin/mossferry:88-97` loads the kit and falls back:
```
_ferry_load_ui() {
  local kit="${REPO_ROOT}/lib/green-ui.sh"
  if [[ -r "$kit" ]]; then
    # shellcheck source=lib/green-ui.sh
    source "$kit" || _ferry_ui_fallbacks
  else
    _ferry_ui_fallbacks
  fi
  ui_init
}
```
The fallbacks themselves are `_ferry_ui_fallbacks()` at `bin/mossferry:37-86`.

**`FERRY_LIB=1` library-source guard** — `bin/mossferry:647-654`:
```
if [[ "${FERRY_LIB:-}" == "1" ]]; then
  # Sourced as a library: expose load_config / own_version / usage / main.
  return 0 2>/dev/null || true
else
  main "$@"
  exit $?
fi
```

### Test-harness facts (verified)

- `tests/run.sh` runs every `tests/test-*.sh`, nonzero exit on any failure.
- `tests/test-repo-session.sh:11-31` — `ok()`/`fail()` helpers and `setup()`
  (temp `HOME`, temp `FERRY_REPO_BASE`, `FAKE_TMUX_LOG`, sets
  `REPO_SESSION_TMUXBIN="$FAKE"` where `FAKE="$ROOT/tests/fake-tmux"`).
- **t8** (`tests/test-repo-session.sh:157-182`) unit-tests `build_session_rows`
  via `export REPO_SESSION_LIB=1; source "$RS"; build_session_rows`, then asserts
  `fields -eq 6` and field 6 (`cut -f6`) equals `alpha:0` (the `<name>:0`
  preview). This is the "6-field row" invariant.
- **t13** (`tests/test-repo-session.sh:254-268`) asserts `--validate goodrepo` →
  `rc -eq 0`, empty stdout+stderr (`-z "$out"`), and empty tmux log (`-z "$log"`)
  — i.e. silent success, no tmux calls.
- Integration env for repo-session: `FAKE_TMUX_SESSIONS` (newline names),
  `FAKE_TMUX_META` (`name|window|Nw attached|detached cmd`), `FAKE_TMUX_WINDOWS`
  (`session:idx:name`), `FAKE_TMUX_LOG` (captures argv), `FERRY_NO_FZF=1` forces
  the numbered-menu path. See `setup()` and `t8`/`t13`.
- Client tests (`tests/test-mossferry.sh:14-56`) run `bin/mossferry` as a
  **subprocess** with `PATH="${FAKE_BIN}:${PATH}"` where
  `FAKE_BIN="${ROOT}/tests/fake-bin"` (fake `ssh`, `mosh` stubs live there), and
  `FAKE_NET_LOG` captures every net call. **Correction to any brief you were
  handed**: the fake stubs are at `tests/fake-bin/ssh` and `tests/fake-bin/mosh`
  (NOT `tests/ssh` / `tests/mosh`), and `test-mossferry.sh` does not currently
  exercise `FERRY_LIB=1` sourcing — that guard exists in `bin/mossferry:647` as an
  available mechanism. Document these accurately, per the excerpts above.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Confirm no existing file | `ls CLAUDE.md 2>/dev/null; echo rc=$?` | prints `rc=` non-zero (file absent) before you create it |
| Full suite | `bash tests/run.sh` | exit 0, no `FAIL ` lines |
| Markdown lint (optional) | `test -s CLAUDE.md && echo present` | prints `present` |
| Spot-check an excerpt | `sed -n '397,398p' bin/mossferry` | matches the update-line excerpt above |

(No build/typecheck exists — this is a bash repo. `bash tests/run.sh` is the only
gate, and it must stay green because no source is being changed.)

## Scope

**In scope** (the only file you may create):
- `CLAUDE.md` (new, at the repo root)

**Out of scope** (do NOT touch, even though they are related):
- `bin/mossferry`, `bin/repo-session`, `lib/green-ui.sh`, `install.sh` — no source
  changes of any kind. This plan is read-only on all source.
- `README.md` and any file under `docs/` — do not edit the README Ops-screens
  table or the design/spec docs; `CLAUDE.md` is a *separate* contract file.
- The duplicated comment line at `bin/mossferry:193-194` — leave it as-is.
- `tests/*` — do not add or modify tests.

## Git workflow

- Branch: `advisor/12-claude-md` (or the repo's convention if one is evident from
  `git log`). Repo uses conventional-commit style (see `git log`, e.g.
  `chore(demo): …`).
- Single commit, message e.g. `docs: add root CLAUDE.md executor contract`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Confirm the file does not already exist

Run `ls CLAUDE.md 2>/dev/null; echo rc=$?`. If it prints `rc=0` (file already
exists), STOP and report — do not overwrite.

**Verify**: command prints a non-zero `rc=` (file absent).

### Step 2: Create `CLAUDE.md` at the repo root with the content below

Write the following **verbatim** to `CLAUDE.md`. Every `file:line` reference and
every token in it was verified against the live code at commit `88cd1f4` (see
"Current state"). Do not add, drop, or paraphrase the byte-stable tokens.

````markdown
# CLAUDE.md — mossferry executor contract

mossferry is a bash CLI that opens remote tmux sessions over mosh. This file is
the contract every agent editing this repo must honor. The tests enforce these
invariants; a violating change fails opaquely (a byte-diff assertion, not a clear
message). Read this before touching `bin/*`, `lib/*`, or `install.sh`.

## What the tool is — two scripts

- `bin/mossferry` — LOCAL client. Config load/merge, mosh/ssh launch, `doctor`,
  `update`, `--help`. Also symlinked as `ferry`.
- `bin/repo-session` — REMOTE brain. fzf/numbered picker, session create/attach,
  atomic grid claim (flock), all tmux logic.
- `lib/green-ui.sh` — vendored TTY chrome kit (color / glyphs / banner / panels).
- `install.sh` — symlink installer: links `bin/*` into `~/.local/bin` and seeds
  config. Installed paths are SYMLINKS back into the repo, so edits to `bin/*` are
  live immediately. `bin/mossferry` finds its own repo root symlink-safely via
  `_ferry_resolve_self` (never relies on GNU `readlink -f`).

## 1. Portability targets

- `bin/mossferry` must run on **bash 3.2 (stock macOS)** AND Linux. No bash-4-only
  features here (no `mapfile`, no `${x^^}`, no associative arrays).
- `bin/repo-session` is **effectively Linux-only BY DESIGN**. It uses `mapfile`
  (e.g. `bin/repo-session:367`) and util-linux `flock` (`bin/repo-session:476`,
  `:481`) deliberately. Do NOT "fix" or remove those.
- `install.sh` follows the mossferry rule (macOS 3.2 + Linux).

## 2. Shell safety idioms

- `set -u` is ON in both scripts (`bin/mossferry:4`, `bin/repo-session:17`).
  `set -e` is **OFF** — never add it.
- Under `set -u`, guard every array expansion that may be empty:
  `"${arr[@]+"${arr[@]}"}"` — see `bin/repo-session:199`. An unguarded
  `"${arr[@]}"` on an empty array is an unbound-variable crash.
- Never assume `UI_*` vars are non-empty; always default-expand: `${UI_R-}`.

## 3. THE NON-TTY BYTE-STABLE TOKEN LAW (most important)

Chrome (color, glyphs, banner, panels, wave strips) is emitted ONLY when `ui_tty`
is true. Non-TTY output (pipes / CI / tests) is byte-stable and asserted by the
suite. Any NEW user-facing line must be TTY-gated (behind `if ui_tty 2>/dev/null`)
so it never pollutes pipes. Do NOT change these existing non-TTY tokens unless a
plan explicitly updates the asserting test on purpose:

| Surface | Non-TTY token (exact) | Where | Asserted by |
|---|---|---|---|
| `doctor` check lines | bare `ok …` / `FAIL …` / `info …` | `bin/mossferry:432-455` | mossferry/ui-ops tests |
| `update` version | `local <v> / remote <v>` (stdout) | `bin/mossferry:398` | mossferry/ui-ops tests |
| repo not found | `repo-session: no repo '<r>' under <base> — …` | `bin/repo-session:317` | t1, t14 |
| session rows | 6 tab-separated fields; field 6 = `<name>:0` preview | `build_session_rows` | t8 |
| `--validate <ok>` | silent, exit 0, zero tmux calls | validate path | t13 |

Error prefixes are unified: `mossferry:` (client, `bin/mossferry:106`) and
`repo-session:` (remote). A red ✗ glyph is added only when stderr is a TTY.

## 4. Deliberate duplication — do NOT dedup

`bin/mossferry` and `bin/repo-session` each carry their OWN copy of:

- `ferry_banner()` (`bin/mossferry:197`, `bin/repo-session:219`) — the "Keep in
  sync" comments (`bin/mossferry:193`, `bin/repo-session:216`) mark this on
  purpose.
- the `_ferry_resolve_self()` path resolver (`bin/mossferry:8`, mirrored in
  `bin/repo-session`).

This is INTENTIONAL so each script stays self-contained — one runs locally, one
runs on the remote; they are never both present in one place. If you change one
banner, change the other to match. Do NOT extract a shared file.

## 5. Missing green-ui must never break the tool

`lib/green-ui.sh` is optional at runtime. `_ferry_load_ui` (`bin/mossferry:88`)
falls back to `_ferry_ui_fallbacks` (`bin/mossferry:37-86`) when the kit is
absent or unreadable. Never make core behavior depend on the kit being present,
and never assume `UI_*` are set.

## 6. How to verify (run before claiming done)

| Purpose | Command | Expected |
|---|---|---|
| Full suite | `bash tests/run.sh` | exit 0, no `FAIL ` lines |
| Syntax | `bash -n bin/mossferry && bash -n bin/repo-session && bash -n install.sh && bash -n lib/green-ui.sh` | exit 0 |
| Lint | `shellcheck bin/mossferry bin/repo-session install.sh` | clean (honor existing `# shellcheck disable=` directives) |

## 7. Test-harness mechanics

- `tests/run.sh` runs every `tests/test-*.sh`; nonzero exit on any failure.
  `ok()`/`fail()` helpers and `setup()`/`teardown()` (temp `HOME`) are at the top
  of `tests/test-repo-session.sh`.
- **Unit-test a repo-session function**: `export REPO_SESSION_LIB=1`, `source
  bin/repo-session`, call the function — e.g. `build_session_rows` (t8,
  `tests/test-repo-session.sh:164-168`).
- **Integration-test repo-session**: run it as a subprocess with
  `REPO_SESSION_TMUXBIN=tests/fake-tmux`. Drive fake tmux state via env:
  `FAKE_TMUX_SESSIONS` (newline names), `FAKE_TMUX_META`
  (`name|window|Nw attached|detached cmd`), `FAKE_TMUX_WINDOWS`
  (`session:idx:name`). `FAKE_TMUX_LOG` captures every tmux argv line.
  `FERRY_NO_FZF=1` forces the numbered-menu path. Read `tests/fake-tmux` for what
  each subcommand answers (fake `list-sessions` prints names only; `show-options`
  returns empty so every session looks claimable; `has-session` does an EXACT
  compare, not tmux prefix-matching).
- **Client (bin/mossferry) tests** (`tests/test-mossferry.sh`): run the client as
  a subprocess with `PATH` prefixed by `tests/fake-bin/` (fake `ssh`, `mosh`
  stubs) and `FAKE_NET_LOG` capturing each net call. `bin/mossferry` also supports
  `FERRY_LIB=1` sourcing (guard at `bin/mossferry:647`) to expose
  `load_config` / `own_version` / `usage` / `main` for library-style unit tests.

## Maintenance

Update THIS file whenever the byte-stable non-TTY token set changes (doctor
tokens, the update `local <v> / remote <v>` line, the `repo-session: no repo`
string, the t8 6-field row, t13 silence) or the portability targets change (the
bash 3.2 / Linux split). The table in section 3 is the canonical list — keep it in
sync with the asserting tests.
````

**Verify**: `test -s CLAUDE.md && echo present` → prints `present`.

### Step 3: Confirm the suite is still green (no source changed)

Because you changed no source, the suite must be exactly as green as before.

**Verify**: `bash tests/run.sh; echo "exit=$?"` → ends with `exit=0` and prints no
`FAIL ` lines.

### Step 4: Confirm nothing outside scope was modified

**Verify**: `git status --porcelain` → shows only `?? CLAUDE.md` (and, if you
created the branch/commit, nothing else staged from source). No `bin/`, `lib/`,
`tests/`, `README.md`, or `docs/` path may appear.

## Test plan

No new tests. This plan adds documentation only and must not alter any asserted
output. The single gate is that the existing suite stays green:

- Verification: `bash tests/run.sh` → exit 0 (unchanged from before this plan,
  since no source file is touched).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `CLAUDE.md` exists at the repo root and is non-empty (`test -s CLAUDE.md`).
- [ ] Every `file:line` reference in `CLAUDE.md` still matches the live code
      (spot-check at least: `sed -n '397,398p' bin/mossferry` shows the `local
      %s / remote %s` line; `sed -n '317p' bin/repo-session` shows the `no repo`
      line; `sed -n '4p' bin/mossferry` and `sed -n '17p' bin/repo-session` show
      `set -u`).
- [ ] `bash tests/run.sh` exits 0 with no `FAIL ` lines.
- [ ] `git status --porcelain` shows only `CLAUDE.md` added — no source file
      modified.
- [ ] `plans/README.md` status row updated (unless a reviewer maintains it).

## STOP conditions

Stop and report back (do not improvise) if:

- `CLAUDE.md` already exists at the repo root (Step 1). Do not overwrite.
- Any excerpt in "Current state" does NOT match the live code when you spot-check
  it (the codebase drifted since commit `88cd1f4`). Report the specific mismatch
  — do NOT document the outdated claim, and do NOT silently "correct" the code.
- `bash tests/run.sh` reports any `FAIL ` line. Since you changed no source, a
  failure means the tree was already red or your environment lacks a dependency
  (e.g. `flock`, `bash`); report it rather than editing source to make it pass.
- Writing an accurate invariant would require changing a source file. It would
  not — this plan is docs-only — so if you feel that pull, stop and report.

## Maintenance notes

For the human/agent who owns this after it lands:

- `CLAUDE.md` is now the canonical statement of the token law and portability
  targets. Whenever a plan intentionally changes a byte-stable non-TTY token
  (doctor `ok`/`FAIL`/`info`, the `update` slash line, the `repo-session: no repo`
  string, the t8 6-field row, or t13's silence) or the bash-3.2/Linux split, that
  plan MUST also update section 3 (or section 1) of `CLAUDE.md` in the same change
  — otherwise the contract and the tests diverge.
- A reviewer should scrutinize that no `file:line` reference in `CLAUDE.md` points
  at the wrong line after a later refactor; line numbers drift. Prefer the symbol
  names (`_doc_emit`, `build_session_rows`, `ferry_banner`, `_ferry_load_ui`) as
  the durable anchor, and treat the line numbers as hints.
- Deferred out of this plan (intentionally): no `AGENTS.md` symlink/alias is
  created, and the README Ops-screens table is left untouched. If a future task
  wants a single source of truth, consider making `AGENTS.md` a pointer to
  `CLAUDE.md` rather than duplicating the content.
