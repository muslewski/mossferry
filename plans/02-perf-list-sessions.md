# Plan 02: Collapse build_session_rows from ~5 tmux forks per session to a single list-sessions -F

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/repo-session tests/fake-tmux tests/test-repo-session.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts below against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/01-*.md` (test safety net) — plan 01 establishes/extends
  the row-format assertions this plan must not break. If plan 01 is not yet DONE,
  this plan is still executable (the relevant assertions already exist as t8, t15,
  t16, t17, t20 in `tests/test-repo-session.sh`), but coordinate so the two plans
  do not edit `tests/test-repo-session.sh` in a way that conflicts.
- **Category**: perf
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

`build_session_rows` (the function that paints the fzf picker and the `--list`
output) forks **five** `tmux display-message -p -t <session>` processes per
session — `window_name`, `window_index`, `session_windows`, `session_attached`,
`pane_current_command` — on top of the one up-front `list-sessions`. That is
`1 + 5N` tmux processes to paint the list once, and the picker re-runs
`build_session_rows` on **every reload** (after a create, kill, rename, or the
`ctrl-r` reload key). Over mosh — where each tmux fork is a round-trip on the
remote host — this fan-out is the dominant lag between an action and the picker
reappearing. tmux resolves `#{window_name}`, `#{window_index}` and
`#{pane_current_command}` against each session's **active** window/pane inside a
single `list-sessions -F`, so all six columns can come from **one** tmux fork
(`1 + 0N` in the common case; `1 + K` where `K` is only the count of sessions
whose active window is hidden). The row output stays **byte-identical**, so no
downstream consumer changes. This plan also hardens two documented races by
adding `2>/dev/null` so a session vanishing mid-loop cannot leak
`can't find session` onto the terminal.

## Current state

Files involved:

- `bin/repo-session` — the REMOTE brain. `build_session_rows()` (lines 358–403)
  builds the picker/`--list` rows. Downstream consumers of its output are
  `print_list()` (lines 459–466, the `--list` numbered view), `run_picker()`
  numbered-menu path (line 693) and `run_picker()` fzf path (line 735). The fzf
  preview command lives at line 755.
- `tests/fake-tmux` — the stub `tmux` used by the suite. Its `list-sessions`
  branch (lines 65–71) currently prints **only** session names, ignoring `-F`.
  It must learn to answer the richer 6-field `-F` format that the new
  `build_session_rows` sends (test scaffolding — explicitly in scope). It
  already has the helpers `_lookup_meta` (lines 18–43) and
  `_active_window_index` (lines 45–63) you will reuse.
- `tests/test-repo-session.sh` — the repo-session contract suite. t8 (lines
  157–182), t15 (287–311), t16 (313–335), t17 (337–359) and t20 (401–415) assert
  the exact 6-field row shape and the hidden-window rule. A new test (t36) goes
  here, and it must be wired into the runner block (lines 826–833).

### Excerpt A — `build_session_rows` today (`bin/repo-session:358-403`)

```bash
# One line per live session (optionally scoped to <repo>):
#   <session>\t<display_window>\t<N>w\t<attached|detached>\t<cmd>\t<preview_target>
# Display window skips FERRY_HIDDEN_WINDOW_GLOB (default _*); preview_target is session:index.
build_session_rows() {
  local filter="${1:-}" s cname wins att cmd attword
  local active_name active_idx display_name preview_target glob wline widx wname found
  local -a names=()
  glob="${FERRY_HIDDEN_WINDOW_GLOB:-_*}"
  if [[ -n "$filter" ]]; then
    mapfile -t names < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
      | grep -E "^${filter}(-[0-9]+)?$" | sort -V)
  else
    mapfile -t names < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null | sort -V)
  fi
  for s in "${names[@]}"; do
    [[ -z "$s" ]] && continue
    active_name=$("$TMUXBIN" display-message -p -t "$s" '#{window_name}')
    active_idx=$("$TMUXBIN" display-message -p -t "$s" '#{window_index}')
    wins=$("$TMUXBIN" display-message -p -t "$s" '#{session_windows}')
    att=$("$TMUXBIN" display-message -p -t "$s" '#{session_attached}')
    cmd=$("$TMUXBIN" display-message -p -t "$s" '#{pane_current_command}')
    if [[ "$att" == "0" ]]; then attword="detached"; else attword="attached"; fi

    display_name="$active_name"
    preview_target="${s}:${active_idx}"
    # If active window is hidden, fall back to first non-matching window by index.
    if [[ "$active_name" == $glob ]]; then
      found=0
      while IFS= read -r wline; do
        [[ -z "$wline" ]] && continue
        widx="${wline%%:*}"
        wname="${wline#*:}"
        if [[ "$wname" != $glob ]]; then
          display_name="$wname"
          preview_target="${s}:${widx}"
          found=1
          break
        fi
      done < <("$TMUXBIN" list-windows -t "$s" -F '#{window_index}:#{window_name}' 2>/dev/null)
      # all-matching → keep active as-is (found stays 0)
      :
    fi

    printf '%s\t%s\t%sw\t%s\t%s\t%s\n' "$s" "$display_name" "$wins" "$attword" "$cmd" "$preview_target"
  done
}
```

Facts you must preserve exactly:

- **The emitted row is 6 tab-separated fields, in this order**:
  `<session>` TAB `<display_window>` TAB `<N>w` TAB `<attached|detached>` TAB
  `<cmd>` TAB `<session>:<index>`. This is asserted by t8 (`fields -eq 6`,
  `preview == "alpha:0"`) and consumed positionally by the fzf preview at line
  755 as `{6}` (field 6 = the preview target). Do NOT add, remove, or reorder a
  field.
- **`<N>w`** = `session_windows` with a literal `w` suffix (field 3).
- **`<attached|detached>`** (field 4) = `detached` when `session_attached` is `0`,
  else `attached`.
- **The hidden-window rule**: if the active window name matches the glob
  (`FERRY_HIDDEN_WINDOW_GLOB`, default `_*`), fields 2 and 6 are replaced by the
  first window (by index) whose name does NOT match the glob; if every window
  matches, the active window is kept as-is. Asserted by t15 (substitutes),
  t16 (all-hidden keeps active), t17 (glob override → no substitution).
- **`$TMUXBIN`** is the tmux binary (real `tmux`, or the test stub via
  `REPO_SESSION_TMUXBIN`). Already resolved before this function; do not touch it.

### Excerpt B — the fzf preview command (`bin/repo-session:751-756`)

```bash
    } | fzf --ansi --delimiter=$'\t' \
        --layout=reverse --header-first --cycle \
        --expect="$expect_keys" \
        --header "$header" \
        --preview "$TMUXBIN capture-pane -ep -t {6}" \
        --preview-window=right:60% \
```

`{6}` is fzf's substitution for the 6th tab-delimited field of the selected row
= the `session:index` preview target. When a session is killed while its row is
still on screen, `capture-pane` writes `can't find session` to stderr; this plan
silences it (Step 3).

### Excerpt C — the fake-tmux `list-sessions` branch today (`tests/fake-tmux:65-71`)

```bash
  list-sessions)
    if [[ -n "${FAKE_TMUX_SESSIONS:-}" ]]; then
      printf '%s\n' "$FAKE_TMUX_SESSIONS"
    fi
    exit 0
    ;;
```

It ignores `-F` entirely and prints raw names. Six call sites in
`bin/repo-session` pass `-F '#{session_name}'` and rely on getting **names
only** (lines 454, 933, 936, 951, 959, 962) — those must keep working. After
this plan, only `build_session_rows` sends a multi-field format, so the fake must
branch on the `-F` argument: emit 6 fields for the multi-field format, names
otherwise.

### Excerpt D — the fake-tmux helpers you will reuse (`tests/fake-tmux:18-63`)

```bash
_lookup_meta() {
  # sets: _win _meta _wins _attword _cmd
  ...
}

# Active window index for session: match active name in FAKE_TMUX_WINDOWS, else 0.
_active_window_index() {
  local name="$1" line sess idx wname rest
  _lookup_meta "$name"
  ...
  printf '0\n'
}
```

`_lookup_meta "$name"` sets `_win` (active window name), `_wins` (window count,
e.g. `2`), `_attword` (`attached`/`detached`), `_cmd`. `_active_window_index
"$name"` prints the active window's index (0 when `FAKE_TMUX_WINDOWS` is unset).
`_active_window_index` runs its own `_lookup_meta` in a subshell when captured
with `$(...)`, so it will not clobber the `_win`/`_wins`/`_attword`/`_cmd` you
set in the parent — call `_lookup_meta` in the parent first, then capture the
index.

### Excerpt E — the runner block (`tests/test-repo-session.sh:826-833`)

```bash
export TEST_TMPDIR_ROOT="${TMPDIR:-/tmp}"
set +e
t1; t2; t3; t4; t5; t6; t7; t8; t9; t10; t11; t12
t13; t14; t15; t16; t17; t18; t19; t20
t21; t22; t23; t24; t25
t26; t27; t28
t29; t30; t31; t32
t33; t34; t35
```

Tests are invoked by explicit name here (not auto-discovered inside the file), so
a new test function must be added to this list or it will never run. Highest
existing number is **t35**; the new test is **t36**.

### Repo conventions that apply here

- `set -u` is on, `set -e` is OFF in `bin/repo-session`. Guard array expansions
  against unbound errors: `"${arr[@]+"${arr[@]}"}"` (invariant #2).
- Non-TTY output is byte-stable and asserted. `build_session_rows` writes only
  the tab-separated data rows (no chrome), so this plan must keep every row
  **byte-identical** for the same session state.
- `bin/repo-session` is effectively Linux and already uses `mapfile` by design —
  keep using it; do not "fix" it to a portable loop.
- Tab-peeling with `${var%%$'\t'*}` / `${var#*$'\t'}` is the parsing idiom used in
  the existing hidden-window loop (`${wline%%:*}` / `${wline#*:}`). Prefer it over
  `read -r … <<<"$line"` with `IFS=$'\t'`: `read` treats tab as IFS whitespace and
  **collapses** consecutive tabs / drops empty fields, which would misalign a row
  whose `pane_current_command` or window name is empty. Peeling does not.
- `bin/repo-session` and `bin/mossferry` deliberately duplicate the banner /
  path-resolver helpers — do NOT dedup them.

## Commands you will need

| Purpose               | Command                                            | Expected on success                 |
|-----------------------|----------------------------------------------------|-------------------------------------|
| Syntax check (source) | `bash -n bin/repo-session`                         | exit 0, no output                   |
| Syntax check (fake)   | `bash -n tests/fake-tmux`                          | exit 0, no output                   |
| Syntax check (test)   | `bash -n tests/test-repo-session.sh`               | exit 0, no output                   |
| Lint                  | `shellcheck bin/repo-session`                      | exit 0, no new findings             |
| Single suite          | `bash tests/test-repo-session.sh`                  | every line `ok tN`, no `FAIL`       |
| Full suite            | `bash tests/run.sh`                                | exit 0 (all tests pass)             |

`shellcheck` is expected on PATH per the repo's stated invariants; if it is not
installed in your environment, note that and rely on `bash -n` + the suite.
Honor existing `# shellcheck disable=` directives in the files (there are three
in `bin/repo-session` at lines 16, 93, 139 — none inside `build_session_rows`).

## Suggested executor toolkit

(Optional.) Read `README.md` / the CLAUDE.md invariants only if you need context;
everything load-bearing is inlined here. No special skills are required — this is
a self-contained bash refactor verified entirely by `bash -n`, `shellcheck`, and
the test suite.

## Scope

**In scope** (the only files you may modify):

- `bin/repo-session` — **only** `build_session_rows()` (Excerpt A, lines
  358–403) and **only** the one-line `--preview` string at line 755 (Excerpt B).
  Nothing else in the file.
- `tests/fake-tmux` — **only** the `list-sessions` branch (Excerpt C, lines
  65–71). Do NOT touch `_lookup_meta`, `_active_window_index`, or any other
  subcommand branch (`display-message` etc. stay — they are still used by the
  claim logic at `bin/repo-session:997`).
- `tests/test-repo-session.sh` — add test **t36** and wire it into the runner
  block (Excerpt E). Do NOT edit any existing test body.

**Out of scope** (do NOT touch, even though they look related):

- `run_picker()` action dispatch and its key handling — that is **plan 03**. This
  plan changes only how the rows are computed, not how selections are acted on.
- Any MRU / age-based sorting of the rows — that is **plan 05**. Keep the current
  `sort -V` ordering.
- `print_list()` formatting (lines 459–466) — it consumes `build_session_rows`
  output and must not change; do not edit it.
- The six name-only `list-sessions -F '#{session_name}'` call sites (lines 454,
  933, 936, 951, 959, 962) and the `display-message` at line 997 — leave them
  byte-for-byte unchanged.
- The duplicated banner / path-resolver helpers — do NOT dedup them.
- `bin/mossferry`, `lib/green-ui.sh`, `install.sh`, `tests/run.sh`, any other
  test file.

## Git workflow

- Branch: `advisor/02-perf-list-sessions` (create off `main`; do not commit on
  `main` directly).
- Commit style is conventional commits (recent log shows `chore(demo): …`,
  `feat: …`, `merge: …`). One commit per step is fine, or one squashed commit;
  suggested final message:
  `perf(repo-session): build picker rows in one list-sessions -F (was 1+5N tmux forks)`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

Execute in this order. The order guarantees the suite is green **between** steps:
Step 1 (fake) is backward-compatible with the *old* `build_session_rows` because
the old code only ever sends `-F '#{session_name}'` (the names-only branch), so
the suite still passes after Step 1 and before Step 2.

### Step 1: Teach fake-tmux `list-sessions` to answer the 6-field `-F` format

Edit `tests/fake-tmux`. Replace the entire `list-sessions)` branch (Excerpt C,
lines 65–71) with:

```bash
  list-sessions)
    fmt=""
    while (( $# )); do
      case "$1" in
        -F) fmt="${2:-}"; shift 2 ;;
        -*) shift ;;
        *)  shift ;;
      esac
    done
    if [[ -z "${FAKE_TMUX_SESSIONS:-}" ]]; then
      exit 0
    fi
    _tab=$(printf '\t')
    if [[ "$fmt" == *"$_tab"* || "$fmt" == *'#{window_name}'* ]]; then
      # Multi-field build_session_rows format: emit six tab-separated fields,
      #   name  window  Nw  attword  cmd  name:index
      # matching bin/repo-session build_session_rows (window/pane tokens resolve
      # against each session's active window/pane).
      while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        _lookup_meta "$s"
        idx=$(_active_window_index "$s")
        printf '%s\t%s\t%sw\t%s\t%s\t%s:%s\n' "$s" "$_win" "$_wins" "$_attword" "$_cmd" "$s" "$idx"
      done <<< "$FAKE_TMUX_SESSIONS"
    else
      printf '%s\n' "$FAKE_TMUX_SESSIONS"
    fi
    exit 0
    ;;
```

Notes for correctness:

- Detection is on the `-F` argument. The names-only format `#{session_name}`
  contains no tab and no `#{window_name}`, so it takes the `else` branch and
  prints names exactly as before — keeping the six name-only call sites working.
- The multi-field format that `build_session_rows` sends (Step 2) contains real
  tab bytes, so `"$fmt" == *"$_tab"*` is true.
- `%sw` reproduces `#{session_windows}w` (e.g. `_wins=2` → `2w`). `_attword` is
  already the word (`attached`/`detached`). The final `%s:%s` builds the
  `name:index` preview target from `$s` and `$idx`.
- `_lookup_meta "$s"` runs in the parent so `$_win/$_wins/$_attword/$_cmd` are
  set for the `printf`; `idx=$(_active_window_index "$s")` captures the index in
  a subshell so it does not clobber those parent values.
- `s`, `idx`, `fmt`, `_tab` are plain (file-global) variables here — the stub is
  not a function; each are assigned before use, satisfying `set -u`.

**Verify**:
- `bash -n tests/fake-tmux` → exit 0, no output.
- `bash tests/test-repo-session.sh` → every existing line prints `ok tN`, no
  `FAIL` (the OLD `build_session_rows` still sends `-F '#{session_name}'`, so it
  hits the names-only branch — nothing regresses yet).

### Step 2: Rewrite `build_session_rows` to one `list-sessions -F`

Edit `bin/repo-session`. Replace the whole function body from the comment header
through the closing brace (Excerpt A, lines 358–403) with:

```bash
# One line per live session (optionally scoped to <repo>):
#   <session>\t<display_window>\t<N>w\t<attached|detached>\t<cmd>\t<preview_target>
# Display window skips FERRY_HIDDEN_WINDOW_GLOB (default _*); preview_target is session:index.
# All six fields come from a SINGLE `list-sessions -F`: tmux resolves the
# window/pane tokens against each session's active window/pane (same values the
# old per-session display-message calls fetched). Only sessions whose active
# window is hidden pay for a second fork (list-windows) to substitute fields 2/6.
build_session_rows() {
  local filter="${1:-}" line s dwin wins att cmd ptgt
  local glob wline widx wname r1 r2 r3 r4 fmt
  local -a rawrows=()
  glob="${FERRY_HIDDEN_WINDOW_GLOB:-_*}"
  fmt=$'#{session_name}\t#{window_name}\t#{session_windows}w\t#{?session_attached,attached,detached}\t#{pane_current_command}\t#{session_name}:#{window_index}'
  if [[ -n "$filter" ]]; then
    mapfile -t rawrows < <("$TMUXBIN" list-sessions -F "$fmt" 2>/dev/null \
      | grep -E "^${filter}(-[0-9]+)?"$'\t' | sort -V)
  else
    mapfile -t rawrows < <("$TMUXBIN" list-sessions -F "$fmt" 2>/dev/null | sort -V)
  fi
  for line in "${rawrows[@]+"${rawrows[@]}"}"; do
    [[ -z "$line" ]] && continue
    s="${line%%$'\t'*}"
    [[ -z "$s" ]] && continue          # session vanished mid-snapshot → skip row
    r1="${line#*$'\t'}"; dwin="${r1%%$'\t'*}"
    # Common case: active window not hidden → the tmux line is already the final
    # 6-field row; emit it unchanged (byte-identical to the old printf).
    if [[ "$dwin" != $glob ]]; then
      printf '%s\n' "$line"
      continue
    fi
    # Uncommon case: active window matches the hidden glob. Peel the remaining
    # fields and substitute the first non-hidden window (by index). Only this
    # branch spends a second tmux fork, and only for hidden-active sessions.
    r2="${r1#*$'\t'}"; wins="${r2%%$'\t'*}"
    r3="${r2#*$'\t'}"; att="${r3%%$'\t'*}"
    r4="${r3#*$'\t'}"; cmd="${r4%%$'\t'*}"
    ptgt="${r4#*$'\t'}"
    while IFS= read -r wline; do
      [[ -z "$wline" ]] && continue
      widx="${wline%%:*}"
      wname="${wline#*:}"
      if [[ "$wname" != $glob ]]; then
        dwin="$wname"
        ptgt="${s}:${widx}"
        break
      fi
    done < <("$TMUXBIN" list-windows -t "$s" -F '#{window_index}:#{window_name}' 2>/dev/null)
    # all-matching → keep active display/preview as-is
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$dwin" "$wins" "$att" "$cmd" "$ptgt"
  done
}
```

Why each piece is correct (do not deviate):

- **Single format string.** `fmt` uses `$'…\t…'` so the tabs are real bytes tmux
  passes through, and the tokens map 1:1 to the old columns:
  - `#{session_name}` → field 1
  - `#{window_name}` → field 2 (active window's name)
  - `#{session_windows}w` → field 3 (`<N>w`; the `w` is a literal in the format)
  - `#{?session_attached,attached,detached}` → field 4 (tmux conditional: nonzero
    `session_attached` → `attached`, else `detached` — identical to the old
    `if [[ "$att" == "0" ]]`)
  - `#{pane_current_command}` → field 5 (active pane's command)
  - `#{session_name}:#{window_index}` → field 6 (preview target)
- **Filter grep anchors on the tab, not `$`.** The old grep `^${filter}(-[0-9]+)?$`
  anchored to end-of-line, which worked when the line was just the name. Now the
  line has five more fields, so anchor to the field-1/field-2 boundary instead:
  `"^${filter}(-[0-9]+)?"$'\t'`. (The pre-existing behavior that a `.` in a repo
  name is a regex metachar is unchanged — do not "fix" it here.)
- **Common case emits `$line` verbatim.** Because the tmux `-F` output already IS
  the final 6-field row, `printf '%s\n' "$line"` is byte-identical to the old
  reconstructing `printf`. This is what keeps the output stable.
- **Tab-peel, not `read`.** Peeling with `%%$'\t'*` / `#*$'\t'` handles empty
  fields; `IFS=$'\t' read` would collapse them (see conventions above).
- **Hidden branch reuses the exact old loop** over
  `list-windows -F '#{window_index}:#{window_name}'`, with the same
  keep-active-when-all-hidden fallthrough. In the hidden branch, `wins` already
  carries the `w` suffix (it is field 3, `2w`), so the final `printf` uses plain
  `%s` for it (NOT `%sw`).
- **`set -u` safety.** `rawrows` is declared (`local -a rawrows=()`) and iterated
  with the guarded expansion `"${rawrows[@]+"${rawrows[@]}"}"`.

**Verify**:
- `bash -n bin/repo-session` → exit 0, no output.
- `shellcheck bin/repo-session` → exit 0, no new findings.
- `bash tests/test-repo-session.sh` → `ok t8`, `ok t15`, `ok t16`, `ok t17`,
  `ok t20` all present, no `FAIL`.

### Step 3: Silence `capture-pane` in the fzf preview

Edit `bin/repo-session` line 755. Change:

```bash
        --preview "$TMUXBIN capture-pane -ep -t {6}" \
```

to:

```bash
        --preview "$TMUXBIN capture-pane -ep -t {6} 2>/dev/null" \
```

This appends `2>/dev/null` inside the preview command string fzf runs, so a
session killed while its row is still displayed does not flash
`can't find session` in the preview pane. No test drives the fzf preview (the
suite runs the no-fzf path or does not invoke the preview), so this is
behavior-only and asserted by nothing — keep the rest of the fzf block
byte-for-byte unchanged.

**Verify**:
- `bash -n bin/repo-session` → exit 0, no output.
- `grep -n 'capture-pane -ep -t {6} 2>/dev/null' bin/repo-session` → exactly one
  match (line ~755).

### Step 4: Add test t36 — one `list-sessions`, zero per-session `display-message`

Edit `tests/test-repo-session.sh`. Insert this new test function **after** the
t35 function (which ends with its closing `}` near line 681) and **before** the
runner block that starts with `export TEST_TMPDIR_ROOT=…` (line 826):

```bash
# ---- t36: build_session_rows uses ONE list-sessions, no per-session display-message ----
t36() {
  setup
  local log ls_count dm_count
  export FAKE_TMUX_SESSIONS=$'alpha\nbeta\ngamma'
  export FAKE_TMUX_META=$'alpha|Awin|2w attached claude\nbeta|Bwin|1w detached bash\ngamma|Cwin|3w detached vim'
  export REPO_SESSION_TMUXBIN="$FAKE"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    build_session_rows >/dev/null
  )
  log=$(cat "$FAKE_TMUX_LOG")
  ls_count=$(grep -c '^list-sessions' <<<"$log" || true)
  dm_count=$(grep -c '^display-message' <<<"$log" || true)
  if [[ "$ls_count" -eq 1 ]] && [[ "$dm_count" -eq 0 ]]; then
    ok t36
  else
    fail t36 "ls=$ls_count dm=$dm_count log=[$log]"
  fi
  teardown
}
```

Then add `t36` to the runner block (Excerpt E). Change the last line:

```bash
t33; t34; t35
```

to:

```bash
t33; t34; t35; t36
```

Why this shape:

- Sourcing with `REPO_SESSION_LIB=1` returns before `main` (guard at
  `bin/repo-session:1080-1082`), so the log captures **only** the explicit
  `build_session_rows` call — no load-time tmux calls.
- Three plain sessions with non-hidden active windows (`Awin`/`Bwin`/`Cwin`, none
  matching `_*`) means the hidden-window branch is never taken, so there are zero
  `list-windows` and zero `display-message` calls — the whole row build is one
  `list-sessions`. `FAKE_TMUX_LOG` logs each invocation's argv (`tests/fake-tmux`
  lines 10–13), so `grep -c '^list-sessions'` = 1 and `grep -c '^display-message'`
  = 0 proves the fan-out is gone. (`grep -c` prints `0` and exits nonzero when
  there are no matches; `|| true` keeps `set -e`-free bash calm and the count
  correct.)

**Verify**:
- `bash -n tests/test-repo-session.sh` → exit 0, no output.
- `bash tests/test-repo-session.sh` → prints `ok t36` (plus all of t1–t35), no
  `FAIL`.
- `bash tests/run.sh` → exit 0.

## Test plan

- **New test t36** (`tests/test-repo-session.sh`): asserts the performance
  invariant this plan exists to create — `build_session_rows` issues exactly one
  `list-sessions` and zero `display-message` calls for a normal (non-hidden)
  row build. Wired into the runner block so it actually runs.
- **Regression coverage already present** (must stay green, unchanged):
  - t8 (lines 157–182) — 6-field shape, field count, `preview == "alpha:0"`.
  - t15 (287–311) — hidden active window substitutes field 2 + preview target.
  - t16 (313–335) — all windows hidden → keep active name/preview.
  - t17 (337–359) — `FERRY_HIDDEN_WINDOW_GLOB` override → no substitution.
  - t20 (401–415) — `--list` applies the hidden-window display rule end-to-end.
  - t6 (121–138) — numbered-menu path with a repo **filter**
    (`FAKE_TMUX_SESSIONS=$'myrepo\nmyrepo-2'`); exercises the tab-anchored grep.
- **Supporting scaffolding**: Step 1's multi-field `list-sessions` branch in
  `tests/fake-tmux` (backward-compatible — names-only callers unaffected).
- Structural pattern for t36: model the sourcing/log-inspection on **t8**
  (`REPO_SESSION_LIB=1; source "$RS"; build_session_rows`) combined with the
  `log=$(cat "$FAKE_TMUX_LOG")` + `grep` idiom used throughout (e.g. t4, t18).
- Verification: `bash tests/run.sh` → exit 0, all tests pass including t36.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/repo-session` exits 0.
- [ ] `bash -n tests/fake-tmux` exits 0.
- [ ] `bash -n tests/test-repo-session.sh` exits 0.
- [ ] `shellcheck bin/repo-session` exits 0 with no new findings (or shellcheck
      is unavailable and that is noted).
- [ ] `bash tests/test-repo-session.sh` prints `ok t36` and shows no `FAIL`,
      including `ok t8`, `ok t15`, `ok t16`, `ok t17`, `ok t20`, `ok t6`.
- [ ] `bash tests/run.sh` exits 0 (full suite green).
- [ ] `grep -cE 'display-message' bin/repo-session` shows the count **dropped by
      five** vs. commit `88cd1f4` (the five per-session calls inside
      `build_session_rows` are gone; the claim-logic call at line ~997 remains).
      Confirm with: `git show 88cd1f4:bin/repo-session | grep -cE 'display-message'`
      vs. `grep -cE 'display-message' bin/repo-session` — the difference is 5.
- [ ] `grep -n 'capture-pane -ep -t {6} 2>/dev/null' bin/repo-session` returns
      exactly one match.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row updated (unless a reviewer maintains it).

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `bin/repo-session:358-403`, line 755, or the `tests/fake-tmux`
  `list-sessions` branch (lines 65–71) does not match Excerpt A / B / C (the
  codebase drifted since this plan was written — the drift-check `git diff --stat`
  reported a change). Do NOT guess at reconciling; report the mismatch.
- **A real-tmux format token cannot reproduce a current column exactly** — name
  the column. Specifically:
  - if `#{session_windows}w` does not yield the exact `<N>w` string (field 3), or
  - if `#{?session_attached,attached,detached}` does not yield exactly `attached`
    / `detached` (field 4), or
  - if `#{session_name}:#{window_index}` does not yield the exact `session:index`
    preview target (field 6), or
  - if `#{window_name}` / `#{pane_current_command}` in a `list-sessions -F`
    context resolve against something other than the session's active window/pane
    (i.e. the row shape changes).
  In any of these cases, STOP and report which column — do NOT silently change the
  row shape or add a field to compensate.
- After Step 2, t8/t15/t16/t17/t20 change from `ok` to `FAIL`, or the row's field
  count or ordering differs — that means the single-call output is not
  byte-identical; STOP and re-check the format string and the fake-tmux branch,
  do not edit the assertions.
- Adding t36 makes any existing test (t1–t35) fail — the fake-tmux change was not
  backward-compatible; STOP and re-check Step 1's `-F` detection.
- The fix appears to require touching an out-of-scope file (e.g. `print_list`,
  `run_picker`, `tests/run.sh`, or any name-only `list-sessions` call site).
- A verification command fails twice after a reasonable fix attempt.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- **The `-F` format string is now the single source of truth for the row shape.**
  Any future column change (add/remove/reorder a field) must be made in THREE
  places together or the tests fail opaquely: (1) `fmt` in `build_session_rows`,
  (2) the multi-field `printf` in the `tests/fake-tmux` `list-sessions` branch,
  and (3) the assertions in t8 (field count, preview column). Field 6 must remain
  the `session:index` preview target because the fzf preview consumes it as `{6}`.
- **Plan 05 (MRU / age ordering) extends this same `-F` format.** The natural
  seam is to append an activity token (e.g. `#{session_activity}` or
  `#{session_last_attached}`) as a **new trailing field used only for sorting**,
  then sort on it and strip it before emit — rather than reintroducing per-session
  forks. Keep the six user-visible fields and their order intact so this plan's
  byte-stability holds; add sort keys as extra columns, not by mutating existing
  ones. Coordinate the fake-tmux + t8 update at that time.
- **Reviewer should scrutinize**: (1) the common-case `printf '%s\n' "$line"`
  really is byte-identical to the old six-field reconstruction (no field dropped,
  no `w`/`attached` transform lost); (2) the filter grep now anchors on a tab
  (`…?"$'\t'`) not `$`, so `<repo> --list` and the repo-scoped picker still match
  `<repo>` and `<repo>-N`; (3) the hidden-window branch still uses plain `%s` (not
  `%sw`) for field 3 because `wins` already carries the `w`; (4) `2>/dev/null` was
  added to the preview but NOT to any assert-visible path.
- **Deferred out of this plan** (separate findings): run_picker action dispatch
  hardening (plan 03) and MRU sorting (plan 05). This plan intentionally keeps
  `sort -V` and the existing selection handling.
