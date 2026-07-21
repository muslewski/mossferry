# Plan 15: Make the grid-claim TTL configurable via FERRY_CLAIM_TTL

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/repo-session config.example README.md tests/test-repo-session.sh tests/fake-tmux`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/13-*.md` (for the boundary integration test only — see STOP conditions; the source + docs + config-plumbing test do NOT depend on 13)
- **Category**: dx
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

The grid-claim reservation TTL is a hardcoded `ttl=25` (seconds) in the
`--resume-closed` / `--resume-or-new` claim block of `bin/repo-session`, while
every other operational knob in the tool is `FERRY_`-configurable through the
uniform env > file > default snapshot pattern in `load_config`. On a slow-starting
fleet, 25 s is not always right: too short and a still-initializing pane's session
can be stolen out from under it; too long and a crashed pane's session stays
reserved and unusable. Promoting the constant to a config key (`FERRY_CLAIM_TTL`,
default `25`) matches the project's own convention, costs almost nothing, and lets
an operator tune the claim window without editing the script. With the key unset
the default of `25` keeps behavior byte-for-byte identical, so this is a
pure-additive change.

## Current state

Files and their roles:

- `bin/repo-session` — REMOTE brain. `load_config()` (lines 114–152) snapshots
  every `FERRY_` key with the env > file > default pattern. The claim block
  (lines 981–1020, the `if (( claim ))` branch inside `main()`) hardcodes
  `ttl=25` at line 990 and uses `ttl` in the `claimable()` helper.
- `config.example` — documented, commented template of every key (11 lines).
- `README.md` — the "Configuration" section has a table of every key
  (lines 147–157).
- `tests/test-repo-session.sh` — the repo-session test file; unit-tests source
  the script with `REPO_SESSION_LIB=1` and call a function directly (see t8).
- `tests/fake-tmux` — the fake tmux driver used by integration tests. **Its
  `show-options` subcommand always returns empty and `set-option` is a no-op**
  (lines 171–177 below), so `@claim_ts` is never persisted today — this is why
  the boundary test depends on plan 13.

### Excerpt A — `load_config`, `bin/repo-session:114-152` (verbatim)

```bash
load_config() {
  # Snapshot env (env > file > default).
  local e_REMOTE_BIN e_REPO_BASE e_DEFAULT_CMD e_DEFAULT_HOST e_SERVER_TIMEOUT e_REMOTE_REPO
  local e_HIDDEN_WINDOW_GLOB e_BANNER e_LAUNCHERS
  e_REMOTE_BIN="${FERRY_REMOTE_BIN-__UNSET__}"
  e_REPO_BASE="${FERRY_REPO_BASE-__UNSET__}"
  e_DEFAULT_CMD="${FERRY_DEFAULT_CMD-__UNSET__}"
  e_DEFAULT_HOST="${FERRY_DEFAULT_HOST-__UNSET__}"
  e_SERVER_TIMEOUT="${FERRY_SERVER_TIMEOUT-__UNSET__}"
  e_REMOTE_REPO="${FERRY_REMOTE_REPO-__UNSET__}"
  e_HIDDEN_WINDOW_GLOB="${FERRY_HIDDEN_WINDOW_GLOB-__UNSET__}"
  e_BANNER="${FERRY_BANNER-__UNSET__}"
  e_LAUNCHERS="${FERRY_LAUNCHERS-__UNSET__}"

  FERRY_REMOTE_BIN=".local/bin/repo-session"
  FERRY_REPO_BASE="${HOME}/Repositories"
  FERRY_DEFAULT_CMD="neofetch"
  FERRY_DEFAULT_HOST=""
  FERRY_SERVER_TIMEOUT="86400"
  FERRY_REMOTE_REPO="Repositories/mossferry"
  FERRY_HIDDEN_WINDOW_GLOB="_*"
  FERRY_BANNER="on"
  FERRY_LAUNCHERS="ctrl-a:claude,ctrl-g:grok"

  if [[ -r "${HOME}/.config/mossferry/config" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/.config/mossferry/config"
  fi

  [[ "$e_REMOTE_BIN" != "__UNSET__" ]] && FERRY_REMOTE_BIN="$e_REMOTE_BIN"
  [[ "$e_REPO_BASE" != "__UNSET__" ]] && FERRY_REPO_BASE="$e_REPO_BASE"
  [[ "$e_DEFAULT_CMD" != "__UNSET__" ]] && FERRY_DEFAULT_CMD="$e_DEFAULT_CMD"
  [[ "$e_DEFAULT_HOST" != "__UNSET__" ]] && FERRY_DEFAULT_HOST="$e_DEFAULT_HOST"
  [[ "$e_SERVER_TIMEOUT" != "__UNSET__" ]] && FERRY_SERVER_TIMEOUT="$e_SERVER_TIMEOUT"
  [[ "$e_REMOTE_REPO" != "__UNSET__" ]] && FERRY_REMOTE_REPO="$e_REMOTE_REPO"
  [[ "$e_HIDDEN_WINDOW_GLOB" != "__UNSET__" ]] && FERRY_HIDDEN_WINDOW_GLOB="$e_HIDDEN_WINDOW_GLOB"
  [[ "$e_BANNER" != "__UNSET__" ]] && FERRY_BANNER="$e_BANNER"
  [[ "$e_LAUNCHERS" != "__UNSET__" ]] && FERRY_LAUNCHERS="$e_LAUNCHERS"
}
```

`load_config` is called once from `main()` at line 857; the claim block runs
later in the same `main()` (line 990), so `FERRY_CLAIM_TTL` is guaranteed to be
set by the time the claim block reads it.

### Excerpt B — claim block TTL, `bin/repo-session:987-994` (verbatim)

```bash
    local lockf now ttl target s n c
    lockf="${TMPDIR:-/tmp}/repo-session-$repo.claim"
    exec 9>"$lockf"; flock 9
    now=$(date +%s); ttl=25; target=""
    claimable() {   # not reserved by another pane in the last ttl seconds
      local c; c=$("$TMUXBIN" show-options -t "$1" -v -q @claim_ts 2>/dev/null)
      [[ -z "$c" ]] || (( now - c >= ttl ))
    }
```

`ttl=25` at line 990 is the **only** occurrence of the literal; `grep -n "ttl" bin/repo-session`
returns exactly lines 987, 990, 991, 993. The `--primary` (line 1023+),
`--new` (1040+) and zero-session fast-path (1060+) blocks do **not** use `ttl`
or `claimable` — do not touch them.

### Excerpt C — `config.example` FERRY_LAUNCHERS block, `config.example:9-11` (verbatim)

```
#FERRY_BANNER="on"                           # green ferry art in picker / --help (off|0 to hide)
#FERRY_LAUNCHERS="ctrl-a:claude,ctrl-g:grok" # picker AI launchers: comma-separated key:command
#                                            # (first colon splits; empty disables; ctrl-x/ctrl-r reserved)
```

Convention: one commented `#FERRY_KEY="default"` line, value aligned, then a
`# one-line explanation` whose `#` starts at column 46. The file is 11 lines,
no test asserts its bytes.

### Excerpt D — README config table, `README.md:147-159` (verbatim)

```
| Key | Default | Where |
|---|---|---|
| `FERRY_REMOTE_BIN` | `.local/bin/repo-session` | remote path of repo-session, relative to remote `$HOME` |
| `FERRY_REPO_BASE` | `$HOME/Repositories` | remote: where repos live |
| `FERRY_DEFAULT_CMD` | `neofetch` | remote: startup command in fresh sessions |
| `FERRY_DEFAULT_HOST` | _(unset)_ | local: host used by bare `ferry` |
| `FERRY_SERVER_TIMEOUT` | `86400` | local: mosh-server self-exit after N seconds clientless |
| `FERRY_REMOTE_REPO` | `Repositories/mossferry` | remote: repo checkout, relative to remote `$HOME` |
| `FERRY_HIDDEN_WINDOW_GLOB` | `_*` | remote: window-name glob skipped for picker labels/previews |
| `FERRY_BANNER` | `on` | green ferry art in picker header and `--help` (`off`/`0` hides) |
| `FERRY_LAUNCHERS` | `ctrl-a:claude,ctrl-g:grok` | remote: picker AI-launcher keys (`key:command` pairs; empty disables; `ctrl-x`/`ctrl-r` reserved) |

See `config.example` for a ready-to-edit template.
```

### Excerpt E — `tests/fake-tmux` claim handling, `tests/fake-tmux:171-177` (verbatim)

```bash
  show-options)
    # No claim markers → always empty (claimable)
    exit 0
    ;;
  attach|new-session|set-option|send-keys|new|kill-session|rename-session|capture-pane)
    exit 0
    ;;
```

This confirms the harness cannot currently persist `@claim_ts`: `set-option`
is a no-op and `show-options` returns nothing, so `claimable()` always returns
true regardless of `ttl`. The boundary integration test (Step 6, t37) therefore
requires the `@claim_ts` persistence that **plan 13** adds to this harness. The
config-plumbing unit test (Step 5, t36) does NOT need it.

### Test harness conventions (inline — the executor has not read these files)

- `tests/test-repo-session.sh` is plain bash (`set -u`), no framework. Helpers
  `ok "<id>"` / `fail "<id>" "<msg>"`, and `setup()` / `teardown()` at the top
  (lines 11–39) provision a temp `HOME` with `mkdir -p "$HOME/.config/mossferry"`,
  a temp `FERRY_REPO_BASE`, a `FAKE_TMUX_LOG`, and `REPO_SESSION_TMUXBIN="$FAKE"`.
  Every test calls `setup` first and `teardown` last.
- Unit-test a function by sourcing the script in a subshell with
  `REPO_SESSION_LIB=1` (guard that stops `main` from running) then calling the
  function. Structural exemplar (t8, lines 158–169):

  ```bash
  rows=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    build_session_rows
  )
  ```

- Tests are registered by adding the function name to the invocation list at the
  bottom of the file. The current highest test id is **t35**; the tail reads:

  ```bash
  t29; t30; t31; t32
  t33; t34; t35
  exit $FAIL
  ```

## Commands you will need

| Purpose        | Command                          | Expected on success                 |
|----------------|----------------------------------|-------------------------------------|
| Syntax check   | `bash -n bin/repo-session`       | exit 0, no output                   |
| Lint           | `shellcheck bin/repo-session`    | exit 0, no new warnings             |
| Full suite     | `bash tests/run.sh`              | exit 0, every line `ok …`, no `FAIL`|
| Literal gone   | `grep -n 'ttl=25' bin/repo-session` | no match (exit 1)                |
| Key wired      | `grep -n 'FERRY_CLAIM_TTL' bin/repo-session` | 4 matches (snapshot, default, restore, claim-block use) |

## Scope

**In scope** (the only files you may modify):
- `bin/repo-session` — `load_config` (lines 114–152) + claim block line 990.
- `config.example` — add one commented key line.
- `README.md` — add one config-table row.
- `tests/test-repo-session.sh` — add the config-plumbing test (t36) and, if
  plan 13 is landed, the boundary test (t37).

**Out of scope** (do NOT touch, even though they look related):
- The claim algorithm itself — pass ordering, the `flock`, the `@claim_ts`
  stamping, the two-pass detached/attached logic. Only the *source* of the `ttl`
  value changes.
- `bin/mossferry` (the LOCAL client) — `FERRY_CLAIM_TTL` is a remote-only concern;
  the client never runs the claim block. Do NOT add it to the client's config
  loader.
- The `--primary`, `--new`, and zero-session fast-path blocks (lines 1022–1073) —
  they do not use `ttl`.
- `tests/fake-tmux` — do NOT edit it here; its `@claim_ts` persistence is plan
  13's job. If plan 13 is not landed, skip the boundary test (see STOP conditions),
  do not add persistence yourself.
- Any change to existing non-TTY output tokens or existing test assertions.

## Git workflow

- Branch: `advisor/15-claim-ttl-config` (or the repo's branch convention if one
  is evident from `git log`).
- Recent commit style is conventional-ish with a scope, e.g.
  `chore(demo): re-record with real JetBrains Mono metrics`. Match it, e.g.
  `feat(config): add FERRY_CLAIM_TTL for the grid-claim reservation window`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Snapshot the new key in `load_config`

In `bin/repo-session`, add `e_CLAIM_TTL` to the second `local` line and add its
env snapshot next to the others.

Change line 117 from:

```bash
  local e_HIDDEN_WINDOW_GLOB e_BANNER e_LAUNCHERS
```

to:

```bash
  local e_HIDDEN_WINDOW_GLOB e_BANNER e_LAUNCHERS e_CLAIM_TTL
```

Then, immediately after line 126 (`e_LAUNCHERS="${FERRY_LAUNCHERS-__UNSET__}"`),
add:

```bash
  e_CLAIM_TTL="${FERRY_CLAIM_TTL-__UNSET__}"
```

**Verify**: `bash -n bin/repo-session` → exit 0, no output.

### Step 2: Add the default in `load_config`

Immediately after line 136 (`FERRY_LAUNCHERS="ctrl-a:claude,ctrl-g:grok"`), add:

```bash
  FERRY_CLAIM_TTL="25"
```

**Verify**: `bash -n bin/repo-session` → exit 0.

### Step 3: Add the restore in `load_config`

Immediately after line 151
(`[[ "$e_LAUNCHERS" != "__UNSET__" ]] && FERRY_LAUNCHERS="$e_LAUNCHERS"`), add:

```bash
  [[ "$e_CLAIM_TTL" != "__UNSET__" ]] && FERRY_CLAIM_TTL="$e_CLAIM_TTL"
```

After Steps 1–3, `load_config` handles `FERRY_CLAIM_TTL` with the identical
env > file > default pattern used by every other key.

**Verify**: `bash -n bin/repo-session` → exit 0, and
`grep -n 'FERRY_CLAIM_TTL' bin/repo-session` → 3 matches (snapshot, default,
restore).

### Step 4: Use the key in the claim block

Change line 990 from:

```bash
    now=$(date +%s); ttl=25; target=""
```

to:

```bash
    now=$(date +%s); ttl="${FERRY_CLAIM_TTL:-25}"; target=""
```

Notes for the executor:
- Keep the surrounding line intact — only the middle statement changes. Do NOT
  touch the `local lockf now ttl target s n c` declaration at line 987; `ttl`
  stays a local, now assigned from the config var.
- The `:-25` fallback is intentional belt-and-suspenders (set -u safety and the
  `REPO_SESSION_LIB=1` unit-source path where `load_config` may not have run).
  Keep it even though `load_config` already defaults the key.
- `claimable()` (lines 991–994) is unchanged — it still reads `ttl`.

**Verify**:
- `grep -n 'ttl=25' bin/repo-session` → no match (exit 1).
- `grep -n 'FERRY_CLAIM_TTL' bin/repo-session` → 4 matches.
- `bash -n bin/repo-session` → exit 0.
- `shellcheck bin/repo-session` → exit 0, no new warnings (honor any existing
  `# shellcheck disable=` directives already in the file).

### Step 5: Document in `config.example`

Append one commented line after the FERRY_LAUNCHERS block (after line 11). Add:

```
#FERRY_CLAIM_TTL="25"                        # remote: seconds a pane's grid-claim reserves a session
```

Match the file's alignment (the `#` explanation begins at column 46, as in the
other lines). Exact column alignment is cosmetic and not asserted by any test —
if you cannot reproduce the exact spacing, a single space before the `#` is
acceptable; the key/value/default are the load-bearing part.

**Verify**: `grep -n 'FERRY_CLAIM_TTL' config.example` → 1 match.

### Step 6: Document in the README config table

In `README.md`, add one row to the config table immediately after the
`FERRY_LAUNCHERS` row (after line 157, before the blank line and
`See \`config.example\`…`). Add:

```
| `FERRY_CLAIM_TTL` | `25` | remote: seconds a pane's grid-claim reserves a session before another pane may take it |
```

**Verify**: `grep -n 'FERRY_CLAIM_TTL' README.md` → 1 match.

### Step 7: Add the config-plumbing unit test (t36) — no dependency on plan 13

This test proves the env > file > default wiring without needing tmux state, so
it is deterministic today. Add it to `tests/test-repo-session.sh` following the
t8 `REPO_SESSION_LIB=1` source pattern and the `setup`/`teardown` +
`ok`/`fail` conventions. It asserts three cases:

1. **default** — no env, no config file → `FERRY_CLAIM_TTL == 25`.
2. **file overrides default** — write `FERRY_CLAIM_TTL=40` into
   `"$HOME/.config/mossferry/config"` → `FERRY_CLAIM_TTL == 40`.
3. **env overrides file** — with the file still saying `40`, export
   `FERRY_CLAIM_TTL=99` → `FERRY_CLAIM_TTL == 99`.

Target shape (adapt ids/spacing to the file; each `source` runs in its own
subshell so exports don't leak):

```bash
# ---- t36: FERRY_CLAIM_TTL env > file > default plumbing ----
t36() {
  setup
  local d f e
  d=$(
    unset FERRY_CLAIM_TTL 2>/dev/null || true
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"; load_config; printf '%s' "$FERRY_CLAIM_TTL"
  )
  printf 'FERRY_CLAIM_TTL=40\n' >"$HOME/.config/mossferry/config"
  f=$(
    unset FERRY_CLAIM_TTL 2>/dev/null || true
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"; load_config; printf '%s' "$FERRY_CLAIM_TTL"
  )
  e=$(
    export FERRY_CLAIM_TTL=99
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"; load_config; printf '%s' "$FERRY_CLAIM_TTL"
  )
  if [[ "$d" == "25" ]] && [[ "$f" == "40" ]] && [[ "$e" == "99" ]]; then
    ok t36
  else
    fail t36 "default=$d file=$f env=$e"
  fi
  teardown
}
```

Register it: add `t36` to the invocation list at the bottom (change the last
function line, e.g. `t33; t34; t35` → `t33; t34; t35; t36`).

**Verify**: `bash tests/run.sh` → exit 0, output includes `ok t36`, no `FAIL`.

### Step 8: Add the TTL-boundary integration test (t37) — ONLY if plan 13 is landed

**Precondition check first.** Run:
`git grep -n 'claim_ts' tests/fake-tmux`
- If `tests/fake-tmux` now **persists and reads back** `@claim_ts` (plan 13
  landed — `set-option @claim_ts` writes state and `show-options … @claim_ts`
  echoes it), write t37 as below.
- If it still matches Excerpt E (always-empty `show-options`, no-op
  `set-option`), **skip this step** and record the deferral (see STOP
  conditions + Done criteria). Do NOT add persistence to `tests/fake-tmux`
  yourself — that is plan 13's scope.

When writing t37, drive `bin/repo-session <repo> --resume-or-new` as a subprocess
(the integration pattern: `REPO_SESSION_TMUXBIN="$FAKE"`, `FERRY_NO_FZF=1`,
`FAKE_TMUX_SESSIONS`/`FAKE_TMUX_META` for state, `FAKE_TMUX_LOG` to capture
argv). Use **plan 13's** documented mechanism to seed a stored `@claim_ts` of
`now-30` on the single detached session, then assert the boundary flips:
- **default TTL (25)**: 30 ≥ 25 → session is expired/claimable → the run
  attaches (claims) that session (assert an `attach … -t <session>` line in
  `FAKE_TMUX_LOG`).
- **`FERRY_CLAIM_TTL=60`**: 30 < 60 → session is still fresh/reserved → the run
  does NOT claim it; with `--resume-or-new` it falls through to creating a fresh
  fill session instead (assert a `new-session` line, and no claim of the seeded
  session).

Read `plans/13-*.md` for the exact seeding env/API — its persistence contract is
the source of truth for how to set the stored timestamp; do not guess the env
var name. Register `t37` in the invocation list the same way as t36.

**Verify**: `bash tests/run.sh` → exit 0, output includes `ok t37`, no `FAIL`.

## Test plan

- **New tests** in `tests/test-repo-session.sh`:
  - `t36` (Step 7) — config plumbing: default `25`, file override, env-over-file.
    Deterministic, no dependency. Model after t8's `REPO_SESSION_LIB=1` source
    block.
  - `t37` (Step 8) — TTL boundary shift: same stored `@claim_ts` age yields
    claim vs. no-claim across default and `FERRY_CLAIM_TTL=60`. Depends on
    plan 13's `@claim_ts` persistence in `tests/fake-tmux`; omit if not landed.
- **Regression / byte-stability**: the full existing suite must stay green
  unchanged — with the key unset the default `25` reproduces current behavior
  exactly, and no non-TTY output token changes.
- **Verification**: `bash tests/run.sh` → exit 0, all `ok …`, including the new
  test(s), no `FAIL`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/repo-session` exits 0.
- [ ] `shellcheck bin/repo-session` exits 0 with no new warnings.
- [ ] `grep -n 'ttl=25' bin/repo-session` returns no match.
- [ ] `grep -cn 'FERRY_CLAIM_TTL' bin/repo-session` shows 4 uses (snapshot,
      default, restore, claim-block assignment).
- [ ] `grep -n 'FERRY_CLAIM_TTL' config.example` → 1 match;
      `grep -n 'FERRY_CLAIM_TTL' README.md` → 1 match.
- [ ] `bash tests/run.sh` exits 0; `ok t36` present; no `FAIL`.
- [ ] If plan 13 landed: `ok t37` present. If not: t37 omitted and the deferral
      noted in the plan status / handoff.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row for plan 15 updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts —
  especially if `ttl=25` is not on line 990, or `load_config` no longer uses the
  `e_<KEY>` / `__UNSET__` snapshot pattern. The codebase has drifted; do not
  invent an alternative wiring.
- **Plan 13 is not landed** (`tests/fake-tmux` still has the always-empty
  `show-options` from Excerpt E). This is expected and NOT a blocker for the
  source + docs + t36 config-plumbing test — land those and simply omit the t37
  boundary test, recording in your report that t37 is deferred pending plan 13's
  `@claim_ts` persistence. The claim-window behavior is then verified manually:
  reason that with the key unset `ttl` resolves to `25` (identical to before) and
  that a set `FERRY_CLAIM_TTL` flows env > file > default through `load_config`
  into the `ttl` local. Do NOT add `@claim_ts` persistence to `tests/fake-tmux`
  to force t37 — that edit belongs to plan 13.
- A verification command fails twice after a reasonable fix attempt.
- The change appears to require editing an out-of-scope file (e.g. `bin/mossferry`,
  `tests/fake-tmux`, or the claim algorithm).
- `shellcheck` flags a NEW warning you cannot resolve without changing behavior.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- **This is the reference template for promoting any future hardcoded constant to
  a `FERRY_` key.** The recipe: (1) add `e_<KEY>` to the `local` line and an
  `e_<KEY>="${FERRY_<KEY>-__UNSET__}"` snapshot, (2) add a default assignment in
  the defaults block, (3) add the `[[ "$e_<KEY>" != "__UNSET__" ]] && …` restore,
  (4) consume the var at the use site with a `:-<default>` fallback, (5) document
  in `config.example` and the README table, (6) add a config-plumbing unit test
  (like t36) plus a behavior test if the harness can model it.
- `FERRY_CLAIM_TTL` is consumed in an arithmetic context (`(( now - c >= ttl ))`
  in `claimable`). A non-integer value would raise a bash arithmetic error, the
  same as `FERRY_SERVER_TIMEOUT`; no numeric validation is added here (matching
  the other numeric keys). If future work adds config validation, this key should
  be validated as a non-negative integer.
- A reviewer should confirm the default stayed `25` (byte-stable behavior when
  unset) and that the key was NOT added to the LOCAL client `bin/mossferry`,
  which never runs the claim block.
- Deferred out of this plan: tuning the *default* value, and any change to the
  two-pass claim algorithm — out of scope by design.
