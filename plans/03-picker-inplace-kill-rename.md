# Plan 03: Kill/rename in place via fzf --bind execute+reload (no teardown, single-keystroke confirm)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` if that file exists — unless a reviewer dispatched you
> and told you they maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/repo-session tests/fake-tmux tests/test-picker.sh`
> If `bin/repo-session` or `tests/fake-tmux` changed since this plan was written
> (commit `88cd1f4`), compare the "Current state" excerpts below against the live
> code before proceeding; on a mismatch, treat it as a STOP condition.
> `tests/test-picker.sh` is expected to appear only after plan 01 lands (see
> "Dependencies" — its absence is itself a STOP condition for Step 3).

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/01-*.md` (introduces `tests/test-picker.sh` + a fake `fzf` test harness), `plans/02-*.md` (prior picker refactor). Both must be merged first.
- **Category**: dx
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

Today `ctrl-x` (kill) and `ctrl-r` (rename) are fzf `--expect` keys, so pressing
one makes **fzf exit entirely**. The shell then prints a prompt to `/dev/tty`,
does a **blocking line read** (you must type `y` **and** press Enter — two
keystrokes), and then `continue` **rebuilds the whole picker from scratch**
(banner + rows + preview flash back into view). The user named this as the core
picker pain: a destructive single action tears down and rebuilds the entire UI.

This plan moves `ctrl-x`/`ctrl-r` out of `--expect` and into fzf `--bind`
`execute(...)+reload(...)` actions on a **single persistent fzf instance**. The
confirm becomes one keystroke (`read -rsn1`, no Enter), and after the kill/rename
the list just `reload`s in place — the row disappears without the screen
collapsing to a shell prompt and rebuilding. Attach, the `➕ new session…` create
flow, and the AI launcher keys (`ctrl-a`/`ctrl-g`) keep exiting fzf as before,
because they must replace the current process (`exec`) — they stay outside the
persistent-fzf binds.

## Current state

Files in play:

- `bin/repo-session` — the remote brain. `run_picker()` (the fzf branch, lines
  726–819) is where kill/rename live today; `main()` (lines 824–1077) is the arg
  parser + dispatcher; `picker_kill`/`picker_rename` (lines 405–411) are the
  tmux wrappers; `_ferry_resolve_self` (lines 27–44) is the symlink-safe
  self-path resolver; `_launcher_expect_suffix` (lines 197–203) builds the
  launcher `--expect` list.
- `tests/fake-tmux` — stub tmux for the suite (logs argv to `FAKE_TMUX_LOG`,
  answers `list-sessions`/`display-message`/etc. from env). `kill-session` and
  `rename-session` are accepted and logged (line 175). **Do not modify.**
- `tests/test-picker.sh` — **created by plan 01** (does not exist at `88cd1f4`).
  This plan adds tests here. Read it in full before editing (see Step 3).

### `picker_kill` / `picker_rename` — `bin/repo-session:405-411` (the tmux wrappers; contract asserted by t18/t19 — keep byte-for-byte)

```bash
picker_kill() {
  "$TMUXBIN" kill-session -t "=$1"
}

picker_rename() {
  "$TMUXBIN" rename-session -t "=$1" "$2"
}
```

### `_ferry_resolve_self` — `bin/repo-session:27-44` (symlink-safe self path; reuse it)

```bash
_ferry_resolve_self() {
  local src="${1:-${BASH_SOURCE[0]}}"
  local dir link max=50
  case "$src" in
    /*) ;;
    *) src="$(pwd)/$src" ;;
  esac
  while [ -L "$src" ] && [ "$max" -gt 0 ]; do
    dir=$(cd "$(dirname "$src")" && pwd) || return 1
    link=$(readlink "$src") || return 1
    case "$link" in
      /*) src=$link ;;
      *) src=$dir/$link ;;
    esac
    max=$((max - 1))
  done
  printf '%s\n' "$src"
}
```

### `_launcher_expect_suffix` — `bin/repo-session:197-203` (leading-comma launcher list)

```bash
# Comma-separated --expect list: ctrl-x,ctrl-r[,launcher keys...]
_launcher_expect_suffix() {
  local k out=""
  for k in "${LAUNCHER_KEYS[@]+"${LAUNCHER_KEYS[@]}"}"; do
    out+=",$k"
  done
  printf '%s' "$out"
}
```

Note the established idiom for a **launcher-only** expect list (from the
sub-picker, `bin/repo-session:548`) — strip the leading comma:

```bash
sub_expect=(--expect="$(_launcher_expect_suffix | sed 's/^,//')")
```

### `run_picker` fzf branch — `bin/repo-session:726-819` (the code this plan rewrites)

Hints + expect list (`726-730`):

```bash
  # fzf path: loop so kill/rename / invalid create can reload the list.
  pickfile="${TMPDIR:-/tmp}/repo-session-pick.$$"
  local banner hints header expect_keys lc
  hints='enter=attach · ctrl-x=kill · ctrl-r=rename · esc=quit'
  expect_keys="ctrl-x,ctrl-r$(_launcher_expect_suffix)"
```

The fzf invocation (`748-760`):

```bash
    {
      printf '%s\n' "${rows[@]}"
      printf '%s\n' "$new_label"
    } | fzf --ansi --delimiter=$'\t' \
        --layout=reverse --header-first --cycle \
        --expect="$expect_keys" \
        --header "$header" \
        --preview "$TMUXBIN capture-pane -ep -t {6}" \
        --preview-window=right:60% \
        >"$pickfile" || {
      rm -f "$pickfile"
      exit 130
    }
```

Key/choice parse + `is_new` detection (`762-769`):

```bash
    key=$(head -n 1 "$pickfile")
    choice=$(sed -n '2p' "$pickfile")
    rm -f "$pickfile"

    is_new=0
    if [[ "$choice" == "$new_label" || "$choice" == *$'\t'"$new_label" || "$choice" == "➕ new session…" ]]; then
      is_new=1
    fi
```

New-row guard + create flow (`771-784`):

```bash
    # Action keys on the new-session row: ignore and reload.
    if (( is_new )) && [[ "$key" == "ctrl-x" || "$key" == "ctrl-r" ]]; then
      continue
    fi

    if (( is_new )); then
      # Launcher key arms start command for this one creation (overrides flags).
      if [[ -n "$key" ]] && lc=$(launcher_cmd "$key"); then
        startcmd="$lc"
      fi
      # Success execs attach; cancel exits 130; invalid returns → reload.
      _do_new_session_flow || continue
      continue
    fi
```

The `case "$key"` block — the `ctrl-x`/`ctrl-r` branches here are the exit+rebuild
behavior being removed (`786-818`):

```bash
    name="${choice%%$'\t'*}"
    [[ -z "$name" ]] && exit 130

    case "$key" in
      ctrl-x)
        printf 'kill %s? [y/N] ' "$name" >/dev/tty
        if ! read -r ans </dev/tty; then
          continue
        fi
        if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
          picker_kill "$name"
        fi
        continue
        ;;
      ctrl-r)
        printf 'new name: ' >/dev/tty
        if ! read -r newname </dev/tty; then
          continue
        fi
        if [[ -n "$newname" ]]; then
          picker_rename "$name" "$newname"
        fi
        continue
        ;;
      *)
        # Launcher keys on existing-session rows: ignore, reload.
        if [[ -n "$key" ]] && launcher_cmd "$key" >/dev/null 2>&1; then
          continue
        fi
        # Enter (or empty expect key) → attach
        exec "$TMUXBIN" attach -t "=$name"
        ;;
    esac
  done
```

### `main()` arg parser — `bin/repo-session:824-858` (where the hidden subcommands are added)

```bash
main() {
  local repo="" fresh=0 list=0 pick="" startcmd="" claim=0 fill=0 wantpick=0 help=0 primary=0
  local client_version="" validate=0 validate_arg=""
  local dir sessions
  sessions=()

  while (( $# )); do
    case "$1" in
      --new)              fresh=1; shift ;;
      --list|-l)          list=1; shift ;;
      --resume|-R)        wantpick=1
                          if [[ -n "${2:-}" && "${2:-}" != -* ]]; then pick="$2"; shift 2; else shift; fi ;;
      --resume-closed)    claim=1; shift ;;
      --resume-or-new)    claim=1; fill=1; shift ;;
      --claude|-c)        startcmd="claude"; shift ;;
      --help|-h)          help=1; shift ;;
      --primary|-p)       primary=1; shift ;;
      --client-version)   client_version="${2:-}"; shift 2 ;;
      --validate)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          echo "repo-session: --validate requires a <repo>" >&2
          exit 1
        fi
        validate=1
        validate_arg="$2"
        shift 2
        ;;
      --)                 shift; startcmd="$*"; break ;;
      -*)                 echo "repo-session: ignoring unknown flag '$1'" >&2; shift ;;
      *)                  if [[ -z "$repo" ]]; then repo="$1"; else startcmd="${startcmd:+$startcmd }$1"; fi; shift ;;
    esac
  done

  load_config
  parse_launchers
```

The `--validate` dispatch (the model to copy — dispatch after `parse_launchers`,
exit immediately, never fall through to the picker), `bin/repo-session:860-864`:

```bash
  # --validate dispatches first (before help/list/resume); never touches tmux.
  if (( validate )); then
    validate_repo "$validate_arg"
    exit $?
  fi
```

### LIB block + main invocation — `bin/repo-session:1080-1085`

```bash
# LIB mode: define helpers only (for unit tests / sourcing).
if [[ "${REPO_SESSION_LIB:-}" == "1" ]]; then
  # When sourced: return to caller. When executed with LIB=1: exit quietly.
  return 0 2>/dev/null || exit 0
fi

main "$@"
```

### Existing LIB tests that must stay green — `tests/test-repo-session.sh`

`picker_kill` (t18, `361-379`) and `picker_rename` (t19, `381-397`) source the
script with `REPO_SESSION_LIB=1` and call the helpers directly. This plan does
**not** change `picker_kill`/`picker_rename`, so these stay green — verify they
still do. Excerpt (t18):

```bash
# ---- t18: LIB picker_kill ----
t18() {
  setup
  local log
  export REPO_SESSION_TMUXBIN="$FAKE"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    picker_kill s1
  )
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'kill-session -t =s1' <<<"$log"; then
    ok t18
  else
    fail t18 "log=[$log]"
  fi
  teardown
}
```

`build_session_rows` (t8, `157-176`) is the row generator the new `--_rows`
subcommand wraps; the 6-field format and `=` exact-match target vocabulary
(`-t "=$name"`) are the conventions to reuse verbatim.

### Repo invariants that constrain this change (from the repo's own guidance)

- `set -u` on, `set -e` off in both scripts. Guard array expansions:
  `"${arr[@]+"${arr[@]}"}"`.
- **Non-TTY output is byte-stable and asserted by tests.** Everything this plan
  touches is interactive fzf UI (only reachable on a TTY with `fzf` present) plus
  three **internal, never-user-facing** subcommands — so it must not change any
  existing non-TTY token. Do not touch `doctor`/`update`/`--validate`/`--list`
  output or the `t8` 6-field row format.
- `bin/repo-session` is effectively Linux and already uses `mapfile` + util-linux
  `flock` by design — do not "fix" those.

## Commands you will need

| Purpose        | Command                                                                                      | Expected on success |
|----------------|----------------------------------------------------------------------------------------------|---------------------|
| Drift check    | `git diff --stat 88cd1f4..HEAD -- bin/repo-session tests/fake-tmux tests/test-picker.sh`      | see excerpts still match |
| Syntax check   | `bash -n bin/repo-session`                                                                    | exit 0, no output   |
| Lint           | `shellcheck bin/repo-session`                                                                 | exit 0, no new findings |
| Full suite     | `bash tests/run.sh`                                                                           | exit 0, every `ok tN`, no `FAIL` |
| Rows subcmd    | see Step 1 verify                                                                             | 6-field rows        |
| Kill subcmd    | see Step 1 verify                                                                             | `kill-session -t =s1` in log |

Notes for the executor:
- `shellcheck` is the repo's lint gate. If it is not installed in your
  environment, install it (e.g. `pacman -S shellcheck` / `apt-get install
  shellcheck` / `brew install shellcheck`) or report that you could not run it —
  do **not** skip it silently. Honor existing `# shellcheck disable=` directives
  in the file; add a scoped `disable` only if a new, unavoidable finding appears
  and you can justify it in the commit message.
- `bash tests/run.sh` globs `tests/test-*.sh`, so a `tests/test-picker.sh` added
  by plan 01 is picked up automatically.

## Scope

**In scope** (the only files you may modify):
- `bin/repo-session` — add three hidden subcommands (`--_rows`, `--_kill`,
  `--_rename`) to the `main()` arg parser + dispatch; rewrite the `run_picker`
  fzf branch (lines 726–819) to use `--bind` execute+reload for `ctrl-x`/`ctrl-r`.
- `tests/test-picker.sh` — add the new assertions (Step 3). This file is created
  by plan 01; **only edit it, never re-create it**.

**Out of scope** (do NOT touch, even though they look related):
- `picker_kill` / `picker_rename` (`bin/repo-session:405-411`) — leave the bodies
  and signatures exactly as-is; t18/t19 assert them. The new subcommands *call*
  them.
- The **no-fzf numbered menu** path (`bin/repo-session:688-724`) — it has no binds
  and its behavior must not change.
- `tests/fake-tmux` — do not modify; `kill-session`/`rename-session` are already
  logged.
- The duplicated banner + path-resolver helpers in the two scripts — do not
  dedup them (deliberate).
- Bulk multi-select / `--multi` (that is plan 04), MRU ordering (plan 05).
- Any non-TTY output token in `doctor`, `update`, `--validate`, `--list`.

## Git workflow

- Branch: `advisor/03-picker-inplace-kill-rename` (repo has no strict convention;
  match this).
- Commit style is conventional-commits (see `git log`, e.g.
  `chore(demo): re-record with real JetBrains Mono metrics`). Suggested messages:
  - `feat(repo-session): hidden --_rows/--_kill/--_rename subcommands for picker binds`
  - `feat(repo-session): in-place kill/rename via fzf --bind execute+reload`
  - `test(picker): assert bind callbacks kill/rename without picker teardown`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add hidden `--_rows` / `--_kill` / `--_rename` subcommands to `main()`

These are **internal** entry points the fzf binds call back into (they are never
documented in `--help` and never shown to users). Each must dispatch and exit
immediately, exactly like `--validate` — never fall through into the picker.

1a. In the `main()` local declarations (`bin/repo-session:825-828`), add mode
flags and the kill/rename operands. Change:

```bash
  local repo="" fresh=0 list=0 pick="" startcmd="" claim=0 fill=0 wantpick=0 help=0 primary=0
  local client_version="" validate=0 validate_arg=""
```

to add a line after the `validate` line:

```bash
  local rows_mode=0 kill_mode=0 rename_mode=0 kname="" rename_arg=""
```

1b. In the arg-parser `case` (before the `--)` / `-*)` / `*)` fallbacks), add
three entries. Follow the existing `--client-version) ... shift 2 ;;` idiom
(these are always invoked internally with their operands present):

```bash
      --_rows)
        rows_mode=1
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then repo="$2"; shift 2; else shift; fi ;;
      --_kill)            kill_mode=1; kname="${2:-}"; shift 2 ;;
      --_rename)          rename_mode=1; kname="${2:-}"; rename_arg="${3:-}"; shift 3 ;;
```

1c. Add the dispatch immediately after `parse_launchers` and **before** the
`--validate` block (`bin/repo-session:858-860`), so the picker is never entered:

```bash
  load_config
  parse_launchers

  # Hidden internal subcommands used by the fzf --bind callbacks in run_picker.
  # Never user-facing; must dispatch and exit without entering the picker.
  if (( rows_mode ));   then build_session_rows "$repo"; exit 0; fi
  if (( kill_mode ));   then picker_kill "$kname"; exit $?; fi
  if (( rename_mode )); then picker_rename "$kname" "$rename_arg"; exit $?; fi
```

Rationale for placement: `build_session_rows` reads `FERRY_HIDDEN_WINDOW_GLOB`
(a config key with a default) so it must run **after** `load_config`; dispatching
here mirrors the picker's own row generation exactly, so `reload` shows the same
rows the picker would.

**Verify** (run from repo root; uses the fake tmux so no real tmux is touched):

```bash
FAKE="$PWD/tests/fake-tmux"
REPO_SESSION_TMUXBIN="$FAKE" FAKE_TMUX_SESSIONS=$'alpha\nbeta' \
  FAKE_TMUX_META=$'alpha|Awin|2w attached claude\nbeta|Bwin|1w detached bash' \
  bash bin/repo-session --_rows | awk -F'\t' '{print NF, $1}'
```
→ expected two lines: `6 alpha` and `6 beta` (6 tab-fields each, session names in
field 1 — same shape as t8).

```bash
LOG=$(mktemp)
REPO_SESSION_TMUXBIN="$PWD/tests/fake-tmux" FAKE_TMUX_LOG="$LOG" \
  bash bin/repo-session --_kill s1
grep -q 'kill-session -t =s1' "$LOG" && echo KILL_OK; rm -f "$LOG"
```
→ expected: `KILL_OK`.

```bash
LOG=$(mktemp)
REPO_SESSION_TMUXBIN="$PWD/tests/fake-tmux" FAKE_TMUX_LOG="$LOG" \
  bash bin/repo-session --_rename s1 newname
grep -q 'rename-session -t =s1 newname' "$LOG" && echo RENAME_OK; rm -f "$LOG"
```
→ expected: `RENAME_OK`.

```bash
bash -n bin/repo-session && echo SYNTAX_OK
```
→ expected: `SYNTAX_OK`.

### Step 2: Rewrite the `run_picker` fzf branch to use `--bind` execute+reload

The goal: `ctrl-x`/`ctrl-r` become `--bind` actions on one persistent fzf; the
launcher keys stay on `--expect`; Enter still attaches; the `➕ new session…`
create flow is unchanged.

2a. **Change the expect list to launcher-keys-only.** Replace the two lines at
`bin/repo-session:729-730`:

```bash
  hints='enter=attach · ctrl-x=kill · ctrl-r=rename · esc=quit'
  expect_keys="ctrl-x,ctrl-r$(_launcher_expect_suffix)"
```

with (drop `ctrl-x,ctrl-r`; keep only launcher keys, using the established
`sed 's/^,//'` idiom from line 548 — the hints string is unchanged, still
accurate):

```bash
  hints='enter=attach · ctrl-x=kill · ctrl-r=rename · esc=quit'
  expect_keys="$(_launcher_expect_suffix | sed 's/^,//')"
```

2b. **Resolve the self-path once and build the reload command + binds.** Inside
`run_picker`, before the `while true` loop that starts at line 731, add
self-resolution and a guard. Insert immediately after the `expect_keys=` line
from 2a:

```bash
  local self rows_cmd kill_bind rename_bind
  self=$(_ferry_resolve_self "${BASH_SOURCE[0]}") || {
    echo "repo-session: cannot resolve own path for picker binds" >&2
    exit 1
  }
  if [[ ! -x "$self" ]]; then
    echo "repo-session: own path not executable ($self); cannot bind kill/rename" >&2
    exit 1
  fi
  # reload() must reproduce the picker feed: live rows PLUS the ➕ create row,
  # so the create entry survives a kill/rename reload. $new_label expands here
  # (build shell) so its exact bytes match the initial feed and the is_new test.
  rows_cmd="\"$self\" --_rows \"$repo\"; printf '%s\n' \"$new_label\""
  # ctrl-x: one-key [y/N] confirm in place, then delete the session and reload.
  # ctrl-r: prompt for a new name (line read, needs text) then rename and reload.
  # {1} = first tab-field = session name (fzf shell-escapes it). $__c/$__n are
  # evaluated by fzf's exec shell, so they are escaped here (\$__c, \$__n).
  kill_bind="ctrl-x:execute(printf 'kill %s? [y/N] ' {1}; read -rsn1 __c; printf '\n'; [ \"\$__c\" = y ] && \"$self\" --_kill {1})+reload($rows_cmd)"
  rename_bind="ctrl-r:execute(printf 'rename %s -> ' {1}; read -re __n; [ -n \"\$__n\" ] && \"$self\" --_rename {1} \"\$__n\")+reload($rows_cmd)"
```

Notes the executor must respect:
- Use `[y/N]` (square brackets), **not** `(y/N)` — fzf's `execute(...)` matches
  balanced parentheses, and a literal `)` inside the prompt would confuse the
  parser. Square brackets are safe.
- Do **not** wrap `{1}` in quotes inside the bind (`--_kill {1}`, not
  `--_kill "{1}"`); fzf substitutes `{1}` with a single-quote-escaped token, so
  quoting it again would embed literal quotes.
- The reload command deliberately re-appends `$new_label`; without it, a
  kill/rename reload would drop the `➕ new session…` row.

2c. **Wire the binds into the fzf call and drop the dead `--expect` entries.**
Replace the fzf invocation at `bin/repo-session:751-760`:

```bash
    } | fzf --ansi --delimiter=$'\t' \
        --layout=reverse --header-first --cycle \
        --expect="$expect_keys" \
        --header "$header" \
        --preview "$TMUXBIN capture-pane -ep -t {6}" \
        --preview-window=right:60% \
        >"$pickfile" || {
      rm -f "$pickfile"
      exit 130
    }
```

with (add the two `--bind` flags; `--expect` now carries only launcher keys):

```bash
    } | fzf --ansi --delimiter=$'\t' \
        --layout=reverse --header-first --cycle \
        --expect="$expect_keys" \
        --bind "$kill_bind" \
        --bind "$rename_bind" \
        --header "$header" \
        --preview "$TMUXBIN capture-pane -ep -t {6}" \
        --preview-window=right:60% \
        >"$pickfile" || {
      rm -f "$pickfile"
      exit 130
    }
```

2d. **Remove the now-dead new-row `ctrl-x`/`ctrl-r` guard.** `ctrl-x`/`ctrl-r` can
no longer surface as `$key` (they never exit fzf now), so delete the block at
`bin/repo-session:771-774`:

```bash
    # Action keys on the new-session row: ignore and reload.
    if (( is_new )) && [[ "$key" == "ctrl-x" || "$key" == "ctrl-r" ]]; then
      continue
    fi

```

(Delete those four lines including the trailing blank line. The `if (( is_new ))`
create-flow block immediately below it stays.)

2e. **Remove the dead `ctrl-x`/`ctrl-r` case branches.** In the `case "$key" in`
block (`bin/repo-session:789-818`), delete the `ctrl-x)` and `ctrl-r)` branches
entirely, keeping only the `*)` branch. The block becomes:

```bash
    case "$key" in
      *)
        # Launcher keys on existing-session rows: ignore, reload.
        if [[ -n "$key" ]] && launcher_cmd "$key" >/dev/null 2>&1; then
          continue
        fi
        # Enter (or empty expect key) → attach
        exec "$TMUXBIN" attach -t "=$name"
        ;;
    esac
```

Because only `*)` remains, the `case` still behaves correctly; you may leave it
as a single-branch `case` (simplest, lowest-risk edit). Do not rewrite the
surrounding `name=…`/`[[ -z "$name" ]]` lines.

2f. **Prune now-unused locals.** With the `ctrl-x`/`ctrl-r` branches gone, the
`ans` and `newname` locals declared for `run_picker` (in its `local` line, `bin/
repo-session:683`) are no longer referenced. Remove `ans` and `newname` from that
`local` declaration **only if** `shellcheck` flags them as unused; otherwise
leave the declaration untouched to minimize churn. Current line 683 for
reference:

```bash
  local line choice name i nsel key ans newname pickfile
```

**Verify**:

```bash
bash -n bin/repo-session && echo SYNTAX_OK
```
→ `SYNTAX_OK`.

```bash
shellcheck bin/repo-session && echo LINT_OK
```
→ `LINT_OK` (no new findings; honor existing `disable` directives).

```bash
# The dead exit+rebuild branches are gone; the binds are present.
grep -n 'ctrl-x:execute' bin/repo-session
grep -n 'ctrl-r:execute' bin/repo-session
grep -c 'printf .new name: .' bin/repo-session   # → 0 (old rename prompt removed)
```
→ first two grep lines each print exactly one match; the third prints `0`.

### Step 3: Add bind-callback tests to `tests/test-picker.sh`

**Precondition**: `tests/test-picker.sh` exists (created by plan 01). If it does
**not** exist, STOP — plan 01 has not landed (see STOP conditions). Read the whole
file first to learn plan 01's helpers (`setup`/`teardown`, `ok`/`fail`, the fake
`fzf` mechanism, and how test functions are registered at the bottom, e.g. a
`tN; tN+1; …` line like `tests/test-repo-session.sh:829`).

Add the following, modeled structurally on t18/t19 (quoted in "Current state").
Use the file's own `setup`/`teardown` and its `REPO_SESSION_TMUXBIN`/
`FAKE_TMUX_LOG` conventions. Register each new function in the file's run line.

**Mandatory tests — the callback subcommands the binds invoke** (no fake `fzf`
needed; they run `repo-session` as a subprocess, which is exactly what the bind
`execute()` does):

1. **`--_kill` logs a kill without any picker teardown.** Set
   `FAKE_TMUX_SESSIONS`, run `bash "$RS" --_kill s1`, assert `FAKE_TMUX_LOG`
   contains `kill-session -t =s1` and contains **no** `capture-pane` /
   `list-sessions` "rebuild" churn beyond what `picker_kill` itself emits (i.e.
   the only tmux call logged is the kill — proving the kill path does not rebuild
   the picker). Concretely: assert the log has exactly one line and it matches
   `kill-session -t =s1`.

2. **`--_rename` logs a rename.** Run `bash "$RS" --_rename s1 newname`, assert
   `FAKE_TMUX_LOG` contains `rename-session -t =s1 newname`.

3. **`--_rows` reproduces the 6-field rows.** With `FAKE_TMUX_SESSIONS` +
   `FAKE_TMUX_META` set (as in t8), run `bash "$RS" --_rows`, assert the output
   has one 6-tab-field row per session and field 1 is the session name — i.e. the
   `reload` data source matches `build_session_rows`.

Example shape for test 1 (adapt names/registration to plan 01's harness):

```bash
# ---- tNN: --_kill bind callback logs kill, no picker rebuild ----
tNN() {
  setup
  local log lines
  export FAKE_TMUX_SESSIONS="s1"
  export REPO_SESSION_TMUXBIN="$FAKE"
  bash "$RS" --_kill s1
  log=$(cat "$FAKE_TMUX_LOG")
  lines=$(printf '%s\n' "$log" | grep -c . || true)
  if [[ "$lines" -eq 1 ]] && grep -q 'kill-session -t =s1' <<<"$log"; then
    ok tNN
  else
    fail tNN "log=[$log] lines=$lines"
  fi
  teardown
}
```

**Recommended integration test (only if plan 01's fake `fzf` can fire a bind).**
Read plan 01's fake `fzf`. If it can be told which `--bind` to trigger and can
run that bind's `execute(...)` body (e.g. via an env var such as
`FAKE_FZF_FIRE=ctrl-x` plus a way to feed `y` to the confirm read), add a test
that:
- drives `run_picker` through the fzf path with one session,
- fires the `ctrl-x` bind with a `y` confirm,
- asserts `kill-session -t =s1` appears in `FAKE_TMUX_LOG`, **and**
- asserts the fake `fzf` was invoked **exactly once** across the kill (e.g. a
  counter file the fake `fzf` increments) — proving the persistent instance was
  not torn down and rebuilt.

If plan 01's fake `fzf` does not support firing a bind, **do not** invent a new
fake-`fzf` contract here (that is plan 01's surface) — the three mandatory
callback tests above are sufficient for this plan's Done criteria; note the gap
in your final report so plan 04 (which extends these binds) can add the
end-to-end firing test alongside its `--multi` work.

**Verify**:

```bash
bash tests/run.sh; echo "run.sh exit=$?"
```
→ every `ok tN` prints, no `FAIL` line, `run.sh exit=0`. In particular t18 and
t19 (in `tests/test-repo-session.sh`) still pass — `picker_kill`/`picker_rename`
were not changed.

### Step 4: Manual acceptance (document, do not fake)

Record this in your final report (you cannot run it in CI — it needs a real
terminal + real `fzf`):

- On a host with `fzf >= 0.23` (the floor for `execute`+`reload`; the script
  already relies on `--header-first`, so no new floor is introduced), run the
  picker with at least one live session. Press `ctrl-x`: fzf prompts
  `kill <name>? [y/N]`, a single `y` keystroke (no Enter) removes the row and the
  list refreshes **in place** — the screen does not collapse to a shell prompt
  and the banner/preview do not flash a full rebuild. Press `esc` after `ctrl-x`
  with `N`/any-other-key: nothing is killed.
- Press `ctrl-r`: fzf prompts `rename <name> -> `, typing a new name + Enter
  renames in place and the row updates.
- Confirm the `➕ new session…` row is still present after a kill/rename reload.

**`$SHELL` caveat to verify on the dev remote**: fzf runs `execute()` via the
user's `$SHELL`. The confirm uses bash-style `read -rsn1` / `read -re`. Confirm
the remote login shell is bash (`echo "$SHELL"` → `.../bash`). If it is not
bash, `read -rsn1` may not do a silent single-key read — report this rather than
working around it (see STOP conditions).

## Test plan

- New tests in `tests/test-picker.sh` (created by plan 01):
  - `--_kill` callback: logs `kill-session -t =s1`, single tmux call, no rebuild.
  - `--_rename` callback: logs `rename-session -t =s1 newname`.
  - `--_rows` callback: 6-field rows, one per session, field 1 = name.
  - (Recommended, conditional) end-to-end `ctrl-x` bind firing on plan 01's fake
    `fzf`, asserting the kill + a single `fzf` invocation.
- Structural pattern to model after: t18/t19 and t8 in
  `tests/test-repo-session.sh`.
- Verification: `bash tests/run.sh` → all pass including the new picker tests and
  the unchanged t18/t19.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/repo-session` exits 0.
- [ ] `shellcheck bin/repo-session` exits 0 with no new findings.
- [ ] `bash tests/run.sh` exits 0; the new `--_kill`/`--_rename`/`--_rows`
      callback tests exist in `tests/test-picker.sh` and pass; t18/t19 still pass.
- [ ] `bash bin/repo-session --_kill s1` (with `REPO_SESSION_TMUXBIN` =
      `tests/fake-tmux`, `FAKE_TMUX_LOG` set) logs `kill-session -t =s1`.
- [ ] `bash bin/repo-session --_rename s1 newname` logs
      `rename-session -t =s1 newname`.
- [ ] `bash bin/repo-session --_rows` prints 6-tab-field rows matching
      `build_session_rows`.
- [ ] `grep -n 'ctrl-x:execute' bin/repo-session` and
      `grep -n 'ctrl-r:execute' bin/repo-session` each return exactly one match.
- [ ] `grep -c 'new name: ' bin/repo-session` returns `0` (old rename prompt gone).
- [ ] `picker_kill` / `picker_rename` (`bin/repo-session:405-411`) are unchanged.
- [ ] No files outside `bin/repo-session` and `tests/test-picker.sh` are modified
      (`git status`).
- [ ] `plans/README.md` status row updated (if that file exists).

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows `bin/repo-session` or `tests/fake-tmux` changed since
  `88cd1f4` and the "Current state" excerpts no longer match — line numbers or
  code in `run_picker`/`main`/`picker_kill`/`picker_rename` differ. Do **not**
  guess where to edit.
- `tests/test-picker.sh` does not exist (plan 01 has not landed) — this plan
  depends on it. Do not create the file or a substitute fake `fzf`.
- `_ferry_resolve_self "${BASH_SOURCE[0]}"` fails, or the resolved path is not
  executable, under the symlinked install (`install.sh` symlinks
  `bin/repo-session` onto the remote) — the reload/execute binds cannot call back
  into the script. Do **not** fall back to the old exit+rebuild behavior; report
  the resolution failure so the approach can be revisited.
- The remote's `$SHELL` is not bash and the single-key `read -rsn1` confirm does
  not work in fzf's `execute()` — report it; do not silently switch to a
  two-keystroke line read.
- A verification command fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file (e.g. `tests/fake-tmux`,
  `picker_kill`/`picker_rename`, or the no-fzf menu path).

## Maintenance notes

For the human/agent who owns this code after the change lands:

- **The hidden `--_rows` / `--_kill` / `--_rename` subcommands are an internal
  contract** between `run_picker`'s fzf binds and the script itself. They are
  intentionally undocumented in `--help`. Keep them: (a) dispatching after
  `load_config`/`parse_launchers`, (b) exiting without entering the picker, and
  (c) delegating to `build_session_rows` / `picker_kill` / `picker_rename` so
  there is a single source of truth for the `=` exact-match target and the
  6-field row format.
- **Keep the `reload()` row command (`rows_cmd`) factored.** Plan 04 adds
  `--multi` bulk kill on top of these binds and will reuse the same reload
  command and the `--_kill` callback (bulk kill iterates selected `{+1}` names).
  Do not inline `rows_cmd` back into the fzf call.
- A reviewer should scrutinize: the bind-string quoting (`{1}` unquoted;
  `\$__c`/`\$__n` escaped for fzf's exec shell; `[y/N]` not `(y/N)`), that
  `--expect` no longer contains `ctrl-x`/`ctrl-r`, and that the `reload` command
  re-appends `$new_label` so the `➕` row survives.
- Deferred out of this plan (by design): the end-to-end fake-`fzf` bind-firing
  test is only added if plan 01's fake `fzf` supports it; otherwise it lands with
  plan 04. The `$SHELL`-is-bash assumption for fzf `execute()` is documented, not
  enforced in code.
