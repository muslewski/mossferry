# Plan 11: Remote-quote arguments on the ssh `--list`/`--validate` paths so names with spaces/metacharacters survive

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index (as of this writing `plans/README.md` does not exist; if
> it is still absent, skip that step).
>
> **Drift check (run first)**: `git diff --stat 88cd1f4..HEAD -- bin/mossferry tests/test-mossferry.sh`
> If either in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

On the **ssh** launch paths (`--list`/`-l` and the repo `--validate` pre-check),
`bin/mossferry` hands the user's arguments to `ssh` as separate words and lets
the **remote** shell re-word-split them. A repo/dir name containing a space or a
shell metacharacter is therefore mangled: `ferry host 'my repo' --list` sends
the wire command `… my repo --list`, so the remote sees `my` as the repo and
`repo` as a stray token — the wrong thing runs, silently. `$`, `;`, `*`, backticks
and globs would likewise be interpreted by the remote shell. Frequency is low
(repo directory names rarely contain spaces) but the behavior is unsafe and it is
**asymmetric** with the mosh path, whose wrapper already single-quotes arguments
correctly.

The remote brain (`bin/repo-session`) *does* validate repo names and rejects
spaces (`repo-session: invalid repo name 'has space'`, see
`bin/repo-session:419` `sanitize_repo_name` / used at `bin/repo-session:975`), but
that guard can only do the right thing if it receives the name **intact**. Today
the local mangling changes *which token* the remote validates before its guard
ever runs. Quoting each argument with `printf %q` on just these two ssh
invocations makes the remote receive byte-for-byte the same tokens the user
typed; plain names are unchanged, so nothing about normal usage moves.

## Current state

Relevant files:

- `bin/mossferry` — the LOCAL client. Shebang `#!/usr/bin/env bash`, `set -u` on,
  `set -e` OFF (`bin/mossferry:1-4`). The bug is in `launch_remote()` (defined at
  `bin/mossferry:574`). Two ssh invocations need quoting; a third mosh invocation
  in the same function is **already safe and out of scope** (see below).
- `tests/test-mossferry.sh` — client contract tests `m1`–`m16`. Runs `bin/mossferry`
  as a subprocess with `tests/fake-bin` first on `PATH` (fake `ssh` + `mosh`), and
  asserts against `FAKE_NET_LOG`, the log every fake network binary appends to.
- `tests/fake-bin/ssh` — the fake ssh. **It logs `printf '%s\n' "$0 $*"`** (line 4),
  i.e. it space-joins the argv it received into one log line. This is how a test
  observes exactly what argv `mossferry` handed to ssh.

### The two ssh calls to fix — `bin/mossferry:574-610` (`launch_remote`)

Function locals (`bin/mossferry:577`):

```bash
  local ver a repo val_out val_rc=0
```

The `--list`/`-l` branch (`bin/mossferry:589-596`) — **fix the ssh at line 592**:

```bash
  for a in "$@"; do
    case "$a" in
      --list|-l)
        ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
        return $?
        ;;
    esac
  done
```

The repo `--validate` pre-check (`bin/mossferry:598-605`) — **fix the ssh at line 600**:

```bash
  repo="$(repo_token_from_args "$@")"
  if [[ -n "$repo" ]]; then
    val_out="$(ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" --validate "$repo" 2>&1)" || val_rc=$?
    if [[ $val_rc -ne 0 ]]; then
      [[ -n "$val_out" ]] && printf '%s\n' "$val_out" >&2
      return 1
    fi
  fi
```

The mosh launch immediately after (`bin/mossferry:607-609`) — **DO NOT TOUCH**:

```bash
  mosh --server="MOSH_SERVER_NETWORK_TMOUT=${FERRY_SERVER_TIMEOUT} mosh-server" \
    "$host" -- "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
  return $?
```

The mosh path is separate and already safe (the mosh client wrapper single-quotes
arguments when handing them to `mosh-server`; the remote does not re-parse them).
A prior review finding to "fix" the mosh path was **rejected** for exactly this
reason. Leaving the two paths asymmetric is intentional — different transports.

### Repo convention: bash-3.2-safe arrays with the guarded expansion

`bin/mossferry` must run on stock macOS bash 3.2 (invariant #1) with `set -u`
(invariant #2). The established, invariant-blessed idiom for arrays in this file is
already present — mirror it exactly:

- Declare with compound assignment on its own line: `bin/mossferry:423`
  `  local fix_hints=()`
- Append: `bin/mossferry:509` `    fix_hints+=("run: ferry update ${host}")`
- Expand under `set -u` with the unbound-guard: `bin/mossferry:545`
  `    for h in "${fix_hints[@]+"${fix_hints[@]}"}"; do`

Use that same `"${arr[@]+"${arr[@]}"}"` guard form for the new array so an empty
arg list does not trip `set -u`.

### Verified `printf %q` behavior (why this is byte-stable)

`printf '%q'` escapes a token **only when needed**, so ordinary tokens pass
through unchanged and special ones become a single shell-safe word:

| Input token | `printf '%q'` output |
|-------------|----------------------|
| `--list` | `--list` |
| `2.6.0` | `2.6.0` |
| `.local/bin/repo-session` | `.local/bin/repo-session` |
| `goodrepo` | `goodrepo` |
| `typoo` | `typoo` |
| `my repo` | `my\ repo` |
| `a;b` | `a\;b` |
| `a*b` | `a\*b` |
| `$HOME` | `\$HOME` |

Because ssh concatenates its argv with single spaces and the remote shell parses
that string once, an escaped word like `my\ repo` re-parses on the remote back to
the single token `my repo` — faithful transmission with no double-processing.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 88cd1f4..HEAD -- bin/mossferry tests/test-mossferry.sh` | empty (no drift) |
| Syntax check | `bash -n bin/mossferry` | exit 0, no output |
| Lint | `shellcheck bin/mossferry` | exit 0, no output |
| Client tests only | `bash tests/test-mossferry.sh` | every line `ok m1`…`ok m17`, exit 0 |
| Full suite | `bash tests/run.sh` | exit 0 (no `FAIL` lines) |

(These are the exact commands this repo uses; the full suite was green at commit
`88cd1f4` before this change.)

## Scope

**In scope** (the only files you may modify):
- `bin/mossferry` — the two ssh invocations inside `launch_remote` (lines 592 and
  600) plus the function's local declarations (line 577).
- `tests/test-mossferry.sh` — add one new test (`m17`).

**Out of scope** (do NOT touch, even though they look related):
- The mosh launch at `bin/mossferry:607-609` — by-design safe, different transport.
- Any other ssh call in `bin/mossferry` — the `update` path (`bin/mossferry:345,354,360,376,392`)
  and the `doctor` path (`bin/mossferry:464-528`) invoke fixed, non-user-supplied
  commands (git subcommands, `cat`, `-G`, `command -v`); they carry no user
  free-text token and are not part of this finding.
- `bin/repo-session`, `lib/green-ui.sh`, `install.sh`, any other test file.
- `FERRY_REMOTE_BIN` and `$ver`: leave them unquoted. They are operator-controlled
  config / the tool's own version, not per-invocation user text, and quoting them
  is unnecessary for this fix (a defense-in-depth follow-up is noted in
  Maintenance). Quoting only the user args also keeps the fake-ssh log for normal
  names byte-identical.

## Git workflow

- Branch: `advisor/11-ssh-arg-quoting` (or the repo's branch convention if one is
  evident).
- One commit for the change; conventional-commit style matches this repo's log
  (e.g. `fix(mossferry): remote-quote args on ssh --list/--validate paths`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the array locals to `launch_remote`

In `bin/mossferry`, replace the function's local-declaration line
(`bin/mossferry:577`):

```bash
  local ver a repo val_out val_rc=0
```

with:

```bash
  local ver a repo val_out val_rc=0 x
  local qa=()
```

`x` is the per-token loop variable; `qa` is the quoted-args array declared on its
own line exactly like `local fix_hints=()` at `bin/mossferry:423`.

**Verify**: `bash -n bin/mossferry` → exit 0, no output.

### Step 2: Quote the user args on the `--list`/`-l` ssh call

Replace the `--list`/`-l` case body (`bin/mossferry:591-594`):

```bash
      --list|-l)
        ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
        return $?
        ;;
```

with:

```bash
      --list|-l)
        # Remote-quote each user arg so a name with a space or shell
        # metacharacter survives the REMOTE shell's re-word-splitting as one
        # token. printf %q escapes per-token; plain names pass through unchanged
        # (byte-stable). The mosh path below is intentionally left as-is.
        qa=()
        for x in "$@"; do qa+=("$(printf '%q' "$x")"); done
        ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" "${qa[@]+"${qa[@]}"}"
        return $?
        ;;
```

Notes for correctness:
- `qa=()` resets the array at branch entry; the branch `return`s immediately so the
  outer `for a` loop never re-enters it.
- Keep the `"${qa[@]+"${qa[@]}"}"` guard exactly as written (double-quoted, with the
  `+` unbound-guard) — it matches `bin/mossferry:545` and satisfies `set -u` when the
  arg list is empty.
- Do **not** switch to an unquoted `$qa` string; unquoted expansion would let the
  *local* shell re-split the escaped tokens and undo the escaping.

**Verify**: `bash -n bin/mossferry` → exit 0; `shellcheck bin/mossferry` → exit 0,
no output.

### Step 3: Quote the repo token on the `--validate` ssh call

Replace the `--validate` ssh line (`bin/mossferry:600`):

```bash
    val_out="$(ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" --validate "$repo" 2>&1)" || val_rc=$?
```

with:

```bash
    val_out="$(ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" --validate "$(printf '%q' "$repo")" 2>&1)" || val_rc=$?
```

Only the `"$repo"` token is wrapped in `printf '%q'`; `--validate` stays a standalone
argument so the remote (and the fake ssh, which extracts the repo token *after* a
standalone `--validate` arg) still parse it as before.

**Verify**: `bash -n bin/mossferry` → exit 0; `shellcheck bin/mossferry` → exit 0,
no output.

### Step 4: Confirm no regression on the existing client tests

Run the existing client suite before adding the new test, to confirm the change is
byte-stable for normal (no-space) names:

**Verify**: `bash tests/test-mossferry.sh` → prints `ok m1` … `ok m16`, exit 0.

(Reasoning it must stay green: for plain names `printf %q` is the identity, and the
fake ssh log is a `$*` space-join, so `m2` (ssh, no mosh), `m10` (`typoo` →
`--validate typoo` → fake ssh still prints `no repo 'typoo'`), `m11` (`goodrepo`
validate-then-mosh), `m12`/`m13` (no `--validate`) all produce byte-identical argv.)

### Step 5: Add test `m17` for a spaced name on both ssh paths

Append a new test block to `tests/test-mossferry.sh`, **after the `m16` block and
before** the final `if [[ $fail -ne 0 ]]; then exit 1; fi` / `exit 0` lines
(`tests/test-mossferry.sh:402-405`). Model it on `m2` (ssh/no-mosh),
`m10` (`FAKE_SSH_VALIDATE_EXIT`), and `m12` (log-substring assertions):

```bash
# --- m17: spaced name survives as ONE token on the ssh --list/--validate paths ---
{
  name=m17
  # (a) --list path: 'my repo' must reach the remote %q-escaped as a single token.
  outf="$tmpdir/m17a.out" errf="$tmpdir/m17a.err" logf="$tmpdir/m17a.log"
  run_ferry "$outf" "$errf" "$logf" -- h 'my repo' --list
  log_a="$(cat "$logf" 2>/dev/null || true)"
  ok_list=0
  # Fixed code logs the escaped token 'my\ repo'; the buggy code logged bare 'my repo'.
  [[ "$log_a" == *'my\ repo'* ]] && ok_list=1

  # (b) --validate path: spaced repo, validation forced to fail so no mosh runs.
  outf="$tmpdir/m17b.out" errf="$tmpdir/m17b.err" logf="$tmpdir/m17b.log"
  FAKE_SSH_VALIDATE_EXIT=1 run_ferry "$outf" "$errf" "$logf" -- h 'my repo'
  vline=""
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == *"--validate"* ]] && vline="$l"
  done <"$logf"
  ok_val=0
  [[ "$vline" == *'--validate my\ repo'* ]] && ok_val=1
  unset FAKE_SSH_VALIDATE_EXIT || true

  if [[ $ok_list -eq 1 && $ok_val -eq 1 ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  ok_list=%s ok_val=%s\n' "$ok_list" "$ok_val" >&2
    printf '  list-log=%s\n' "$log_a" >&2
    printf '  validate-line=%s\n' "$vline" >&2
  fi
}
```

Why this is a real regression guard: the assertion patterns are single-quoted so
the `\` is a **literal** backslash in the `[[ == ]]` glob. The fixed code produces
`my\ repo` (matches); the pre-fix code produced bare `my repo` with no backslash
(does not match → `FAIL m17`). Verified locally:
`[[ '…my\ repo --list' == *'my\ repo'* ]]` matches, `[[ '…my repo --list' == *'my\ repo'* ]]` does not.

**Verify**: `bash tests/test-mossferry.sh` → prints `ok m1` … `ok m17`, exit 0.

### Step 6: Run the full suite and lint

**Verify**:
- `shellcheck bin/mossferry` → exit 0, no output.
- `bash -n bin/mossferry` → exit 0.
- `bash tests/run.sh` → exit 0 (no `FAIL` lines anywhere).

## Test plan

- New test `m17` in `tests/test-mossferry.sh`, covering:
  - **--list path** (`ferry h 'my repo' --list`): the fake-ssh log contains the
    single escaped token `my\ repo` (the fix), which the buggy code did not emit.
  - **--validate path** (`FAKE_SSH_VALIDATE_EXIT=1 ferry h 'my repo'`): the ssh
    `--validate` log line contains `--validate my\ repo` (single escaped token),
    exit path returns before mosh.
- Structural pattern to follow: `m2` (ssh/no-mosh), `m10` (uses
  `FAKE_SSH_VALIDATE_EXIT`), `m12` (log-substring assertion). Reuse the existing
  `run_ferry` helper and `$tmpdir` exactly as the other blocks do.
- Regression coverage for byte-stability is already provided by the untouched
  `m2`, `m10`, `m11`, `m12`, `m13` (they assert normal-name argv is unchanged).
- Verification: `bash tests/test-mossferry.sh` → `ok m1`…`ok m17`; then
  `bash tests/run.sh` → exit 0.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/mossferry` exits 0.
- [ ] `shellcheck bin/mossferry` exits 0 with no output.
- [ ] `bash tests/test-mossferry.sh` prints `ok m17` (new) and `ok m1`…`ok m16`
      (unchanged), exit 0.
- [ ] `bash tests/run.sh` exits 0 with no `FAIL` lines.
- [ ] `git diff --stat 88cd1f4..HEAD` shows only `bin/mossferry` and
      `tests/test-mossferry.sh` changed — no other file (`git status`).
- [ ] The mosh launch at `bin/mossferry:607-609` is byte-for-byte unchanged
      (`git diff bin/mossferry` shows no hunk touching the `mosh --server=…` line).
- [ ] `plans/README.md` status row updated **if that file exists** (it is absent as
      of commit `88cd1f4`; skip if still absent).

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `bin/mossferry:577`, `:592`, or `:600` does not match the "Current
  state" excerpts (the file drifted since this plan was written).
- **`printf %q` is not portable on the target's bash.** Before trusting it, run:
  `printf '%q\n' 'my repo'` on the shell that will run the client/tests. Expected
  output is exactly `my\ repo`. If it prints anything else (e.g. a `$'…'` form, a
  single-quoted `'my repo'`, or an error), STOP and report — the escaping the
  remote parses, and the `m17` assertion, both assume the `my\ repo` backslash
  form. Do **not** silently swap in a different quoting scheme; a portable fallback
  is described in Maintenance for the reviewer to choose.
- `bash tests/test-mossferry.sh` shows any `FAIL` for a *pre-existing* test
  (`m1`–`m16`) after the change — that means byte-stability was broken; do not
  "fix" the assertion, report instead.
- The fix appears to require editing the mosh path, `bin/repo-session`, or any
  file outside the in-scope list.
- `shellcheck bin/mossferry` reports a new warning that cannot be resolved by
  matching the existing `"${arr[@]+"${arr[@]}"}"` idiom at `bin/mossferry:545`.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- **The asymmetry with the mosh path is intentional.** Only the ssh `--list` and
  `--validate` paths needed quoting; the mosh transport quotes on its own. If a
  future refactor unifies launch into a single code path, re-derive which transport
  is in play before dropping the quoting.
- **Portable fallback if `printf %q` proves unusable** on some target bash: replace
  each `$(printf '%q' "$x")` / `$(printf '%q' "$repo")` with a small POSIX
  single-quote wrapper — wrap the token in single quotes and replace every embedded
  `'` with `'\''`. Note this changes the *form* transmitted (e.g. `'my repo'`
  instead of `my\ repo`) and is applied even to plain names, so it is **not**
  byte-identical for normal names; `m17`'s expected substrings (`my\ repo`,
  `--validate my\ repo`) would have to change to the single-quoted form, and the
  loose `m2`/`m10`/`m11`/`m12` assertions would need re-confirmation. Prefer
  `printf %q` unless a concrete portability failure forces the swap.
- **Deferred (out of scope), defense-in-depth:** `FERRY_REMOTE_BIN` and `$ver` on
  these two ssh calls are still passed unquoted. They are operator-controlled
  config and the tool's own version string, not per-invocation user text, so the
  finding does not require quoting them; a follow-up could `printf %q` those too for
  belt-and-suspenders, but it adds no protection against the reported issue.
- **Reviewer, scrutinize:** (1) the `git diff` touches *only* lines 577, 591-594,
  and 600 in `bin/mossferry` plus the appended `m17` block — the `mosh` line must be
  untouched; (2) the `"${qa[@]+"${qa[@]}"}"` guard is present verbatim so an empty
  arg list does not trip `set -u`; (3) `m17` actually fails against the pre-fix code
  (a test that passes both ways guards nothing) — a quick way to confirm is to
  temporarily revert Step 2 and see `FAIL m17`.
