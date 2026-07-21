# Plan 09: Guard `--client-version` with a missing value against an infinite arg-parse loop

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 88cd1f4..HEAD -- bin/repo-session tests/test-repo-session.sh`
> If either in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

`bin/repo-session --client-version` invoked with the value omitted hangs forever
with no diagnostic. The arg-loop case does `shift 2`, but when only the flag
itself remains on the command line, `shift 2` fails (bash leaves the positional
parameters unchanged and returns nonzero; `set -e` is OFF so execution
continues), so `$#` never decreases and `while (( $# ))` spins forever. The
condition is only reachable by misuse — the real mossferry client always passes
a version (see `bin/mossferry:592,600,608`) — but an unbounded, silent hang is a
poor failure mode. The repo already has the correct pattern for value-taking
flags in the adjacent `--validate` case; this plan applies the same guard to
`--client-version` so a missing value is treated as "no version" instead of
underflowing the shift. No user-visible output changes for any valid invocation.

## Current state

Relevant files:

- `bin/repo-session` — the REMOTE brain script. The bug is in `main()`'s
  argument-parsing `while` loop (lines 830–855). `set -u` is on, `set -e` is
  off (invariant #2). `--client-version` is documented at `bin/repo-session:12`
  and `bin/repo-session:906`.
- `tests/test-repo-session.sh` — the repo-session test file. It runs
  `repo-session` as a subprocess against a fake tmux (`REPO_SESSION_TMUXBIN`)
  and asserts behavior. `t2`/`t3` already exercise `--client-version` with a
  value present.

### The buggy case — `bin/repo-session:841` (inside the arg loop, lines 830–855)

```bash
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
```

The line to change is exactly:

```bash
      --client-version)   client_version="${2:-}"; shift 2 ;;
```

The `--validate` case immediately below it is the **exemplar pattern** to copy:
it guards `${2:-}` for empty-or-flag before consuming `$2`, so it never runs
`shift 2` when `$2` is absent. The fix mirrors this (minus the error/exit —
`--client-version` should silently treat a missing value as "no version",
because the handshake is warn-only and never blocks; see below).

### Why "no version" is the correct fallback — `bin/repo-session:866-873`

```bash
  # Version handshake (warn only; never block).
  if [[ -n "$client_version" ]]; then
    local ov
    ov="$(own_version | tr -d '[:space:]')"
    if [[ -n "$ov" && "$client_version" != "$ov" ]]; then
      echo "mossferry: client ${client_version} / remote ${ov} — run 'ferry update'" >&2
    fi
  fi
```

The handshake only runs when `client_version` is non-empty, and only prints to
stderr. Setting `client_version=""` on a missing value cleanly skips it — no
output, no block. `client_version` is declared empty at `bin/repo-session:826`
(`local client_version="" validate=0 validate_arg=""`).

### Existing tests that must keep passing — `tests/test-repo-session.sh:56-85`

```bash
# ---- t2: client-version mismatch warns ----
t2() {
  setup
  local err
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|win|1w detached bash"
  err=$(bash "$RS" --client-version 0.0.1 --list 2>&1 >/dev/null)
  if [[ "$err" == *"run 'ferry update'"* ]]; then
    ok t2
  else
    fail t2 "stderr=[$err]"
  fi
  teardown
}

# ---- t3: matching client-version is silent ----
t3() {
  setup
  local err ver
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|win|1w detached bash"
  ver=$(cat "$VERSION_FILE")
  err=$(bash "$RS" --client-version "$ver" --list 2>&1 >/dev/null)
  if [[ "$err" != *"ferry update"* ]]; then
    ok t3
  else
    fail t3 "stderr unexpectedly contains update: [$err]"
  fi
  teardown
}
```

Both pass a **non-empty, non-flag** value (`0.0.1`, a real version). A version
string never begins with `-`, so after the fix these take the "value present"
branch and behave byte-for-byte identically. **This is the byte-stability
guarantee: only the missing-value / next-token-is-a-flag path changes.**

### Test harness facts you need

- `tests/test-repo-session.sh` head (lines 1–39) defines `ok()`, `fail()`,
  `setup()`, `teardown()`, and the globals `ROOT`, `RS="$ROOT/bin/repo-session"`,
  `FAIL`, `VERSION_FILE`. `setup()` creates a temp `HOME` with
  `~/.config/mossferry`, points `REPO_SESSION_TMUXBIN` at `tests/fake-tmux`,
  **unsets `FERRY_NO_FZF`**, and sets `FAKE_TMUX_SESSIONS=""`.
- With `FERRY_NO_FZF=1` and no sessions and stdin from `/dev/null`, a bare
  `repo-session` invocation reaches the numbered-menu picker
  (`bin/repo-session:688`), whose `read -r nsel` hits EOF immediately and does
  `exit 130` (`bin/repo-session:703-705`). So a fixed binary terminates
  promptly; an unfixed one hangs in the arg loop and never reaches the picker.
- The test-runner tail — `tests/test-repo-session.sh:826-834`:

```bash
export TEST_TMPDIR_ROOT="${TMPDIR:-/tmp}"
set +e
t1; t2; t3; t4; t5; t6; t7; t8; t9; t10; t11; t12
t13; t14; t15; t16; t17; t18; t19; t20
t21; t22; t23; t24; t25
t26; t27; t28
t29; t30; t31; t32
t33; t34; t35
exit $FAIL
```

  The last defined test function before this tail is `t32()`
  (`tests/test-repo-session.sh:798-824`). The definitions are **not** in strict
  numeric order (t33–t35 are defined earlier at lines 622–700), so append the
  new function right after `t32`'s closing brace and register it on the runner
  line.

## Commands you will need

| Purpose            | Command                                                              | Expected on success                    |
|--------------------|---------------------------------------------------------------------|----------------------------------------|
| Syntax check       | `bash -n bin/repo-session`                                           | exit 0, no output                      |
| Syntax check test  | `bash -n tests/test-repo-session.sh`                                 | exit 0, no output                      |
| Lint (soft gate)   | `shellcheck bin/repo-session`                                        | exit 0 (see drift note below)          |
| Full suite         | `bash tests/run.sh`                                                  | exit 0, every line `ok …`, no `FAIL`   |
| Single file        | `bash tests/test-repo-session.sh`                                    | every line `ok …`, no `FAIL`, exit 0   |
| Hang-repro (manual)| `FERRY_NO_FZF=1 timeout 5 bash bin/repo-session --client-version </dev/null; echo rc=$?` | `rc=130` (any value except `rc=124`)   |

**Drift note (verified during planning)**: `shellcheck` was **not installed**
on the planning machine (`which shellcheck` → not found), even though the
project convention treats it as available. If `shellcheck` is absent in your
environment, skip that gate — it is advisory. If present, it must pass (honor
the existing `# shellcheck disable=SC1090,SC1091` directive at
`bin/repo-session:16`; do not add new directives).

## Scope

**In scope** (the only files you may modify):
- `bin/repo-session` — the single `--client-version` case line (841).
- `tests/test-repo-session.sh` — add one test function and register it on the
  runner line.

**Out of scope** (do NOT touch, even though they look related):
- Any other case in the arg loop (`--resume`, `--validate`, `--new`, `--help`,
  `--primary`, `--resume-closed`, `--resume-or-new`, `--`, `-*`, `*`). The
  brief is CORRECTNESS-05, scoped to `--client-version` only. `--resume`
  already guards `${2:-}` correctly; `--validate` is the intentional exemplar.
- The version-handshake block (`bin/repo-session:866-873`) — unchanged.
- `bin/mossferry` — it always supplies a version; no change needed.
- Any non-TTY output token, banner, or chrome (invariant #3). This fix emits
  **no** new output.
- `lib/green-ui.sh`, `install.sh`, `tests/fake-tmux`, any other test file.

## Git workflow

- Branch: `advisor/09-client-version-arg-guard` (create off `main`; do not
  commit on `main` directly).
- Commit style follows the repo's conventional-commit history (e.g.
  `git log --oneline` shows `chore(demo): …`, `assets: …`). Suggested message:
  `fix(repo-session): guard --client-version missing value against arg-loop hang`.
- One commit for the whole change (source + test) is fine — it is small.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Guard the `--client-version` case against a missing/flag value

In `bin/repo-session`, replace the single line at 841:

```bash
      --client-version)   client_version="${2:-}"; shift 2 ;;
```

with a guarded block that mirrors the `--validate` case directly below it
(same 6/8/10-space indentation), but silently defaults to an empty version
instead of erroring:

```bash
      --client-version)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          client_version=""
          shift
        else
          client_version="$2"
          shift 2
        fi
        ;;
```

Rationale: when `$2` is absent (`${2:-}` empty) or looks like another flag
(`-*`), take `shift 1` (consuming only `--client-version`) and leave the
version empty — the handshake is skipped. Otherwise consume the value with
`shift 2` exactly as before. This removes the `shift 2` underflow that caused
the infinite loop. Do not touch any other case.

**Verify**:
- `bash -n bin/repo-session` → exit 0, no output.
- `FERRY_NO_FZF=1 timeout 5 bash bin/repo-session --client-version </dev/null; echo rc=$?`
  → prints `rc=130` (crucially **not** `rc=124`, which is the timeout-kill code
  that would mean it still hangs). Run this from the repo root.
- If `shellcheck` is installed: `shellcheck bin/repo-session` → exit 0.

### Step 2: Add a regression test that a bare `--client-version` does not hang

In `tests/test-repo-session.sh`, add a new test function `t36` immediately
after the closing `}` of `t32` (line 824) and before the
`export TEST_TMPDIR_ROOT=…` line (826). Model it on the existing subprocess
tests (`setup`/`teardown`, `bash "$RS" …`), and use a `timeout` so a
regression manifests as a bounded failure instead of hanging the whole suite:

```bash
# ---- t36: bare --client-version (no value) exits, does not hang ----
t36() {
  setup
  local rc
  export FERRY_NO_FZF=1
  export FAKE_TMUX_SESSIONS=""
  timeout 5 bash "$RS" --client-version </dev/null >/dev/null 2>&1
  rc=$?
  # 124 = timeout had to kill it → the arg loop hung (the bug). Any other
  # exit (e.g. 130 from the empty numbered-menu picker) means it terminated.
  if [[ $rc -ne 124 ]]; then
    ok t36
  else
    fail t36 "bare --client-version hung (rc=$rc, 124=timeout-kill)"
  fi
  teardown
}
```

Then register `t36` on the runner line. Change
`tests/test-repo-session.sh:833` from:

```bash
t33; t34; t35
```

to:

```bash
t33; t34; t35; t36
```

**Verify**:
- `bash -n tests/test-repo-session.sh` → exit 0, no output.
- `bash tests/test-repo-session.sh` → includes a line `ok t36`, no `FAIL`
  lines, exit 0.

### Step 3: Run the full suite

**Verify**:
- `bash tests/run.sh` → exit 0. Every emitted line starts with `ok `; there is
  no `FAIL` line anywhere in the output. `t2` and `t3` (the value-present
  `--client-version` tests) still print `ok`.

## Test plan

- **New test** — `t36` in `tests/test-repo-session.sh`:
  - Case covered: `repo-session --client-version` with the value omitted must
    terminate (regression for the infinite arg-loop). Enforced with
    `timeout 5` and an `rc -ne 124` assertion. `FERRY_NO_FZF=1` +
    `FAKE_TMUX_SESSIONS=""` + `</dev/null` route the fixed binary through the
    numbered-menu picker, which hits EOF and exits promptly.
  - Structural pattern to copy: `t2` (`tests/test-repo-session.sh:57-69`) for
    the `setup`/subprocess/`teardown` shape.
- **Existing tests as guardrails**: `t2` and `t3` prove the value-present path
  is unchanged (byte-stable).
- Verification: `bash tests/run.sh` → all pass, including the new `t36`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/repo-session` exits 0.
- [ ] `bash -n tests/test-repo-session.sh` exits 0.
- [ ] `FERRY_NO_FZF=1 timeout 5 bash bin/repo-session --client-version </dev/null` exits with a code that is **not** 124 (no hang).
- [ ] `bash tests/run.sh` exits 0; output contains `ok t36` and no `FAIL`.
- [ ] `shellcheck bin/repo-session` exits 0 **if** shellcheck is installed (else skipped).
- [ ] The `--client-version)` case is the only change in `bin/repo-session`; `git diff bin/repo-session` shows exactly the one case block replaced.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row for plan 09 updated (unless a reviewer maintains the index).

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows `bin/repo-session` or `tests/test-repo-session.sh`
  changed since `88cd1f4`, and the live code no longer matches the "Current
  state" excerpts (e.g. line 841 is not
  `--client-version)   client_version="${2:-}"; shift 2 ;;`).
- Any existing test (especially `t2`/`t3`) begins to FAIL after your change, or
  you find an existing test that deliberately invokes a **bare**
  `--client-version` with no value — reconcile before proceeding, because that
  would mean the old hang behavior was somehow depended upon.
- The hang-repro command prints `rc=124` after applying Step 1 (the fix did not
  take, or the picker path itself is blocking — investigate before adding the
  test).
- Applying the fix appears to require editing any out-of-scope file.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- The `--validate` case (`bin/repo-session:842-850`) is the **shared pattern**
  for any value-taking flag in this arg loop: guard `${2:-}` for empty-or-`-*`
  before consuming `$2`, so `shift 2` can never underflow. If a new
  value-taking flag is added later, copy this shape. `--validate` errors on a
  missing value; `--client-version` silently defaults to empty because its
  handshake is warn-only and non-blocking — pick the variant that matches the
  new flag's semantics.
- A reviewer should confirm the diff touches only the one case block and adds
  no new output (invariant #3: non-TTY output is byte-stable and asserted).
- Follow-up deliberately deferred: the other single-token flags in this loop
  (`--new`, `--primary`, etc.) do not take values, so they cannot underflow;
  they are intentionally out of scope here.
