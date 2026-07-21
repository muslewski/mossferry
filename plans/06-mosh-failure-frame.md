# Plan 06: Frame mosh connection failures with a mossferry error and a doctor pointer

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/mossferry tests/fake-bin/mosh tests/test-mossferry.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts below against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

The mosh launch (`launch_remote` in `bin/mossferry`) is the single most-hit
code path in the tool, and today it has the *worst* error clarity of any path.
When mosh fails — host unreachable, the mosh UDP port range firewalled,
`mosh-server` not installed on the remote, remote session limit reached — the
user sees only mosh's own raw diagnostic (or a bare nonzero exit) with **zero
mossferry framing** and **no hint that `ferry doctor` exists**. Meanwhile the
`update` and `doctor` subcommands are polished with framed, color-safe output.
This plan closes that gap: on a nonzero mosh exit, emit one framed mossferry
error line that names the host, the mosh exit code, and points the user at
`ferry doctor <host>` — while preserving mosh's own stderr and the exact exit
code returned to the caller. It is small, low-risk, and byte-safe because it
reuses the existing TTY-gated `_ferry_err` helper.

## Current state

Files involved:

- `bin/mossferry` — the LOCAL client. `launch_remote()` (starts line 574) is
  the function that runs mosh. The `_ferry_err()` helper (lines 102–108) is the
  standard framed-error emitter.
- `tests/fake-bin/mosh` — the fake mosh stub used by the client tests. It
  currently **always exits 0**, so there is no way to exercise a mosh failure
  yet. This must be extended (test scaffolding — in scope).
- `tests/test-mossferry.sh` — the client contract test suite (tests m1–m16).
  A new test (m17) goes here.

### Excerpt A — the mosh launch and its exit propagation (`bin/mossferry:606-610`)

```bash

  mosh --server="MOSH_SERVER_NETWORK_TMOUT=${FERRY_SERVER_TIMEOUT} mosh-server" \
    "$host" -- "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
  return $?
}
```

This is the tail of `launch_remote()`. `set -e` is OFF in this script, so a
failing mosh does **not** abort the function — control reaches `return $?`,
which propagates mosh's exit code up to `main` and out to the process exit.
`$host` is the function's first positional (declared `local host="$1"` at the
top of `launch_remote`, line 575). The function already declares several locals
at line 577 (`local ver a repo val_out val_rc=0`); you will add one more local
(`rc`) **inside the mosh block** below — do NOT edit line 577.

### Excerpt B — the framed-error helper (`bin/mossferry:101-108`)

```bash
# Client error line: always `mossferry:` prefix; red ✗ when TTY.
_ferry_err() {
  if ui_tty 2>/dev/null; then
    printf '%s%s%s mossferry: %s\n' "${UI_R-}" "${UI_ERR-✗}" "${UI_Z-}" "$*" >&2
  else
    printf 'mossferry: %s\n' "$*" >&2
  fi
}
```

Key facts you will rely on:
- `_ferry_err` writes to **stderr** (`>&2`), so it never pollutes stdout.
- It is already **TTY-gated**: on a TTY it prints a red `✗ … mossferry: <msg>`;
  on a non-TTY (pipe / CI / the test harness) it prints exactly
  `mossferry: <msg>\n` with no color/glyphs. This is what keeps the change
  byte-stable — you do NOT add any new TTY logic yourself; you just call it.
- Existing code already uses em dashes (`—`, U+2014) inside message strings
  (e.g. line 374: `"remote checkout is canonical (no upstream) — pull skipped"`),
  so the em dash in the new message is consistent with existing style and is
  lint-clean (an em dash inside a double-quoted string is valid bash regardless
  of whether `shellcheck` is available to confirm it).

### Excerpt C — the fake mosh stub, current (`tests/fake-bin/mosh`, full file)

```bash
#!/usr/bin/env bash
# Fake mosh: log invocation, exit 0.
printf '%s\n' "$0 $*" >> "${FAKE_NET_LOG:?FAKE_NET_LOG not set}"
exit 0
```

Because it hard-codes `exit 0`, the current suite can only test the success
path. Step 1 makes the exit code selectable via an env var, defaulting to 0 so
every existing test keeps passing.

### Repo conventions that apply here

- Non-TTY output is byte-stable and asserted by tests. Any NEW user-facing line
  must be emitted only through a TTY-gated path. Here that is satisfied by
  routing the message through `_ferry_err` (never a bare `printf` to stderr with
  color). Do not add color codes or glyphs directly.
- `set -u` is on: only reference variables you have assigned. `rc` is assigned
  before use; `$host` is already a set local.
- The test harness (`tests/test-mossferry.sh`) runs `bin/mossferry` as a
  subprocess with stderr redirected to a file (see `run_ferry`, lines 17–37),
  so `_ferry_err` takes the deterministic non-TTY branch: `mossferry: <msg>`.
- The established way to drive a fake-binary exit code in a single test is an
  env-var prefix on `run_ferry` followed by `unset` — see m10
  (`FAKE_SSH_VALIDATE_EXIT=1 run_ferry …`, lines 262–283) and m15
  (`FAKE_SSH_UPSTREAM_EXIT=1 run_ferry …`, lines 367–382). Model the new test on
  those.

## Commands you will need

| Purpose            | Command                                | Expected on success                     |
|--------------------|----------------------------------------|-----------------------------------------|
| Syntax check       | `bash -n bin/mossferry`                | exit 0, no output                       |
| Syntax check (fake)| `bash -n tests/fake-bin/mosh`          | exit 0, no output                       |
| Syntax check (test)| `bash -n tests/test-mossferry.sh`      | exit 0, no output                       |
| Lint (optional)    | `shellcheck bin/mossferry`             | exit 0, no findings — SKIP if not installed |
| Single suite       | `bash tests/test-mossferry.sh`         | every line `ok mN`, exit 0              |
| Full suite         | `bash tests/run.sh`                    | all tests pass, exit 0                  |

(Exact commands from this repo. **`shellcheck` is NOT guaranteed to be installed
in this environment** — `command -v shellcheck` may print nothing and running
`shellcheck` may exit 127 (`command not found`). Treat the Lint row as
**optional**: run it only if `command -v shellcheck` succeeds, and **skip it if
shellcheck is absent — do NOT attempt to install shellcheck** (that is an
out-of-scope dependency). The required, always-available gates are `bash -n`,
`bash tests/test-mossferry.sh`, and `bash tests/run.sh`; `bash tests/run.sh`
does NOT depend on shellcheck (the `# shellcheck …` lines in the repo are inline
lint directives, not invocations). Honor any existing `# shellcheck disable=`
directives in the files.)

## Scope

**In scope** (the only files you may modify):
- `bin/mossferry` — **only** the mosh block inside `launch_remote()`
  (Excerpt A, lines 606–609). Nothing else in the file.
- `tests/fake-bin/mosh` — make the exit code selectable (Step 1).
- `tests/test-mossferry.sh` — add one new test, m17 (Step 3).

**Out of scope** (do NOT touch, even though they look related):
- `bin/mossferry` `cmd_doctor` / `cmd_update` and their output — a separate
  finding. This plan only *points at* doctor; it does not change it.
- The ssh **pre-validation** messaging (`bin/mossferry:598-605`, the
  `--validate` block that prints on a typo before mosh) — that is a distinct
  finding, not selected here. Do not add framing there.
- The `_ferry_err` helper itself (Excerpt B) — reuse it as-is; do not modify it.
- `bin/repo-session`, `lib/green-ui.sh`, `install.sh`, any other test file.
- The duplicated banner / path-resolver helpers — do NOT dedup them (they are
  intentionally duplicated across the two scripts).
- The success path (mosh exit 0), the `--list`/`-l` ssh short-circuit
  (lines 589–596), and the `-h`/`--help` short-circuit (lines 580–587) — leave
  all three byte-for-byte unchanged.

## Git workflow

- Branch: `advisor/06-mosh-failure-frame` (create off `main`; do not commit on
  `main` directly).
- One commit is fine for this small change; message style is conventional
  commits (recent log shows `chore(demo): …`, `feat: …`). Suggested:
  `feat(client): frame mosh connection failures and point at ferry doctor`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make the fake mosh honor a selectable exit code

Edit `tests/fake-bin/mosh`. Replace the entire file contents (Excerpt C) with:

```bash
#!/usr/bin/env bash
# Fake mosh: log invocation, exit per FAKE_MOSH_EXIT (default 0).
printf '%s\n' "$0 $*" >> "${FAKE_NET_LOG:?FAKE_NET_LOG not set}"
exit "${FAKE_MOSH_EXIT:-0}"
```

This preserves the default behavior (exit 0 when `FAKE_MOSH_EXIT` is unset), so
all existing m-tests still pass, while allowing a test to force a nonzero exit.
Keep the file executable (it already is; do not `chmod` it off).

**Verify**:
- `bash -n tests/fake-bin/mosh` → exit 0, no output.
- `bash tests/test-mossferry.sh` → every existing line prints `ok mN` (m1–m16),
  exit 0. (Confirms the default-0 behavior is unchanged.)

### Step 2: Frame the failure in `launch_remote`

Edit `bin/mossferry`. Find the exact three-line block from Excerpt A
(lines 607–609):

```bash
  mosh --server="MOSH_SERVER_NETWORK_TMOUT=${FERRY_SERVER_TIMEOUT} mosh-server" \
    "$host" -- "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
  return $?
```

Replace it with:

```bash
  local rc=0
  mosh --server="MOSH_SERVER_NETWORK_TMOUT=${FERRY_SERVER_TIMEOUT} mosh-server" \
    "$host" -- "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    _ferry_err "connection to $host failed (mosh exit $rc) — run: ferry doctor $host"
  fi
  return $rc
```

Notes for correctness:
- The message uses an em dash (`—`, U+2014) between the parenthetical and
  `run:`, matching the existing style at line 374. Copy it exactly.
- `_ferry_err` is emitted **after** mosh has already run, so mosh's own stderr
  is not swallowed — the framing appears after it.
- `return $rc` preserves mosh's exit code for the caller (`main` → process
  exit). Do not hard-code `return 1`.
- Do not touch the `-h`/`--help`, `--list`/`-l`, or ssh `--validate` blocks
  above this one.

**Verify**:
- `bash -n bin/mossferry` → exit 0, no output. **(Required gate.)**
- Optional lint — **skip entirely if shellcheck is absent; do NOT install it**:
  `command -v shellcheck >/dev/null && shellcheck bin/mossferry` → when
  shellcheck is present this exits 0 with no new findings; when `command -v
  shellcheck` prints nothing (shellcheck not installed here), the command
  short-circuits and you skip this check. A missing shellcheck is NOT a
  verification failure and must NOT be treated as a STOP condition.

### Step 3: Add test m17 — nonzero mosh exit is framed and the code is preserved

Edit `tests/test-mossferry.sh`. Insert the following block **after** the m16
block (which ends with its closing `}` near line 400) and **before** the final
`if [[ $fail -ne 0 ]]; then` block (lines 402–405):

```bash
# --- m17: mosh nonzero exit → framed mossferry error + preserved exit code ---
{
  name=m17
  outf="$tmpdir/m17.out" errf="$tmpdir/m17.err" logf="$tmpdir/m17.log"
  FAKE_MOSH_EXIT=23 run_ferry "$outf" "$errf" "$logf" -- h
  err="$(cat "$errf" 2>/dev/null || true)"
  if [[ $_exit -eq 23 ]] && [[ "$err" == *"run: ferry doctor"* ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  exit=%s err=%s\n' "$_exit" "$err" >&2
  fi
  unset FAKE_MOSH_EXIT || true
}
```

Why this shape:
- `-- h` is the bare-picker path (host `h`, no repo token). It skips ssh
  pre-validation (confirmed by m13, which asserts no `--validate` for `ferry h`)
  and goes straight to the mosh call, so the fake mosh's exit is what propagates.
- `FAKE_MOSH_EXIT=23` forces the stub added in Step 1 to exit 23. The assertion
  `$_exit -eq 23` proves the exit code is preserved end-to-end (mosh →
  `launch_remote` → `main` → process). Do not assert exit 1.
- `run_ferry` redirects stderr to `$errf` (non-TTY), so `_ferry_err` prints the
  plain `mossferry: …` form; asserting the `run: ferry doctor` substring is
  therefore stable and color-independent.
- The trailing `unset FAKE_MOSH_EXIT` mirrors m10/m15 so later tests are not
  affected.

**Verify**:
- `bash -n tests/test-mossferry.sh` → exit 0, no output.
- `bash tests/test-mossferry.sh` → prints `ok m17` (plus all of m1–m16), exit 0.

## Test plan

- New test **m17** in `tests/test-mossferry.sh`, covering the regression this
  plan fixes: a nonzero mosh exit must (a) surface a mossferry-framed line
  containing `run: ferry doctor`, and (b) preserve mosh's exact exit code (23).
- Structural pattern to copy: **m10** (lines 262–283) and **m15** (lines
  367–382) for the `FAKE_*_EXIT=… run_ferry … ; unset …` idiom; **m13** (lines
  331–343) confirms the `ferry h` path reaches mosh without pre-validation.
- Supporting scaffolding: Step 1's `FAKE_MOSH_EXIT` knob in
  `tests/fake-bin/mosh` (defaults to 0, so no existing test changes behavior).
- Verification: `bash tests/run.sh` → all tests pass including the new m17.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/mossferry` exits 0.
- [ ] `bash -n tests/fake-bin/mosh` exits 0.
- [ ] `bash -n tests/test-mossferry.sh` exits 0.
- [ ] Lint (**optional — only when shellcheck is installed**): if
      `command -v shellcheck >/dev/null` succeeds, then `shellcheck bin/mossferry`
      exits 0 with no new findings. If shellcheck is not installed (the case in
      this environment), this criterion is **N/A — skip it and do not install
      shellcheck**. It is NOT a required gate.
- [ ] `bash tests/test-mossferry.sh` prints `ok m17` and exits 0.
- [ ] `bash tests/run.sh` exits 0 (full suite green).
- [ ] `grep -n 'run: ferry doctor' bin/mossferry` returns exactly one match,
      inside `launch_remote`.
- [ ] `grep -n 'FAKE_MOSH_EXIT' tests/fake-bin/mosh tests/test-mossferry.sh`
      shows the knob in the stub and its use in m17.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row updated (unless a reviewer maintains it).

## STOP conditions

Stop and report back (do not improvise) if:

- The code at lines 606–609 of `bin/mossferry` or the full contents of
  `tests/fake-bin/mosh` does not match Excerpt A / Excerpt C (the codebase has
  drifted since this plan was written — the drift-check `git diff --stat`
  reported a change).
- `tests/fake-bin/mosh` cannot be made to return a chosen nonzero code from the
  `FAKE_MOSH_EXIT` env var (e.g. the stub is invoked in a way that discards the
  var), so m17 cannot force a nonzero mosh exit. Extending the stub is in scope;
  if that still does not work, STOP and report rather than restructuring the
  test harness.
- Adding m17 makes any existing test (m1–m16) fail — that means the default-0
  behavior of the stub was not preserved; STOP and re-check Step 1.
- The fix appears to require touching an out-of-scope file (e.g. `_ferry_err`,
  `cmd_doctor`, the `--validate` block, or `run.sh`).
- A verification command fails twice after a reasonable fix attempt.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- The message **intentionally** points at `ferry doctor <host>`. Plan 07 makes
  `doctor` more useful; do not remove or reword that pointer without updating
  plan 07's expectations. `ferry doctor <host>` is already a real, documented
  subcommand (usage line 292: `ferry doctor manjaro-remote`).
- If the mosh invocation in `launch_remote` is ever refactored (e.g. wrapped in
  a helper or given a retry loop), the `rc` capture + `_ferry_err` framing must
  move with it so the exit code stays exact and the failure stays framed.
- Reviewer should scrutinize: (1) that `return $rc` (not `return 1`) preserves
  mosh's code; (2) that the framing goes through `_ferry_err` (TTY-gated), not a
  raw colored `printf`, keeping non-TTY output byte-stable; (3) that
  `tests/fake-bin/mosh` still defaults to exit 0 so the rest of the suite is
  unaffected.
- Deferred out of this plan (separate findings): framing/clarity for the ssh
  pre-validation typo path, and any changes to `doctor`/`update` output.
