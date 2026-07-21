# Plan 10: Harden session targeting — exact-match `has-session`/`attach`, literal repo-name filter, and `--resume 0` guard

> **Executor instructions**: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving to the next step. If anything
> in the "STOP conditions" section occurs, stop and report — do not improvise. When
> done, update the status row for plan 10 in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 88cd1f4..HEAD -- bin/repo-session tests/fake-tmux tests/test-repo-session.sh`
> If any of those changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.
>
> **Environment note**: `shellcheck` may be absent (it is not installed in the authoring
> environment and `tests/run.sh` does not call it). Treat every `shellcheck` step as
> skip-if-absent: `command -v shellcheck >/dev/null && shellcheck bin/repo-session`. A
> missing `shellcheck` is never a failure or a STOP condition. The required gates are
> `bash -n` and `bash tests/run.sh`.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW — additive precision; normal (non-overlapping, plain) names are unaffected.
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

Three real correctness bugs live in `bin/repo-session`'s session targeting. Each is silent —
no error, wrong result:

1. **Prefix-match take-over (CORRECTNESS-02).** Several `has-session -t "$session"` / `attach -t
   "$session"` calls omit tmux's `=` exact-match prefix, so tmux **prefix-matches**. With
   overlapping repo names (a repo `syn` while `syndcast` sessions exist), `ferry <host> syn -p`
   sees the primary as "already present" (a false prefix hit on `syndcast`), skips creation, and
   **attaches the wrong repo's session**. `_next_free_name` / `--new` similarly skip a
   legitimately-free name.
2. **Repo name treated as a regex (CORRECTNESS-04).** `grep -E "^${repo}(-[0-9]+)?$"` interpolates
   the repo name into a regex. `my.app` matches session `myXapp` (wrong repo's sessions
   listed/scoped); a name containing `[` produces an invalid regex, so grep errors and the repo
   silently appears to have **zero sessions**.
3. **`--resume 0` off-by-one (CORRECTNESS-08).** `ferry <host> --resume 0` passes the
   `^[0-9]+$` guard, then indexes `sessions[$((0-1))]` = `sessions[-1]` = the **last** session
   (bash 4) or an error (bash 3.2) — instead of the intended `no session #0`.

After this plan, session targeting is exact and metacharacter-safe, and `--resume 0` errors
cleanly. Blast radius is small but the failures are the worst kind: silent, wrong session.

## Current state

Facts and excerpts, inlined (confirm each against the live file):

- `bin/repo-session` — remote brain; the only file with the bugs (plus `tests/fake-tmux` and
  `tests/test-repo-session.sh` for coverage).

**CORRECTNESS-02 — bare (non-`=`) targets.** Sites that already do it right use `=`
(e.g. `_attach` at line 496 `attach -t "=$1"`, `create_home_session` at 443 `has-session -t
"=$session_name"`). The offending bare sites:

```
# _create_and_attach (502)
  exec "$TMUXBIN" attach -t "$session_name"
# _create_session_locked (477)
  if ! "$TMUXBIN" has-session -t "$session_name" 2>/dev/null; then
# _next_free_name (487)
  while "$TMUXBIN" has-session -t "$session" 2>/dev/null; do
# --resume-or-new fill (1010)
  while "$TMUXBIN" has-session -t "$target" 2>/dev/null; do target="$repo-$n"; ...
# --primary (1031, 1036)
  if ! "$TMUXBIN" has-session -t "$session" 2>/dev/null; then
  ...
  exec "$TMUXBIN" attach -t "$session"
# --new (1048, 1055)
  while "$TMUXBIN" has-session -t "$session" 2>/dev/null; do
  ...
  exec "$TMUXBIN" attach -t "$session"
# zero-session fast path (1067, 1072)
  if ! "$TMUXBIN" has-session -t "$session" 2>/dev/null; then
  ...
  exec "$TMUXBIN" attach -t "$session"
```

Line numbers are leads — **grep for the authoritative list** (Step 1). `new-session -d -s
"$name"` calls are NOT affected (the `-s` name is a literal, not a target lookup) and must NOT
get `=`.

**CORRECTNESS-04 — repo name as regex.** Four sites:

```
# build_session_rows (368)
    mapfile -t names < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
      | grep -E "^${filter}(-[0-9]+)?$" | sort -V)
# _list_repo_sessions (454)
  mapfile -t sessions < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
    | grep -E "^${repo}(-[0-9]+)?$" | sort -V)
# main --resume N, repo-scoped (933-934)
        mapfile -t sessions < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
          | grep -E "^${repo}(-[0-9]+)?$" | sort -V)
# main --list, repo-scoped (959-960)
      mapfile -t sessions < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
        | grep -E "^${repo}(-[0-9]+)?$" | sort -V)
```

The intended match is exactly: session name `== <repo>` OR `== <repo>-<digits>`.

**CORRECTNESS-08 — `--resume 0`.** In `main`, the `--resume N` branch:

```
# 930-945
  if (( wantpick )) && [[ -n "$pick" ]]; then
    if [[ "$pick" =~ ^[0-9]+$ ]]; then
      ...
      local target="${sessions[$((pick-1))]:-}"
      if [[ -z "$target" ]]; then
        echo "no session #$pick${repo:+ for '$repo'}. available:" >&2
        ...
```

`0` passes `^[0-9]+$` and yields index `-1`.

**Test harness facts** (see `tests/test-repo-session.sh` lines 1–60 for `ok`/`fail`,
`setup`/`teardown`, and the `tXX` pattern):
- Run repo-session as a subprocess with `REPO_SESSION_TMUXBIN="$ROOT/tests/fake-tmux"` and drive
  tmux state via `FAKE_TMUX_SESSIONS` (newline names), `FAKE_TMUX_META`, `FAKE_TMUX_WINDOWS`.
  `FAKE_TMUX_LOG` captures each tmux argv line.
- **`tests/fake-tmux` `has-session` currently strips a leading `=` and does EXACT compare**
  (lines ~102–117), so it does NOT model tmux prefix-matching — you must extend it (Step 1b) to
  exercise CORRECTNESS-02.
- Unit-call a function with `REPO_SESSION_LIB=1; source "$RS"` (see t8).

## Commands you will need

| Purpose   | Command                            | Expected on success |
|-----------|------------------------------------|---------------------|
| Syntax    | `bash -n bin/repo-session`         | exit 0              |
| Syntax    | `bash -n tests/fake-tmux tests/test-repo-session.sh` | exit 0 |
| Suite     | `bash tests/run.sh`                | exit 0, all tests pass |
| Lint (opt)| `command -v shellcheck >/dev/null && shellcheck bin/repo-session` | exit 0 or skipped |

## Scope

**In scope** (only these files):
- `bin/repo-session` — the three fixes.
- `tests/fake-tmux` — model prefix vs exact `has-session` so CORRECTNESS-02 is testable.
- `tests/test-repo-session.sh` — add regression tests for all three bugs.

**Out of scope** (do NOT touch):
- `new-session -d -s "$name"` targets — the `-s` argument is a literal session name, not a
  lookup; adding `=` there is wrong.
- The picker `--bind` / interactive loop (plans 01–05).
- `bin/mossferry` and any client-side arg handling (that is plan 08/11).
- The `_ferry_closest_repo` did-you-mean scorer (uses `==`/globs already; not a regex bug).

## Git workflow

- Branch: `advisor/10-session-target-matching` (or the repo's convention).
- Commit per step (three fixes + harness/tests), conventional-commit style — match `git log`
  (e.g. `fix(repo-session): exact-match session targets to stop cross-repo prefix hits`).
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Exact-match all session-target lookups (CORRECTNESS-02)

Find every `has-session -t` and `attach -t` whose target is a variable **without** a leading `=`:

```sh
grep -nE '(has-session|attach)[^\n]*-t "\$' bin/repo-session
grep -nE '(has-session|attach) -t "=' bin/repo-session   # the already-correct ones, for contrast
```

For each bare site, change `-t "$session"` → `-t "=$session"` (and the same for `$session_name`,
`$target`, `$1` used as a target). Do NOT alter `new-session -d -s "$name"` (creation, literal
name). Do NOT alter targets that already start with `=`.

**Verify**: `bash -n bin/repo-session` → exit 0. Then confirm no bare targets remain:
`grep -nE '(has-session|attach)[^\n]*-t "\$' bin/repo-session` → **no output** (every match now
uses `-t "=$..."`). Expected: 0 lines.

### Step 1b: Model prefix vs exact `has-session` in `tests/fake-tmux`

The stub must distinguish `-t name` (tmux prefix match) from `-t =name` (exact) so Step 1's fix
is testable. In the `has-session)` branch (~102–117), when the target starts with `=`, keep the
current exact compare; when it does NOT, match if any known session **equals the target OR begins
with the target** (prefix). Keep all other behavior identical.

**Verify**: with the stub, `FAKE_TMUX_SESSIONS=$'syndcast'`:
- `tests/fake-tmux has-session -t syn` → exit 0 (prefix match, old behavior)
- `tests/fake-tmux has-session -t =syn` → exit 1 (exact, no match)
- `tests/fake-tmux has-session -t =syndcast` → exit 0
Run these three inline (`FAKE_TMUX_SESSIONS=syndcast bash tests/fake-tmux has-session -t =syn; echo $?`).

### Step 2: Literal (non-regex) repo-name session filter (CORRECTNESS-04)

Replace the four `grep -E "^<name>(-[0-9]+)?$"` pipelines with a literal filter that accepts a
session name iff it equals `<repo>` or matches `<repo>-<digits>`, treating `<repo>` as a literal
string (no regex). Extract a small helper so all four sites share it, e.g.:

```sh
# Print stdin session names that belong to <repo>: exactly <repo> or <repo>-<digits>.
_filter_repo_sessions() {   # $1 = repo (literal)
  local repo="$1" s rest
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    if [[ "$s" == "$repo" ]]; then printf '%s\n' "$s"; continue; fi
    rest="${s#"$repo"-}"                       # strip literal "<repo>-" prefix
    [[ "$rest" != "$s" && "$rest" =~ ^[0-9]+$ ]] && printf '%s\n' "$s"
  done
}
```

Then each site becomes:
`... list-sessions -F '#{session_name}' 2>/dev/null | _filter_repo_sessions "$repo" | sort -V`.
Preserve the `sort -V` and the surrounding `mapfile`/assignment exactly so output order is
unchanged for normal names.

**Verify**: `bash -n bin/repo-session` → exit 0. Behavior check via the suite in Step 4. Confirm
no `grep -E "^` repo-name pipelines remain: `grep -nE 'grep -E "\^\$?\{?(filter|repo)' bin/repo-session`
→ no output.

### Step 3: Guard `--resume 0` (CORRECTNESS-08)

In `main`'s `--resume N` branch, add a lower-bound check so `0` (and any `< 1`) falls through to
the existing `no session #N` error instead of negative indexing. Change the numeric guard so the
index path runs only when `pick >= 1`:

```sh
if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 )); then
  ...
  local target="${sessions[$((pick-1))]:-}"
  ...
```

Ensure a `pick` of `0` (now failing the `>= 1` test) reaches the same "no session #$pick"
error path the empty-target case already prints (restructure minimally so both `0` and
out-of-range N produce that error; do not duplicate the message logic).

**Verify**: `bash -n bin/repo-session` → exit 0; behavior asserted in Step 4.

### Step 4: Regression tests

Add three tests to `tests/test-repo-session.sh` (model on the existing `tXX` + `setup`/`teardown`
+ `FAKE_TMUX_*` pattern; wire them into the file's runner list like the others):

- **CORRECTNESS-02**: `FAKE_TMUX_SESSIONS="syndcast"`, then run `bash "$RS" syn --primary` with a
  repo dir `syn` present under `FERRY_REPO_BASE`. Assert `FAKE_TMUX_LOG` shows a `new-session`
  for `syn` (creation happened — no false prefix hit) and the attach target is `=syn`, NOT
  `syndcast`. (Before the fix, no new-session and it attaches `syndcast`.)
- **CORRECTNESS-04**: create a repo dir `my.app`, `FAKE_TMUX_SESSIONS=$'myXapp\nmy.app'`, run
  `bash "$RS" my.app --list`. Assert the output lists `my.app` and does **not** list `myXapp`.
- **CORRECTNESS-08**: `FAKE_TMUX_SESSIONS=$'a\nb'`, run `bash "$RS" --resume 0`. Assert exit 1
  and stderr contains `no session #0`, and `FAKE_TMUX_LOG` shows **no** `attach`.

**Verify**: `bash tests/run.sh` → exit 0, all tests (existing + 3 new) pass.

## Test plan

- New tests: three cases above, in `tests/test-repo-session.sh`, following the structure of an
  existing test such as t6/t7 (subprocess run + `FAKE_TMUX_LOG` assertions).
- Harness change: `tests/fake-tmux` `has-session` now models prefix vs exact (Step 1b) — verify
  existing tests that call `has-session` still pass (they use exact `=` targets after Step 1, or
  bare targets the stub still handles).
- Full verification: `bash tests/run.sh` → all pass, including the 3 new tests. `bash -n` on all
  three touched files → exit 0. `command -v shellcheck >/dev/null && shellcheck bin/repo-session`
  → exit 0 or skipped.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -nE '(has-session|attach)[^\n]*-t "\$' bin/repo-session` returns **no** output (all targets exact).
- [ ] `grep -nE 'grep -E "\^' bin/repo-session` returns no repo-name-regex pipelines (the literal filter replaced them).
- [ ] `bash -n bin/repo-session tests/fake-tmux tests/test-repo-session.sh` → exit 0.
- [ ] `bash tests/run.sh` → exit 0; the 3 new tests exist and pass.
- [ ] `git status` shows only `bin/repo-session`, `tests/fake-tmux`, `tests/test-repo-session.sh` modified.
- [ ] `plans/README.md` status row for plan 10 updated.

## STOP conditions

Stop and report (do not improvise) if:

- Adding `=` to any target breaks an existing test that relied on prefix behavior — report which
  test; it means a caller depends on prefix matching and needs a design decision.
- The literal `_filter_repo_sessions` helper changes the set or order of matched sessions for a
  normal (non-metacharacter) name in any existing test — the output contract must stay byte-stable.
- The live code at the "Current state" excerpts does not match (drift since `88cd1f4`).
- Modeling prefix-vs-exact in `tests/fake-tmux` destabilizes an unrelated existing test.

## Maintenance notes

- `_filter_repo_sessions` is the canonical repo→session matcher now; future session-listing code
  must use it, not `grep -E` on the raw name.
- If a future feature legitimately needs prefix matching, it must opt in explicitly (bare `-t`),
  with a comment — the default is now exact `=`.
- A reviewer should confirm every changed `-t` target is a *lookup* (has-session/attach), never a
  `new-session -s` creation.
