# Plan 01: Add a fake fzf stub and end-to-end tests for the picker kill/rename/launcher dispatch

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` **if that file exists** — otherwise skip it (the
> advisor maintains the index).
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/repo-session`
> This plan creates two NEW files but *characterizes* the current behavior of
> `bin/repo-session` — so the real drift risk is that script. If the command
> shows `bin/repo-session` changed since this plan was written, compare the
> "Current state" excerpts below against the live code before proceeding; on
> any mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

The interactive fzf picker in `bin/repo-session` (`run_picker`, the `while true`
fzf branch) has **zero automated coverage today**. Every existing repo-session
test that touches the picker sets `FERRY_NO_FZF=1`, which forces the numbered
menu and completely bypasses the fzf branch. That means the ctrl-x kill confirm,
ctrl-r rename, launcher-key arming, and the new-session-row guard are only
reachable through code that no test executes. Plans 03/04/05 will **rewrite that
same interactive loop** (moving to `fzf --bind` / reload actions). Without a
characterization net first, those rewrites can silently break kill/rename/launch
and the suite would stay green. This plan builds the missing scaffolding — a
fake `fzf` and five end-to-end cases that pin the *current* dispatch behavior —
so the later rewrites have a safety net. It is a **prerequisite for plans
02/03/04/05**.

## Current state

Files involved:

- `bin/repo-session` — remote brain; the picker lives in `run_picker` (lines
  680–820). This plan does **not** modify it; it only characterizes it.
- `tests/fake-tmux` — existing tmux stub. Logs every argv to `$FAKE_TMUX_LOG`;
  answers `list-sessions`/`has-session`/`display-message` from `FAKE_TMUX_*`
  env. `kill-session`, `rename-session`, `new-session`, `send-keys`, `attach`
  all just log-and-`exit 0` (see its `case` at lines 175–177). This is what the
  new tests assert against.
- `tests/fake-bin/` — existing PATH-stub dir (currently holds `ssh`, `mosh`,
  both `755`). **The new fake `fzf` goes here** so `command -v fzf` finds it.
- `tests/test-repo-session.sh` — the structural model for the new test file
  (`ok`/`fail`, `setup`/`teardown` with a temp `HOME`, `tXX` functions). Read
  lines 11–39 for the helper shape to mirror.
- `tests/run.sh` — the runner. It auto-globs `tests/test-*.sh` (line 8:
  `for t in tests/test-*.sh`) and runs each. **No edit to `run.sh` is needed** —
  naming the new file `tests/test-picker.sh` makes it run automatically.

### The dispatch code being characterized (`bin/repo-session`)

The main picker's fzf branch reads the pressed key + chosen row from a pickfile
and dispatches. Current excerpt, `bin/repo-session:726-819`:

```bash
  # fzf path: loop so kill/rename / invalid create can reload the list.
  pickfile="${TMPDIR:-/tmp}/repo-session-pick.$$"
  local banner hints header expect_keys lc
  hints='enter=attach · ctrl-x=kill · ctrl-r=rename · esc=quit'
  expect_keys="ctrl-x,ctrl-r$(_launcher_expect_suffix)"
  while true; do
    rows=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && rows+=("$line")
    done < <(build_session_rows "$repo")
    ...
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

    key=$(head -n 1 "$pickfile")
    choice=$(sed -n '2p' "$pickfile")
    rm -f "$pickfile"

    is_new=0
    if [[ "$choice" == "$new_label" || "$choice" == *$'\t'"$new_label" || "$choice" == "➕ new session…" ]]; then
      is_new=1
    fi

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

Key facts the tests rely on:

1. **The picker writes fzf output to a pickfile and reads `key=head -n1`,
   `choice=sed -n 2p`.** So the fake fzf must emit exactly two lines: the pressed
   key on line 1 (empty for plain Enter) and the chosen row on line 2. This is
   the `fzf --expect` contract.
2. **The confirm/rename reads bind `/dev/tty`, not stdin** (`read -r ans
   </dev/tty`, `read -r newname </dev/tty`). This is the crux: feeding the `y`,
   `n`, or new name requires a pseudo-terminal, not a normal pipe. See STOP
   conditions.
3. **On any `continue` the loop calls fzf again.** A static stub would loop
   forever, so the stub is *sequenced*: the second (or a later) fzf call returns
   `ABORT` → the picker's `|| { ...; exit 130; }` fires and the process exits
   cleanly. This is how each case terminates.

`new_label` (`bin/repo-session:684`):

```bash
  local new_label=$'➕ new session…'
```

`picker_kill` / `picker_rename` (`bin/repo-session:405-411`) — these are what the
`kill-session`/`rename-session` assertions match:

```bash
picker_kill() {
  "$TMUXBIN" kill-session -t "=$1"
}

picker_rename() {
  "$TMUXBIN" rename-session -t "=$1" "$2"
}
```

The launcher-on-new-row path calls `_do_new_session_flow`, which for a
repo-scoped picker runs a **second** fzf (the sub-picker in `_pick_repo_for_new`,
`bin/repo-session:537-565`) whose stdin is just the one scoped repo name. With
the default `FERRY_LAUNCHERS` (`ctrl-a:claude,ctrl-g:grok`) that sub-picker also
uses `--expect`, so it too reads a two-line pickfile. That is why case p4's
responses file has a **second** line for the sub-picker.

Default launcher config (`bin/repo-session:136`): `FERRY_LAUNCHERS="ctrl-a:claude,ctrl-g:grok"`
→ `ctrl-a` arms `claude`. The tests rely on this default (they do **not** set
`FERRY_LAUNCHERS`).

### fake-tmux behavior the assertions depend on (verified)

- `list-sessions` prints the newline names in `$FAKE_TMUX_SESSIONS`.
- `has-session -t =NAME` strips the leading `=` then does an **exact** compare
  against `$FAKE_TMUX_SESSIONS` lines (so `myrepo-2` is NOT found when only
  `myrepo` exists → `_next_free_name` returns `myrepo-2`).
- `kill-session`/`rename-session`/`new-session`/`send-keys`/`attach` only append
  their argv to `$FAKE_TMUX_LOG` and exit 0.
- Because the `#{session_attached}` display-message format string contains the
  substring `attach`, the "no attach happened" assertion in p5 MUST match
  `attach -t` (with the space+dash), never a bare `attach`. This is already
  handled in the shipped test.

## Commands you will need

| Purpose            | Command                                                                 | Expected on success                    |
|--------------------|-------------------------------------------------------------------------|----------------------------------------|
| pty feasibility    | `printf 'X\n' \| script -qec 'read -r v </dev/tty; [ "$v" = X ]' /dev/null; echo $?` | prints `0`                             |
| Syntax (stub)      | `bash -n tests/fake-bin/fzf`                                            | exit 0, no output                      |
| Syntax (test)      | `bash -n tests/test-picker.sh`                                          | exit 0, no output                      |
| Stub executable    | `test -x tests/fake-bin/fzf && echo x-ok`                              | prints `x-ok`                          |
| New test alone     | `bash tests/test-picker.sh`                                            | `ok p1` … `ok p5`, exit 0              |
| Full suite         | `bash tests/run.sh`                                                    | all `ok …` lines, exit 0               |

(`script` is util-linux `script`; on the verification machine it is `script
from util-linux 2.42.1`. The pty-feasibility command above is the gate for the
`/dev/tty`-dependent cases — run it first.)

## Suggested executor toolkit

- No special skills required. This is plain bash test authoring.
- Read `tests/test-repo-session.sh:11-39` (helpers + setup/teardown) and
  `tests/fake-tmux` in full before starting, so the new files match house style.

## Scope

**In scope** (the only files you create):

- `tests/fake-bin/fzf` (create; make executable)
- `tests/test-picker.sh` (create)

**Out of scope** (do NOT touch, even though they look related):

- `bin/repo-session` — plans 03/04/05 change the picker later. This plan
  characterizes CURRENT behavior; changing the source here would defeat the
  purpose (the net must reflect what exists now).
- `bin/mossferry`, `lib/green-ui.sh`, `install.sh` — unrelated.
- `tests/run.sh` — no edit needed; it auto-globs `tests/test-*.sh`.
- `tests/fake-tmux`, `tests/fake-bin/ssh`, `tests/fake-bin/mosh`,
  `tests/test-repo-session.sh`, and every other existing test — read-only
  references.
- Any `fzf --bind` / reload logic — that is plan 03.

## Git workflow

- Branch: `advisor/01-test-picker-interactive` (or the repo's convention if one
  is evident from `git log`; recent history uses Conventional Commits, e.g.
  `chore(demo): …`, `assets: …`).
- Commit once, message style Conventional Commits, e.g.
  `test(picker): add fake fzf stub + e2e kill/rename/launcher cases`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the fake fzf stub `tests/fake-bin/fzf`

Create the file with **exactly** this content (verified working against the live
`bin/repo-session` at commit 88cd1f4):

```bash
#!/usr/bin/env bash
# Fake fzf for picker tests. Reads the candidate rows on stdin; emits the
# fzf --expect contract on stdout: line1=pressed key, line2=chosen row.
# Sequenced via FAKE_FZF_RESPONSES (file, one response per fzf call) +
# FAKE_FZF_COUNTER (file holding the 0-based invocation index).
#   response line: "KEY<TAB>PATTERN"  (KEY empty => plain Enter)
#                  "ABORT"            => behave like Esc (exit 130)
# Logs each argv to FAKE_FZF_LOG (like tests/fake-tmux).
set -u
[[ -n "${FAKE_FZF_LOG:-}" ]] && printf 'fzf %s\n' "$*" >>"$FAKE_FZF_LOG"

# Slurp candidate rows.
cands=()
while IFS= read -r _l || [[ -n "$_l" ]]; do cands+=("$_l"); done

# Which invocation is this?
cfile="${FAKE_FZF_COUNTER:-}"
idx=0
if [[ -n "$cfile" && -r "$cfile" ]]; then idx=$(<"$cfile"); fi
[[ "$idx" =~ ^[0-9]+$ ]] || idx=0
printf '%s\n' "$((idx+1))" >"${cfile:-/dev/null}" 2>/dev/null || true

# Fetch the idx-th response (1-based sed line).
resp=""
if [[ -n "${FAKE_FZF_RESPONSES:-}" && -r "${FAKE_FZF_RESPONSES}" ]]; then
  resp=$(sed -n "$((idx+1))p" "$FAKE_FZF_RESPONSES")
fi
# No response left, or explicit ABORT => Esc/cancel.
if [[ -z "$resp" || "$resp" == "ABORT" ]]; then
  exit 130
fi

key="${resp%%$'\t'*}"
pat="${resp#*$'\t'}"
[[ "$resp" != *$'\t'* ]] && pat=""   # response had no tab => empty pattern

# Choose the row: exact match first, else first substring match, else pat as-is.
choice=""
for c in "${cands[@]+"${cands[@]}"}"; do
  if [[ "$c" == "$pat" ]]; then choice="$c"; break; fi
done
if [[ -z "$choice" ]]; then
  for c in "${cands[@]+"${cands[@]}"}"; do
    if [[ -n "$pat" && "$c" == *"$pat"* ]]; then choice="$c"; break; fi
  done
fi
[[ -z "$choice" ]] && choice="$pat"

printf '%s\n' "$key"
printf '%s\n' "$choice"
exit 0
```

Then make it executable (mandatory — `command -v fzf` requires the exec bit; the
sibling stubs `ssh`/`mosh` are `755`):

```bash
chmod +x tests/fake-bin/fzf
```

**Verify**:
- `bash -n tests/fake-bin/fzf` → exit 0, no output.
- `test -x tests/fake-bin/fzf && echo x-ok` → prints `x-ok`.

### Step 2: Confirm the pty feasibility gate

Before writing the test, confirm `/dev/tty` can be fed here (this is the whole
plan's linchpin — see STOP conditions):

```bash
printf 'X\n' | script -qec 'read -r v </dev/tty; [ "$v" = X ]' /dev/null; echo $?
```

**Verify**: prints `0`.

If it prints anything else, **STOP** and follow the STOP condition — do not edit
`bin/repo-session`.

### Step 3: Create the test file `tests/test-picker.sh`

Create the file with **exactly** this content (verified: all five cases pass
against the live `bin/repo-session` at commit 88cd1f4). It mirrors
`tests/test-repo-session.sh` house style and self-guards on the pty check:

```bash
#!/usr/bin/env bash
# tests/test-picker.sh — interactive fzf-picker dispatch (p1–p5).
# Characterizes CURRENT bin/repo-session run_picker behavior so plans 03/04/05
# have a regression net. Drives fzf via a PATH-injected stub (tests/fake-bin/fzf)
# and the /dev/tty confirm/rename reads via a util-linux `script` pty.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RS="$ROOT/bin/repo-session"
FAKE="$ROOT/tests/fake-tmux"
FAKE_BIN="$ROOT/tests/fake-bin"
FAIL=0

ok()  { printf 'ok %s\n' "$1"; }
fail(){ printf 'FAIL %s — %s\n' "$1" "$2"; FAIL=1; }

# Can a pty feed /dev/tty here? (util-linux `script -qec`, forwarding stdin.)
PTY_OK=0
if command -v script >/dev/null 2>&1; then
  if printf 'X\n' | script -qec 'read -r v </dev/tty; [ "$v" = X ]' /dev/null >/dev/null 2>&1; then
    PTY_OK=1
  fi
fi

setup() {
  export TMPDIR="${TEST_TMPDIR_ROOT:-/tmp}"
  export HOME="$(mktemp -d "${TMPDIR}/ferry-home.XXXXXX")"
  _TEST_TMP="$(mktemp -d "${TMPDIR}/ferry-tmp.XXXXXX")"
  export TMPDIR="$_TEST_TMP"
  export FERRY_REPO_BASE="$(mktemp -d "${TMPDIR}/ferry-base.XXXXXX")"
  export FAKE_TMUX_LOG="$(mktemp "${TMPDIR}/ferry-tlog.XXXXXX")"
  export FAKE_FZF_LOG="$(mktemp "${TMPDIR}/ferry-flog.XXXXXX")"
  export FAKE_FZF_COUNTER="${TMPDIR}/ferry-fzf.count"
  export FAKE_FZF_RESPONSES="${TMPDIR}/ferry-fzf.resp"
  export REPO_SESSION_TMUXBIN="$FAKE"
  export PATH="${FAKE_BIN}:${PATH}"
  unset FERRY_NO_FZF 2>/dev/null || true
  unset REPO_SESSION_LIB 2>/dev/null || true
  unset FERRY_LAUNCHERS 2>/dev/null || true
  unset FERRY_HIDDEN_WINDOW_GLOB 2>/dev/null || true
  rm -f "$FAKE_FZF_COUNTER"
  : >"$FAKE_TMUX_LOG"
  : >"$FAKE_FZF_LOG"
  export FAKE_TMUX_SESSIONS="myrepo"
  export FAKE_TMUX_META="myrepo|w|1w detached bash"
  export FAKE_TMUX_WINDOWS=""
  mkdir -p "$HOME/.config/mossferry" "$FERRY_REPO_BASE/myrepo"
}

teardown() {
  local home="${HOME:-}" tmp="${_TEST_TMP:-}" base="${FERRY_REPO_BASE:-}"
  export TMPDIR="${TEST_TMPDIR_ROOT:-/tmp}"
  unset _TEST_TMP FERRY_REPO_BASE FAKE_TMUX_LOG FAKE_FZF_LOG \
        FAKE_FZF_COUNTER FAKE_FZF_RESPONSES 2>/dev/null || true
  rm -rf "$home" "$tmp" "$base" 2>/dev/null || true
}

# Run `repo-session <args>` under a pty, feeding $1 to /dev/tty.
run_pty() {
  local input="$1"; shift
  printf '%s' "$input" | script -qec "bash '$RS' $*" /dev/null >/dev/null 2>&1
}

# ---- p1: ctrl-x on a real row, answer y → kill-session ----
p1() {
  [[ $PTY_OK -eq 1 ]] || { fail p1 "no pty driver — STOP per plan 01"; return; }
  setup
  printf 'ctrl-x\tmyrepo\nABORT\n' >"$FAKE_FZF_RESPONSES"
  run_pty $'y\n' myrepo
  if grep -q 'kill-session -t =myrepo' "$FAKE_TMUX_LOG"; then
    ok p1
  else
    fail p1 "no kill-session; log=[$(cat "$FAKE_TMUX_LOG")]"
  fi
  teardown
}

# ---- p2: ctrl-x, answer n → NO kill ----
p2() {
  [[ $PTY_OK -eq 1 ]] || { fail p2 "no pty driver — STOP per plan 01"; return; }
  setup
  printf 'ctrl-x\tmyrepo\nABORT\n' >"$FAKE_FZF_RESPONSES"
  run_pty $'n\n' myrepo
  if ! grep -q 'kill-session' "$FAKE_TMUX_LOG"; then
    ok p2
  else
    fail p2 "unexpected kill; log=[$(cat "$FAKE_TMUX_LOG")]"
  fi
  teardown
}

# ---- p3: ctrl-r + new name → rename-session ----
p3() {
  [[ $PTY_OK -eq 1 ]] || { fail p3 "no pty driver — STOP per plan 01"; return; }
  setup
  printf 'ctrl-r\tmyrepo\nABORT\n' >"$FAKE_FZF_RESPONSES"
  run_pty $'renamed\n' myrepo
  if grep -q 'rename-session -t =myrepo renamed' "$FAKE_TMUX_LOG"; then
    ok p3
  else
    fail p3 "no rename; log=[$(cat "$FAKE_TMUX_LOG")]"
  fi
  teardown
}

# ---- p4: launcher key (ctrl-a) on the new-session row arms `claude` ----
p4() {
  setup
  printf 'ctrl-a\tnew session\n\tmyrepo\n' >"$FAKE_FZF_RESPONSES"
  run_pty '' myrepo
  if grep -qE 'send-keys -t myrepo-2 claude( C-m)?$' "$FAKE_TMUX_LOG" \
     && grep -q 'new-session -d -s myrepo-2' "$FAKE_TMUX_LOG"; then
    ok p4
  else
    fail p4 "no armed claude create; log=[$(cat "$FAKE_TMUX_LOG")]"
  fi
  teardown
}

# ---- p5: launcher key on an existing-session row is ignored (reload, no attach) ----
p5() {
  setup
  printf 'ctrl-a\tmyrepo\nABORT\n' >"$FAKE_FZF_RESPONSES"
  run_pty '' myrepo
  if ! grep -qE 'attach -t' "$FAKE_TMUX_LOG" \
     && ! grep -qE 'kill-session|rename-session|new-session' "$FAKE_TMUX_LOG"; then
    ok p5
  else
    fail p5 "unexpected action; log=[$(cat "$FAKE_TMUX_LOG")]"
  fi
  teardown
}

export TEST_TMPDIR_ROOT="${TMPDIR:-/tmp}"
if [[ $PTY_OK -ne 1 ]]; then
  printf 'PTY-UNAVAILABLE: /dev/tty cannot be fed here; p1-p3 will fail (STOP per plan 01).\n' >&2
fi
set +e
p1; p2; p3; p4; p5
exit $FAIL
```

**Verify**: `bash -n tests/test-picker.sh` → exit 0, no output.

### Step 4: Run the new test in isolation

```bash
bash tests/test-picker.sh
```

**Verify**: output is exactly

```
ok p1
ok p2
ok p3
ok p4
ok p5
```

and exit status 0 (`echo $?` → `0`).

If instead you see `FAIL p1 … no pty driver` (and the `PTY-UNAVAILABLE:` notice
on stderr), that is the documented STOP condition — go to STOP conditions.

### Step 5: Run the full suite

```bash
bash tests/run.sh
```

**Verify**: every line is `ok …` (including the new `ok p1`…`ok p5`), no `FAIL`
lines, exit status 0. The pre-existing tests (`install.sh`, `m1`–`m16`,
`t1`–`t35`, `f1`–`f7`) must still all pass — the new fake `fzf` is inert unless
`FAKE_FZF_RESPONSES`/`FAKE_FZF_COUNTER` are set, and `bin/mossferry` never invokes
`fzf` locally (its only reference is a remote `ssh "$host" command -v fzf` doctor
check), so `tests/test-mossferry.sh` is unaffected.

## Test plan

New file `tests/test-picker.sh`, cases (all drive the **real** `bin/repo-session`
as a subprocess via a pty, with `tests/fake-tmux` as `REPO_SESSION_TMUXBIN` and
`tests/fake-bin/fzf` on `PATH`):

- **p1** — ctrl-x on a live session row, answer `y` at the `[y/N]` prompt →
  asserts `kill-session -t =myrepo` is logged (the kill fired).
- **p2** — ctrl-x, answer `n` → asserts NO `kill-session` logged (kill declined).
- **p3** — ctrl-r, type a new name → asserts `rename-session -t =myrepo renamed`
  logged.
- **p4** — launcher key `ctrl-a` on the `➕ new session…` row → asserts the new
  session is created with the armed command: `new-session -d -s myrepo-2` **and**
  `send-keys -t myrepo-2 claude` (default `ctrl-a:claude`). This case exercises
  the second (sub-picker) fzf call.
- **p5** — launcher key `ctrl-a` on an existing-session row → asserts it is
  ignored (list reload, then ABORT): NO `attach -t`, NO
  `kill-session`/`rename-session`/`new-session` logged.

Structural pattern: model after `tests/test-repo-session.sh` (`ok`/`fail`,
`setup`/`teardown` with temp `HOME`, `tXX` functions run at the bottom).

Verification: `bash tests/test-picker.sh` → `ok p1`…`ok p5`; `bash tests/run.sh`
→ all pass including the 5 new cases.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n tests/fake-bin/fzf` exits 0.
- [ ] `bash -n tests/test-picker.sh` exits 0.
- [ ] `test -x tests/fake-bin/fzf` succeeds (stub is executable).
- [ ] `bash tests/test-picker.sh` prints `ok p1`…`ok p5` and exits 0.
- [ ] `bash tests/run.sh` exits 0 with no `FAIL` lines (all pre-existing tests
      still pass).
- [ ] Only `tests/fake-bin/fzf` and `tests/test-picker.sh` are added; `git
      status` shows no other modified files (in particular `bin/repo-session`
      unchanged).
- [ ] `plans/README.md` row updated **if that file exists**.

## STOP conditions

Stop and report back (do not improvise) if:

- **The pty feasibility gate fails** — `printf 'X\n' | script -qec 'read -r v
  </dev/tty; [ "$v" = X ]' /dev/null` does not print `0`, OR `bash
  tests/test-picker.sh` reports `FAIL p1/p2/p3 … no pty driver` /
  `PTY-UNAVAILABLE`. This means the current picker's ctrl-x/ctrl-r confirm reads
  bind `/dev/tty` in a way *your* harness cannot feed (no util-linux `script`, or
  a `script` variant like macOS's that does not forward piped stdin to the pty).
  **Do NOT edit `bin/repo-session` to work around it.** Report the exact blocker
  (which tool is missing / how the probe failed). This directly informs plan 03,
  which should make kill/rename reachable as testable subcommands (e.g. a
  `--kill`/`--rename` dispatch or a `--bind execute(...)` path) instead of
  `/dev/tty` line-reads — at which point p1/p2/p3 can be rewritten to drive that
  subcommand without a pty.
- **`bin/repo-session` has drifted** — the drift-check `git diff --stat
  88cd1f4..HEAD -- bin/repo-session` shows changes and the live dispatch code no
  longer matches the "Current state" excerpt (e.g. the `--expect` two-line
  contract changed, `picker_kill`/`picker_rename` renamed, or the `new_label`
  string changed). Report the mismatch — the shipped stub/tests assume the
  quoted behavior.
- **p4 fails specifically because `FERRY_LAUNCHERS` no longer defaults to
  `ctrl-a:claude`** (check `bin/repo-session:136`). Report; do not hardcode a
  different launcher into the test without confirming the default.
- Any verification fails twice after a reasonable fix attempt.
- A fix appears to require touching an out-of-scope file (especially
  `bin/repo-session`).

## Maintenance notes

For whoever owns this after the change lands:

- **Plans 03/04/05 will rewrite `run_picker` to `fzf --bind` / reload actions.**
  When that happens, these characterization tests MUST be updated in lockstep:
  the fake `fzf` will then also need to honor `--bind`/`reload` actions (today it
  only implements the `--expect` two-line contract via `FAKE_FZF_RESPONSES`), and
  the `/dev/tty` pty machinery in p1/p2/p3 may be replaced by driving the new
  kill/rename subcommand directly. Treat any change to the fzf invocation in
  `bin/repo-session` as a signal to revisit `tests/fake-bin/fzf`.
- **The fake `fzf` lives in the shared `tests/fake-bin/`** (alongside
  `ssh`/`mosh`, which `tests/test-mossferry.sh` puts on `PATH`). It is inert
  unless `FAKE_FZF_RESPONSES` is set, and the client never calls `fzf` locally,
  so it does not affect the mossferry tests today. If a future client change adds
  a local `fzf` call, revisit that assumption.
- **Reviewer scrutiny**: confirm the tests assert against `$FAKE_TMUX_LOG`
  argv (behavioral), not against picker stdout; confirm p5's "no attach"
  assertion matches `attach -t` (not bare `attach`, which collides with the
  `#{session_attached}` format string); confirm the counter/responses files are
  reset per case (`setup` does `rm -f "$FAKE_FZF_COUNTER"` and rewrites
  `$FAKE_FZF_RESPONSES`).
- **Deferred out of this plan**: coverage of the esc/quit (exit 130) path as an
  explicit assertion, and of the no-launcher sub-picker single-line pickfile
  format (the shipped stub always emits the two-line `--expect` shape, which is
  correct for every case here because all use the default launchers). Add these
  when plan 03 reshapes the loop.
```