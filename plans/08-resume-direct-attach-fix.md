# Plan 08: Fix documented `ferry <host> --resume N|name` direct attach (broken by client pre-validation)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index (or `plans/README.md` does not exist — then skip it, do
> not create one).
>
> **Drift check (run first)**: `git diff --stat 88cd1f4..HEAD -- bin/mossferry tests/test-mossferry.sh`
> If either in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

The README/`--help` documents `ferry <host> --resume syndcast-2` and
`ferry <host> --resume 2` as the direct "attach this exact session by name or
index" shortcut. The remote brain (`bin/repo-session`) implements this
correctly. But the **local client** (`bin/mossferry`) mis-parses the argument:
it treats the token *after* `--resume` as a **repo** and pre-validates it over
ssh (`repo-session --validate <token>`). On a real host that validation fails
with `no repo 'syndcast-2' …` and the client returns 1 **before ever
launching mosh** — so the documented feature is dead from the client. Only the
bare `--resume` (picker) and repo-scoped forms (`repo --resume`) work today.

After this plan lands, `ferry host --resume <name>` and `ferry host --resume <N>`
reach the mosh launch with the argument intact (no spurious `--validate`),
while every repo-scoped form still pre-validates the repo locally so genuine
repo typos are still caught before connecting.

Note on why the bug is latent in the test suite: the fake `ssh`
(`tests/fake-bin/ssh`) *passes* `--validate` by default (exit 0 unless
`FAKE_SSH_VALIDATE_EXIT` is set), so under the fakes the mosh launch still
happens even today — the defect is the **presence of the spurious `--validate`
ssh call**, which errors on a real host. The new tests assert the *absence* of
that call, which is the real defect.

## Current state

Files involved:

- `bin/mossferry` — LOCAL client. Two functions are relevant:
  - `repo_token_from_args()` (lines 553–569) — returns the "repo" token from the
    arg list. The root cause: it returns the first non-flag token, so the value
    following `--resume` is wrongly returned as the repo.
  - `launch_remote()` (lines 571–610) — pre-scans for `-h/--help` and `--list/-l`
    (special-cased before repo handling), then calls `repo_token_from_args`; if
    the result is non-empty it pre-validates the repo over ssh, else it goes
    straight to mosh.
- `bin/repo-session` — REMOTE brain. Its `--resume` handling (lines 830–835 and
  929–954) is **correct** and OUT OF SCOPE — do not touch it. It is quoted here
  only so you understand the intended end-to-end behavior.
- `README` / `--help` doc lines (`bin/mossferry` lines 266–267) — the documented
  contract this plan restores. Do not change them.

### Root cause — `bin/mossferry` lines 553–569 (verbatim today):

```bash
# First non-flag token after host is the repo (stops at `--`).
# Empty when bare picker / flag-only / cmd-only.
repo_token_from_args() {
  local a
  for a in "$@"; do
    if [[ "$a" == "--" ]]; then
      return 0
    fi
    case "$a" in
      -*) continue ;;
      *)
        printf '%s\n' "$a"
        return 0
        ;;
    esac
  done
}
```

For `--resume syndcast-2` this loop skips `--resume` (matches `-*`, continue),
then returns `syndcast-2` — the resume target — as if it were a repo.

### Consumer — `bin/mossferry` `launch_remote`, lines 580–608 (verbatim today):

```bash
  for a in "$@"; do
    case "$a" in
      -h|--help)
        usage
        return 0
        ;;
    esac
  done

  for a in "$@"; do
    case "$a" in
      --list|-l)
        ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
        return $?
        ;;
    esac
  done

  repo="$(repo_token_from_args "$@")"
  if [[ -n "$repo" ]]; then
    val_out="$(ssh "$host" "$FERRY_REMOTE_BIN" --client-version "$ver" --validate "$repo" 2>&1)" || val_rc=$?
    if [[ $val_rc -ne 0 ]]; then
      [[ -n "$val_out" ]] && printf '%s\n' "$val_out" >&2
      return 1
    fi
  fi

  mosh --server="MOSH_SERVER_NETWORK_TMOUT=${FERRY_SERVER_TIMEOUT} mosh-server" \
    "$host" -- "$FERRY_REMOTE_BIN" --client-version "$ver" "$@"
  return $?
```

Note: after a successful (or skipped) validation, mosh is launched with the
**original `"$@"`** (not the repo token), so fixing the token function is
sufficient — `launch_remote` itself needs no change.

### Doc contract — `bin/mossferry` lines 266–267 (verbatim, DO NOT edit):

```
  --resume [N|name]  no arg -> session picker; N -> the Nth session;
                     name -> attach that exact session (e.g. --resume syndcast-2)
```

### Remote brain (correct; OUT OF SCOPE) — `bin/repo-session` lines 830–835:

```bash
  while (( $# )); do
    case "$1" in
      --new)              fresh=1; shift ;;
      --list|-l)          list=1; shift ;;
      --resume|-R)        wantpick=1
                          if [[ -n "${2:-}" && "${2:-}" != -* ]]; then pick="$2"; shift 2; else shift; fi ;;
```

And `bin/repo-session` lines 929–954 (the direct-attach dispatch):

```bash
  # --resume with N or name (bare --resume falls through to picker later)
  if (( wantpick )) && [[ -n "$pick" ]]; then
    if [[ "$pick" =~ ^[0-9]+$ ]]; then
      if [[ -n "$repo" ]]; then
        mapfile -t sessions < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
          | grep -E "^${repo}(-[0-9]+)?$" | sort -V)
      else
        mapfile -t sessions < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null | sort -V)
      fi
      local target="${sessions[$((pick-1))]:-}"
      if [[ -z "$target" ]]; then
        echo "no session #$pick${repo:+ for '$repo'}. available:" >&2
        local i=1 s
        for s in "${sessions[@]}"; do echo "  $i) $s" >&2; ((i++)) || true; done
        exit 1
      fi
      exec "$TMUXBIN" attach -t "$target"
    else
      if "$TMUXBIN" has-session -t "=$pick" 2>/dev/null; then
        exec "$TMUXBIN" attach -t "=$pick"
      fi
      echo "no session named '$pick'. available:" >&2
      "$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null | sort -V | sed 's/^/  /' >&2
      exit 1
    fi
  fi
```

This confirms: the remote brain already treats the token after `--resume` as an
index (`N`) or session name (`name`), scoping to `repo` only when a repo appeared
**before** `--resume` (the `repo --resume …` form). The client must therefore
NOT treat that token as a repo.

### Repo conventions that apply here (from repo `CLAUDE.md` invariants)

- Both scripts run under `set -u` (unbound-variable errors are fatal), `set -e`
  is OFF. Guard array element reads with `:-` defaults (this plan's fix uses
  `${args[$((i+1))]:-}`), and never expand `${arr[@]}` unguarded — see invariant
  #2. The fixed function must not introduce an unbound-variable error when called
  with zero args.
- `bin/mossferry` must run on **bash 3.2** (macOS) as well as Linux. The fix uses
  only bash-3.2-safe constructs: `local x=("$@")`, `${#x[@]}`, arithmetic
  `(( … ))`, and `${x[$((i))]:-}`. Do NOT use `mapfile`, `${x:offset}` slicing,
  or `[[ =~ ]]` on the token here.
- Non-TTY output is byte-stable and asserted by tests (invariant #3). This fix is
  **control-flow only** — it changes which ssh/mosh calls happen, not any printed
  token. Do not add or change any user-facing string. Keep the existing repo-typo
  error path (`no repo '…'`, surfaced from the remote `--validate`) untouched.
- `bin/mossferry` can be sourced as a library with `FERRY_LIB=1` (guard at line
  647) to unit-test its functions without running `main`.

## Commands you will need

| Purpose            | Command                                                                 | Expected on success                         |
|--------------------|-------------------------------------------------------------------------|---------------------------------------------|
| Syntax check       | `bash -n bin/mossferry`                                                  | exit 0, no output                           |
| Lint               | `shellcheck bin/mossferry`                                               | exit 0 (honor existing `# shellcheck disable=` directives) |
| Unit (sourced)     | `FERRY_LIB=1 bash -c 'source ./bin/mossferry; …'` (see Step 1)           | prints the expected token                   |
| Full test suite    | `bash tests/run.sh`                                                      | all tests print `ok …`; exit 0              |
| Just client tests  | `bash tests/test-mossferry.sh`                                           | `ok m1` … `ok m20`; exit 0                  |

(Run all commands from the repository root. VERSION is `2.6.0` at this commit;
tests derive it dynamically from the `VERSION` file — never hardcode it in tests.)

## Suggested executor toolkit

- `shellcheck` is already on PATH in this environment; run it after editing.
- No external skills required. This is a small, self-contained bash change.

## Scope

**In scope** (the only files you may modify):

- `bin/mossferry` — replace the body of `repo_token_from_args()` (lines 553–569).
- `tests/test-mossferry.sh` — add tests `m17`–`m20` before the final
  `if [[ $fail -ne 0 ]]` block.

**Out of scope** (do NOT touch, even though they look related):

- `bin/repo-session` — its `--resume` logic is already correct. Changing it is
  wrong and risks breaking the atomic-claim / picker paths.
- `launch_remote()` in `bin/mossferry` — fixing `repo_token_from_args` is
  sufficient; do NOT add a `--resume` branch to the pre-scan loops (that would
  either lose local repo-typo validation for `repo --resume`, or duplicate logic).
- The `--resume` doc lines (`bin/mossferry` 266–267) and any printed string.
- `lib/green-ui.sh`, `install.sh`, any other file.

## Git workflow

- Branch: `advisor/08-resume-direct-attach-fix` (create it; do not work on `main`).
- Commit style: conventional commits (repo uses e.g. `chore(demo): …`,
  `fix: …`). Suggested message:
  `fix(client): don't pre-validate the --resume N|name value as a repo`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Fix `repo_token_from_args` so the `--resume`/`-R` value is not treated as a repo

In `bin/mossferry`, replace the **entire** current function body (lines 553–569,
quoted verbatim under "Current state") with the version below. The change:
iterate by index; when the current token is `--resume` or `-R`, skip its optional
value token (the `N|name`) too — because that value is a resume target, not a
repo. Everything else (first non-flag token wins, `--` stops the scan) is
preserved.

Target code:

```bash
# First non-flag token after host is the repo (stops at `--`).
# Empty when bare picker / flag-only / cmd-only.
# The value following --resume/-R (N|name) is a resume target, NOT a repo,
# so it is skipped — otherwise `ferry host --resume syndcast-2` would try to
# pre-validate "syndcast-2" as a repo and fail (see plan 08).
repo_token_from_args() {
  local args=("$@")
  local n=${#args[@]}
  local i=0 a next
  while (( i < n )); do
    a="${args[$i]}"
    if [[ "$a" == "--" ]]; then
      return 0
    fi
    case "$a" in
      --resume|-R)
        next="${args[$((i+1))]:-}"
        if [[ -n "$next" && "$next" != -* ]]; then
          i=$((i+2))
        else
          i=$((i+1))
        fi
        continue
        ;;
      -*) i=$((i+1)); continue ;;
      *)  printf '%s\n' "$a"; return 0 ;;
    esac
  done
}
```

Why each shape is correct after this change (all verified against the parser):

| Client args              | Returned token | Effect                                             |
|--------------------------|----------------|----------------------------------------------------|
| `--resume syndcast-2`    | *(empty)*      | no validate → mosh with `--resume syndcast-2` ✓ FIX |
| `--resume 2`             | *(empty)*      | no validate → mosh with `--resume 2` ✓ FIX          |
| `-R 2`                   | *(empty)*      | no validate → mosh with `-R 2` ✓ FIX                |
| `--resume` (bare)        | *(empty)*      | picker, unchanged ✓                                 |
| `--resume goodrepo`      | *(empty)*      | name form: attach session `goodrepo`, not a repo ✓  |
| `goodrepo --resume`      | `goodrepo`     | repo-scoped picker: validate `goodrepo` ✓           |
| `goodrepo --resume 2`    | `goodrepo`     | Nth session of `goodrepo`: validate `goodrepo` ✓    |
| `--resume 2 repo`        | `repo`         | Nth session scoped to `repo`: validate `repo` ✓     |
| `typoo --resume`         | `typoo`        | still validates → still errors on real host ✓       |
| `repo`                   | `repo`         | unchanged regression guard ✓                        |

**Verify** (run each; confirm the bracketed output exactly):

```
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args --resume syndcast-2)"'   # → []
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args --resume 2)"'            # → []
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args -R 2)"'                  # → []
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args --resume goodrepo)"'     # → []
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args goodrepo --resume)"'     # → [goodrepo]
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args goodrepo --resume 2)"'   # → [goodrepo]
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args --resume 2 repo)"'       # → [repo]
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args typoo --resume)"'        # → [typoo]
FERRY_LIB=1 bash -c 'source ./bin/mossferry; printf "[%s]\n" "$(repo_token_from_args repo)"'                  # → [repo]
```

Then: `bash -n bin/mossferry` → exit 0, no output. And `shellcheck bin/mossferry`
→ exit 0 (if a *new* warning appears on your added lines, fix it; do not silence
pre-existing warnings that already had `# shellcheck disable=` directives).

### Step 2: Add regression tests `m17`–`m20` to `tests/test-mossferry.sh`

Insert the four blocks below **immediately before** the final tail of the file.
The current end of the file (verbatim) is:

```bash
# --- m16: mossferry --help contains MEDIUM hull line (ANSI-stripped) + usage text ---
{
  …
}

if [[ $fail -ne 0 ]]; then
  exit 1
fi
exit 0
```

Place the new blocks between the closing `}` of the `m16` block and the
`if [[ $fail -ne 0 ]]; then` line. They mirror the existing style (`m1`, `m10`,
`m11`): each runs `run_ferry`, scans `FAKE_NET_LOG` for the `mosh` / `--validate`
lines by basename, and calls `ok`/`FAIL`. Use `$VERSION` (already set at the top
of the file) — do not hardcode `2.6.0`.

```bash
# --- m17: ferry h --resume syndcast-2 → mosh w/ arg intact, NO spurious --validate ---
{
  name=m17
  unset FAKE_SSH_VALIDATE_EXIT || true
  outf="$tmpdir/m17.out" errf="$tmpdir/m17.err" logf="$tmpdir/m17.log"
  run_ferry "$outf" "$errf" "$logf" -- h --resume syndcast-2
  mosh_line="" has_validate=0
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == *"--validate"* ]] && has_validate=1
    base="${l%% *}"; base="${base##*/}"
    [[ "$base" == mosh ]] && mosh_line="$l"
  done <"$logf"
  expected_tail="mosh --server=MOSH_SERVER_NETWORK_TMOUT=86400 mosh-server h -- .local/bin/repo-session --client-version ${VERSION} --resume syndcast-2"
  if [[ $has_validate -eq 0 ]] && [[ "$mosh_line" == *"$expected_tail" ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  has_validate=%s mosh_line=%s\n' "$has_validate" "$mosh_line" >&2
  fi
}

# --- m18: ferry h --resume 2 → mosh w/ arg intact, NO spurious --validate ---
{
  name=m18
  unset FAKE_SSH_VALIDATE_EXIT || true
  outf="$tmpdir/m18.out" errf="$tmpdir/m18.err" logf="$tmpdir/m18.log"
  run_ferry "$outf" "$errf" "$logf" -- h --resume 2
  mosh_line="" has_validate=0
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == *"--validate"* ]] && has_validate=1
    base="${l%% *}"; base="${base##*/}"
    [[ "$base" == mosh ]] && mosh_line="$l"
  done <"$logf"
  expected_tail="mosh --server=MOSH_SERVER_NETWORK_TMOUT=86400 mosh-server h -- .local/bin/repo-session --client-version ${VERSION} --resume 2"
  if [[ $has_validate -eq 0 ]] && [[ "$mosh_line" == *"$expected_tail" ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  has_validate=%s mosh_line=%s\n' "$has_validate" "$mosh_line" >&2
  fi
}

# --- m19: ferry h goodrepo --resume → validate goodrepo THEN mosh (repo scope kept) ---
{
  name=m19
  unset FAKE_SSH_VALIDATE_EXIT || true
  outf="$tmpdir/m19.out" errf="$tmpdir/m19.err" logf="$tmpdir/m19.log"
  run_ferry "$outf" "$errf" "$logf" -- h goodrepo --resume
  has_validate=0 mosh_line=""
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == *"--validate"* && "$l" == *goodrepo* ]] && has_validate=1
    base="${l%% *}"; base="${base##*/}"
    [[ "$base" == mosh ]] && mosh_line="$l"
  done <"$logf"
  expected_tail="mosh --server=MOSH_SERVER_NETWORK_TMOUT=86400 mosh-server h -- .local/bin/repo-session --client-version ${VERSION} goodrepo --resume"
  if [[ $has_validate -eq 1 ]] && [[ "$mosh_line" == *"$expected_tail" ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  has_validate=%s mosh_line=%s\n' "$has_validate" "$mosh_line" >&2
  fi
}

# --- m20: ferry h typoo --resume (bad repo scope) → validate errs, no mosh, exit 1 ---
{
  name=m20
  outf="$tmpdir/m20.out" errf="$tmpdir/m20.err" logf="$tmpdir/m20.log"
  FAKE_SSH_VALIDATE_EXIT=1 run_ferry "$outf" "$errf" "$logf" -- h typoo --resume
  err="$(cat "$errf" 2>/dev/null || true)"
  has_validate=0 has_mosh=0
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == *"--validate"* ]] && has_validate=1
    base="${l%% *}"; base="${base##*/}"
    [[ "$base" == mosh ]] && has_mosh=1
  done <"$logf"
  if [[ $_exit -eq 1 ]] && [[ "$err" == *"no repo"* ]] && [[ $has_validate -eq 1 ]] && [[ $has_mosh -eq 0 ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  exit=%s has_validate=%s has_mosh=%s err=%s\n' "$_exit" "$has_validate" "$has_mosh" "$err" >&2
  fi
  unset FAKE_SSH_VALIDATE_EXIT || true
}
```

**Verify**: `bash -n tests/test-mossferry.sh` → exit 0. Then
`bash tests/test-mossferry.sh` → prints `ok m1` … `ok m20` (in particular
`ok m17`, `ok m18`, `ok m19`, `ok m20`) and exits 0.

> Sanity check that the tests actually catch the bug: if you temporarily revert
> Step 1, `m17` and `m18` must FAIL (they would see `has_validate=1`). Re-apply
> Step 1 before finishing. (This is a mental check — do not commit the revert.)

### Step 3: Run the full suite and lint

**Verify**:
- `bash tests/run.sh` → every test prints `ok …`; process exits 0.
- `bash -n bin/mossferry` → exit 0.
- `shellcheck bin/mossferry` → exit 0.
- `git status --porcelain` → only `bin/mossferry` and `tests/test-mossferry.sh`
  are modified (plus `plans/README.md` only if you updated an existing index).

## Test plan

- New tests in `tests/test-mossferry.sh` (model them after `m1`, `m10`, `m11`):
  - `m17` — **the bug fix**: `ferry h --resume syndcast-2` reaches mosh with
    `--resume syndcast-2` intact and produces NO `--validate` ssh call.
  - `m18` — index form: `ferry h --resume 2` reaches mosh with `--resume 2`
    intact and NO `--validate`.
  - `m19` — regression guard: `ferry h goodrepo --resume` still pre-validates
    `goodrepo` (repo-scoped) and then launches mosh with `goodrepo --resume`.
  - `m20` — typo still caught: `FAKE_SSH_VALIDATE_EXIT=1 ferry h typoo --resume`
    exits 1 with `no repo` on stderr and no mosh launch.
- Existing `m1`–`m16` must stay green (unchanged). In particular `m10`
  (`ferry h typoo` typo path) and `m11` (`goodrepo --primary` validate-then-mosh)
  prove the validation path is intact.
- Verification: `bash tests/run.sh` → all pass, including the 4 new tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/mossferry` exits 0.
- [ ] `shellcheck bin/mossferry` exits 0.
- [ ] The Step 1 sourced unit checks all print the bracketed expected values.
- [ ] `bash tests/test-mossferry.sh` prints `ok m17`, `ok m18`, `ok m19`,
      `ok m20` and exits 0.
- [ ] `bash tests/run.sh` exits 0 (whole suite green).
- [ ] `git status --porcelain` shows only `bin/mossferry` and
      `tests/test-mossferry.sh` modified (no other source/lib/test files).
- [ ] `plans/README.md` status row updated (only if that file already exists).

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `bin/mossferry` 553–569 or `launch_remote` 580–608, or the file
  tail of `tests/test-mossferry.sh` (the `m16` block + the `if [[ $fail -ne 0 ]]`
  tail), does not match the excerpts above — the codebase has drifted.
- Disambiguating `repo --resume N` from `--resume N` appears to require behavior
  the current parser can't express. (Per the verification table in Step 1 it does
  NOT: position decides — a non-flag token *before* `--resume` is the repo and is
  validated; the token *immediately after* `--resume` is the resume value and is
  skipped; `--resume N repo` still validates the trailing `repo`. If you observe
  any shape violating this table, STOP and report the exact args and observed
  token rather than guessing.)
- Any existing test `m1`–`m16` starts failing after your change — that means the
  fix touched byte-stable output or a validation path it should not have.
- `shellcheck` reports a *new* warning on your added lines that you cannot
  resolve without an out-of-scope change.

## Maintenance notes

For the owner of this code after the change lands:

- `launch_remote`'s two pre-scan loops (`bin/mossferry` ~580–596) are the
  canonical place to special-case *whole-launch* arg behaviors (they already
  handle `-h/--help` and `--list/-l`). This plan deliberately did NOT add a
  `--resume` case there — instead it fixed `repo_token_from_args` so the resume
  *value* is never mistaken for a repo, which is the narrower, position-correct
  fix and keeps local repo-typo validation working for every `repo --resume …`
  form. If a future flag also takes a following value that must NOT be validated
  as a repo (e.g. a new `--foo <value>`), extend the `--resume|-R` case in
  `repo_token_from_args` rather than adding a pre-scan branch.
- `-R` is the documented short alias for `--resume` in `bin/repo-session`
  (line 834). The client fix handles both spellings; if the alias is ever renamed
  on the remote, update the `case` label here to match.
- A reviewer should scrutinize: (1) no printed/non-TTY token changed (this is
  control-flow only); (2) the fixed function is bash-3.2-safe and `set -u`-safe
  (array reads use `${…:-}`); (3) the new tests assert *absence* of `--validate`
  (the real defect), not merely that mosh launched.
