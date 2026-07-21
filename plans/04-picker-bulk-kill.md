# Plan 04: Bulk-kill multiple sessions in one action with fzf `--multi`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/repo-session tests/test-picker.sh README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
>
> **⚠ HARD DEPENDENCY — READ THIS BEFORE ANYTHING ELSE.** This plan builds on
> plan **03** (the picker `--expect` → `--bind` conversion). At the moment this
> plan was written (commit `88cd1f4`), plan 03 had **not** landed: `run_picker`
> still used `--expect`, there was **no** `tests/test-picker.sh`, and there was
> **no** `plans/` directory. Every code excerpt below tagged `PRE-03` is the
> code *as it exists at 88cd1f4* and is shown **only so you can detect that
> plan 03 has not run**. If you still see the `PRE-03` shape in the live code,
> **STOP** (see STOP condition A) — do not bolt bulk-kill onto the old
> `--expect` teardown model.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/03-*.md — the picker refactor that converts `run_picker`
  from `--expect="ctrl-x,ctrl-r,…"` to per-key `--bind` actions (in particular a
  `ctrl-x` bind that kills the current row and `reload`s the list). This plan
  mirrors that `ctrl-x` bind for a *multi-selection* under a new key. Plan 03
  must be applied first. (Its exact filename/slug was not known when this plan
  was written — locate it in `plans/` and confirm it landed.)
- **Category**: ux
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

FINDING UX-03. Pruning stale sessions is one-at-a-time: each dead session is a
separate `ctrl-x` → `[y/N]` → list-rebuild cycle. Clearing N leftover sessions
costs N full cycles. fzf's `--multi` lets a user tab-mark several rows and act on
all of them at once. Adding a bulk-kill key turns "clear these six" from six
confirm-and-reload round-trips into a single confirm + single reload. The single-
row `ctrl-x` flow (and its byte-stable confirm) is preserved unchanged; bulk-kill
is a strictly additive, interactive-only convenience.

## Current state

**In-scope files and their roles:**

- `bin/repo-session` — the remote brain. `run_picker()` (the interactive fzf
  session picker) is where the kill key(s) live. `picker_kill()` is the tmux
  kill helper. `parse_launchers()` owns the reserved-key guard that stops a
  user-configured launcher from shadowing a picker action key.
- `tests/test-picker.sh` — **expected to be created by plan 03.** It is expected
  to hold the fzf-path integration tests, including a fake-fzf harness that can
  drive `--bind`/`reload` and assert `kill-session` log lines. This file did
  **not** exist at 88cd1f4 (see STOP condition B).
- `README.md` — user docs. The picker-keys table row (line ~76) and the
  "## The picker" section (lines ~104–139) describe the key bindings.

### PRE-03 excerpts (what exists at 88cd1f4 — DETECT-AND-STOP, do not edit these)

These prove plan 03 has not run. If the live code matches any of them, **STOP**.

`bin/repo-session:728-731` — the `--expect` hints/keys setup (PRE-03):

```bash
  local banner hints header expect_keys lc
  hints='enter=attach · ctrl-x=kill · ctrl-r=rename · esc=quit'
  expect_keys="ctrl-x,ctrl-r$(_launcher_expect_suffix)"
  while true; do
```

`bin/repo-session:748-760` — the fzf invocation (PRE-03: uses `--expect`, no
`--multi`, no `--bind`):

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

`bin/repo-session:789-799` — the single-row `ctrl-x` kill handled *after* fzf
returns, via `case "$key"` (PRE-03 teardown model — plan 03 replaces this with a
`--bind`):

```bash
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
```

`bin/repo-session:405-407` — `picker_kill` (this helper is stable and you will
reuse it; exact-match `=` prefix matters):

```bash
picker_kill() {
  "$TMUXBIN" kill-session -t "=$1"
}
```

`bin/repo-session:157-181` — `parse_launchers`, whose reserved-key guard (line
172) currently reserves only `ctrl-x`/`ctrl-r`:

```bash
    [[ -z "$key" || -z "$cmd" ]] && continue
    # Reserved for kill/rename in the main picker.
    [[ "$key" == "ctrl-x" || "$key" == "ctrl-r" ]] && continue
```

### Expected POST-03 shape (what you must be looking at before you start)

After plan 03 lands, `run_picker`'s fzf invocation is expected to:

- **not** contain `--expect`;
- carry per-key `--bind` actions, including a `ctrl-x` bind that (a) confirms,
  (b) calls a kill helper on the current row's field 1, and (c) `reload(...)`s
  the list from `build_session_rows`;
- likely route the kill through a callback into `repo-session` (a hidden
  subcommand / env-gated entry) that the fzf `--bind ... execute(...)` invokes,
  because a `--bind` action cannot run arbitrary shell functions directly.

**You do not have plan 03's file, so its exact bind syntax, callback name, and
reload wiring are unknown to this plan.** Step 1 is to read the live post-03
`ctrl-x` bind and copy its exact mechanism; every later step *mirrors* it. If
the live `ctrl-x` mechanism is not a `--bind` (i.e. it still matches the PRE-03
excerpts above), **STOP** (condition A).

### fzf mechanics you will rely on (reference — confirm against `man fzf`)

- `--multi` (`-m`) lets the user mark multiple rows (Tab / Shift-Tab). Without
  it, only the current row is ever "selected".
- In a `--bind` action's command template, `{+1}` expands to **field 1 of every
  selected row**, each token individually shell-quoted and space-separated; if
  no rows are marked, it expands to just the current row's field 1. `{+}`
  expands to the whole selected rows. Field numbering honors `--delimiter`
  (here `$'\t'`), so field 1 is the session name.
- `reload(CMD)` re-runs `CMD` and replaces the list in place (no fzf restart).
- Session names can never contain spaces (`create_repo` / `create_home_session`
  enforce `^[A-Za-z0-9][A-Za-z0-9._-]*$`), so `{+1}` word-splitting into separate
  positional args is safe here.

### Repo conventions that apply

- `set -u` is on, `set -e` is OFF. Guard array expansions:
  `"${arr[@]+"${arr[@]}"}"`.
- **Non-TTY output is byte-stable and asserted by tests.** All new chrome/hints
  must stay interactive-only. Bulk-kill is inside the fzf path, which only runs
  interactively, so this is naturally satisfied — but do **not** add any new
  stdout/stderr line outside the fzf/TTY path.
- The kill helper uses the `=NAME` exact-match prefix (`picker_kill`, above).
  Any new kill loop must use the same `=` prefix so it targets the exact session
  (tmux would otherwise prefix-match).
- Bulk-kill confirm must mirror the existing single-kill confirm style (a
  `printf ... >/dev/tty` prompt then one `read -r ans </dev/tty`; treat only
  `y`/`Y` as yes). "Reads a single key" here means a single answer read, exactly
  as the single-row `ctrl-x` confirm does today — do not switch to `read -n1`.

## Commands you will need

| Purpose            | Command                                   | Expected on success                     |
|--------------------|-------------------------------------------|-----------------------------------------|
| Detect plan 03     | `grep -n -- '--expect' bin/repo-session`  | **no match inside `run_picker`** (else STOP A) |
| Detect plan 03     | `grep -n -- '--bind' bin/repo-session`    | at least one match in `run_picker`      |
| Picker test file   | `test -f tests/test-picker.sh && echo ok` | prints `ok` (else STOP B)               |
| Syntax check       | `bash -n bin/repo-session`                | exit 0, no output                       |
| Lint               | `shellcheck bin/repo-session`             | exit 0 (honor existing `# shellcheck disable=`) |
| Picker tests       | `bash tests/test-picker.sh`               | all `ok …`, no `FAIL`; exit 0           |
| Full suite         | `bash tests/run.sh`                       | exit 0 (no `FAIL` lines)                |

## Scope

**In scope** (the only files you may modify):

- `bin/repo-session` — `run_picker()` (add `--multi` + the bulk-kill bind, and
  filter the `➕ new session…` label out of any multi-selection); `parse_launchers()`
  reserved-key guard (reserve the chosen bulk-kill key); the `--help` "Picker
  keys" block. You may add one small helper function (e.g. `picker_bulk_kill`)
  next to `picker_kill`.
- `tests/test-picker.sh` — add one multi-select bulk-kill test (created by plan
  03; you extend it).
- `README.md` — picker-keys table row (~line 76) and the "## The picker" bullet
  list (~lines 104–139).

**Out of scope** (do NOT touch, even though they look related):

- The single-row `ctrl-x` bind/flow and its confirm string — **preserve exactly**
  as plan 03 left it; a bulk key is *additive*, it does not replace single-kill.
- The numbered-menu (no-fzf) path in `run_picker` — no multi-select there; leave
  it byte-for-byte unchanged.
- `picker_rename` / `ctrl-r`.
- MRU / most-recently-used ordering (that is plan 05).
- Any delete-repo lifecycle / repo removal.
- Any non-TTY token: `ok`/`FAIL`/`info` (doctor), `local/remote` (update), the
  `repo-session: no repo …` error, the t8 6-field row, t13 silent `--validate`.
- The banner/`ferry_banner` art and its tests (t26/t27/t28/t33/t34).

## Git workflow

- Branch off the current main: `advisor/04-picker-bulk-kill`.
- Commit per logical unit (source change; docs; test) or one squashed commit —
  match the repo's conventional-commit style. Example from `git log`:
  `chore(demo): re-record with real JetBrains Mono metrics (kit v0.2.2)`.
  A fitting subject here: `feat(picker): bulk-kill selected sessions with fzf --multi`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 0: Confirm plan 03 landed (gate — do not skip)

Run:

```
grep -n -- '--expect' bin/repo-session
grep -n -- '--bind'   bin/repo-session
test -f tests/test-picker.sh && echo HAVE_PICKER_TESTS
```

- If `--expect` still appears anywhere inside `run_picker` (i.e. the PRE-03
  excerpt at 748–760 is still live) → **STOP, condition A.**
- If `--bind` does **not** appear in `run_picker` → **STOP, condition A.**
- If `tests/test-picker.sh` does not exist → **STOP, condition B.**

Then open `run_picker` and read plan 03's live **`ctrl-x` bind** end to end.
Write down, verbatim, for reuse in the next steps:
1. the exact `--bind 'ctrl-x:…'` action string;
2. the exact callback/subcommand it invokes to perform the kill (and how that
   callback receives the session name — arg? env? stdin?);
3. the exact `reload(…)` fragment it uses to rebuild the list.

If plan 03 killed via a mechanism you cannot cleanly mirror for a *set* of names
(e.g. it hard-codes a single `{1}` with no reusable callback), **STOP, condition
C**, and report what you found rather than inventing a new callback protocol.

**Verify**: you can quote plan 03's `ctrl-x` bind, its kill callback, and its
`reload` fragment. If you cannot, STOP.

### Step 1: Choose and justify the bulk-kill key — use `alt-x`

Bind bulk-kill to **`alt-x`**, a dedicated key, rather than overloading `ctrl-x`.

Rationale (put a one-line comment to this effect above the bind):
- **Preserves single-row `ctrl-x` semantics untouched** — the brief and this
  plan require the single-kill flow (and its byte-stable confirm string, which a
  plan-03 test may assert) to be unchanged. A separate key guarantees that.
- **No ambiguity**: `ctrl-x` conceptually acts on "the current row"; `alt-x`
  acts on "the marked set". Overloading one key to mean both (via `{+1}`) would
  silently change the single-kill confirm wording into a count/list form.
- `alt-x` is a valid fzf-bindable key (see `parse_launchers`' key regex at
  `bin/repo-session:174-176`, which already accepts `^alt-[a-z]$`).

No verification command (decision step); it is enforced by later steps.

### Step 2: Reserve `alt-x` in `parse_launchers` so a launcher can't shadow it

In `parse_launchers` (`bin/repo-session`), extend the reserved-key guard so a
user-configured `FERRY_LAUNCHERS=alt-x:…` cannot bind over the bulk-kill key.

Current line (`bin/repo-session:171-172`):

```bash
    # Reserved for kill/rename in the main picker.
    [[ "$key" == "ctrl-x" || "$key" == "ctrl-r" ]] && continue
```

Change to also reserve `alt-x`:

```bash
    # Reserved for kill/rename/bulk-kill in the main picker.
    [[ "$key" == "ctrl-x" || "$key" == "ctrl-r" || "$key" == "alt-x" ]] && continue
```

This does not disturb existing launcher tests: t29 uses `ctrl-a`/`ctrl-g`, t30
uses `ctrl-x`/`banana`/`alt-c` (not `alt-x`).

**Verify**:
```
bash -n bin/repo-session            # exit 0
bash tests/test-repo-session.sh     # all ok, no FAIL (t29/t30/t32 still pass)
```

### Step 3: Add a `picker_bulk_kill` helper next to `picker_kill`

Add a helper that takes a set of candidate session names (positional args),
filters out the `➕ new session…` label and empties, confirms **once** with a
count + name list, and on yes kills each via the exact-match `=` prefix.

Place it immediately after `picker_kill` (`bin/repo-session:405-407`). Model its
confirm on the existing single-kill confirm (PRE-03 excerpt 789–799): a
`printf … >/dev/tty` prompt and one `read -r ans </dev/tty`, treating only
`y`/`Y` as yes.

Target shape (adjust the label constant to match the live `new_label` value used
in `run_picker` — at 88cd1f4 it is `$'➕ new session…'`):

```bash
# Bulk-kill: confirm once for a set of session names, then kill each (=exact).
# Skips the picker's "➕ new session…" label and empty args. Interactive only.
picker_bulk_kill() {
  local -a targets=()
  local n
  for n in "$@"; do
    [[ -z "$n" ]] && continue
    [[ "$n" == '➕ new session…' ]] && continue
    targets+=("$n")
  done
  (( ${#targets[@]} == 0 )) && return 0
  printf 'kill %d session(s): %s? [y/N] ' \
    "${#targets[@]}" "${targets[*]}" >/dev/tty
  local ans
  if ! read -r ans </dev/tty; then
    return 0
  fi
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    for n in "${targets[@]}"; do
      "$TMUXBIN" kill-session -t "=$n"
    done
  fi
  return 0
}
```

Notes:
- Uses `"${targets[@]}"` guarded by a count check; array expansions are safe.
- Reuses the `=$n` exact-match prefix identical to `picker_kill`.
- If plan 03's single-kill callback is a hidden `repo-session` subcommand rather
  than a sourced function, add a **parallel** subcommand that forwards `"$@"` to
  `picker_bulk_kill` (mirror exactly how plan 03 wired the `ctrl-x` callback —
  same dispatch location, same env gate). Do not invent a different protocol; if
  plan 03's callback shape makes a multi-arg forward impossible, STOP (C).

**Verify**: `bash -n bin/repo-session` → exit 0. (Behavior is verified by the
test in Step 6.)

### Step 4: Add `--multi` and the `alt-x` bulk-kill bind to the picker fzf

In `run_picker`'s post-03 fzf invocation:

1. Add `--multi` to the fzf flag list (so rows can be tab-marked).
2. Add an `alt-x` `--bind` that runs `picker_bulk_kill` over `{+1}` and then
   `reload(...)`s the list — **mirroring plan 03's `ctrl-x` bind exactly** (same
   `execute`/`execute-silent` form, same callback dispatch, same `reload`
   fragment you recorded in Step 0). Conceptually:

   ```
   --bind 'alt-x:execute(<same callback as ctrl-x, but the bulk entry> {+1} < /dev/tty > /dev/tty 2>&1)+reload(<same reload cmd plan 03 uses>)'
   ```

   Use whatever concrete callback/reload plan 03 established; the only
   differences from the `ctrl-x` bind are: (a) the bulk entry point
   (`picker_bulk_kill` / its subcommand), and (b) `{+1}` (all marked rows'
   field 1) instead of the single-row field. Keep the `< /dev/tty`/`> /dev/tty`
   redirection identical to plan 03's `ctrl-x` bind so the confirm can read a key.

**Filter the new-session row (required).** The `➕ new session…` label is a
single-field row appended after the session rows; under `--multi` a user could
mark it. Step 3's helper already skips that exact label, which is the guard.
Confirm the label string you filter in Step 3 is byte-identical to the live
`new_label` value in `run_picker` — if plan 03 changed it, use the new value.

**Verify**:
```
bash -n bin/repo-session            # exit 0
shellcheck bin/repo-session         # exit 0
grep -n -- '--multi' bin/repo-session   # matches the run_picker fzf invocation
grep -n 'alt-x'      bin/repo-session   # matches the new bind
```

### Step 5: Update the interactive hints and `--help`

1. In `run_picker`, locate the live post-03 hints string (at 88cd1f4 it was
   `hints='enter=attach · ctrl-x=kill · ctrl-r=rename · esc=quit'` at line 729;
   plan 03 may have moved/renamed it). Add a bulk-kill token so it reads, e.g.:
   `enter=attach · ctrl-x=kill · alt-x=kill selected · ctrl-r=rename · esc=quit`.
   Also mention `tab=mark` if there is room. Keep it interactive-only (it is
   already part of the fzf header, so it never reaches non-TTY output).

2. In the `--help` "Picker keys" block (`bin/repo-session:887-890`):

   ```bash
   ${S}Picker keys${Z}
     enter=attach · ctrl-x=kill · ctrl-r=rename · ctrl-a/ctrl-g=AI launchers
     list navigation wraps (cycle) · esc=quit
     (Launchers via FERRY_LAUNCHERS; defaults: ctrl-a:claude, ctrl-g:grok)
   ```

   Add `alt-x` (and `tab` to mark). Target:

   ```bash
   ${S}Picker keys${Z}
     enter=attach · ctrl-x=kill · alt-x=kill selected (tab to mark) · ctrl-r=rename
     ctrl-a/ctrl-g=AI launchers · list navigation wraps (cycle) · esc=quit
     (Launchers via FERRY_LAUNCHERS; defaults: ctrl-a:claude, ctrl-g:grok)
   ```

   This block is inside the `--help` heredoc, which is help text (not an asserted
   non-TTY token); no test asserts its exact wording. Keep it plain ASCII plus
   the `·` already used.

**Verify**:
```
bash -n bin/repo-session
bash "$PWD/bin/repo-session" --help 2>&1 | grep -q 'alt-x' && echo HELP_OK
```
Expected: `HELP_OK`.

### Step 6: Add the multi-select bulk-kill test to `tests/test-picker.sh`

Add one test that drives the fzf path with **two rows marked**, confirms, and
asserts **two** `kill-session` log lines followed by a reload — modeled on plan
03's existing fzf `ctrl-x` (single-kill) integration test in the same file.

**Read plan 03's fake-fzf harness first** and copy its mechanism; do not build a
new one. That harness is what feeds selected rows and triggers the `--bind`
action non-interactively. Adapt it to: mark two session rows, send the confirm
answer `y`, and trigger `alt-x`.

Test structure (adapt names/paths to match plan 03's harness and this file's
`ok`/`fail`/`setup`/`teardown` helpers, which mirror `tests/test-repo-session.sh`
lines 11–39):

- Arrange: `FAKE_TMUX_SESSIONS=$'alpha\nbeta\ngamma'` with matching
  `FAKE_TMUX_META` lines (see `tests/test-repo-session.sh:127-128` for the meta
  format `name|window|Nw detached bash`). Set `REPO_SESSION_TMUXBIN` to the fake
  tmux and a fresh `FAKE_TMUX_LOG`.
- Act: run the picker through plan 03's fake fzf so that rows `alpha` and `beta`
  are the marked multi-selection, the confirm reads `y`, and the `alt-x` bind
  fires.
- Assert on `FAKE_TMUX_LOG`:
  - exactly two kill lines:
    `[[ "$(grep -c 'kill-session -t =' "$FAKE_TMUX_LOG")" -eq 2 ]]`
  - both intended sessions killed:
    `grep -q 'kill-session -t =alpha' "$FAKE_TMUX_LOG"` and `… =beta`
  - `gamma` was **not** killed:
    `! grep -q 'kill-session -t =gamma' "$FAKE_TMUX_LOG"`
  - a reload happened after the kills — assert whatever evidence plan 03's
    reload uses (e.g. a second `list-sessions` invocation, or the fake fzf being
    re-entered). Match plan 03's own reload assertion for `ctrl-x`.

`fake-tmux` logs every argv line and treats `kill-session` as a logged no-op
(`tests/fake-tmux:175`), so the two kill lines and any reload-driven
`list-sessions` will appear in `FAKE_TMUX_LOG`. Session names have no spaces, so
`{+1}` yields two clean positional args.

Add the new test's function name to the run list at the bottom of
`tests/test-picker.sh` (mirror how `tests/test-repo-session.sh:828-833` lists its
tests) so `bash tests/test-picker.sh` executes it.

**Verify**:
```
bash tests/test-picker.sh    # new test prints ok; no FAIL; exit 0
```

### Step 7: Update README docs

1. Picker-keys table row (`README.md:76`, current):

   ```
   | _(picker keys)_ | `enter=attach · ctrl-x=kill · ctrl-r=rename · ctrl-a/ctrl-g=AI · cycle · esc`; launchers on `➕ new session…` and destination rows |
   ```

   Add `alt-x=kill selected`:

   ```
   | _(picker keys)_ | `enter=attach · ctrl-x=kill · alt-x=kill selected (tab-mark) · ctrl-r=rename · ctrl-a/ctrl-g=AI · cycle · esc`; launchers on `➕ new session…` and destination rows |
   ```

2. In the "## The picker" bullet list (`README.md:104-139`), add one bullet after
   the preview-panel bullet (around line 118), e.g.:

   ```
   - **Bulk kill:** `--multi` is on — Tab / Shift-Tab mark rows; `alt-x` confirms
     once and kills every marked session, then reloads the list. `ctrl-x` still
     kills just the current row. The `➕ new session…` row is skipped if marked.
   ```

**Verify**: `grep -n 'alt-x' README.md` → matches both the table row and the new
bullet.

### Step 8: Full suite + lint

**Verify**:
```
bash -n bin/repo-session            # exit 0
shellcheck bin/repo-session         # exit 0
bash tests/run.sh                   # exit 0, no FAIL lines
git status --short                  # only bin/repo-session, tests/test-picker.sh, README.md, plans/README.md
```

## Test plan

- **New test** in `tests/test-picker.sh`: multi-select bulk-kill happy path —
  mark two of three sessions, confirm `y`, assert exactly two `kill-session -t =`
  log lines (for the two marked names), the third session untouched, and a reload
  after. Modeled structurally on plan 03's single-kill `ctrl-x` fzf test in the
  same file, and on the `ok`/`fail`/`setup`/`teardown` + `FAKE_TMUX_*` harness in
  `tests/test-repo-session.sh:11-39,121-138`.
- **Regression coverage relied upon (do not modify):**
  - `tests/test-repo-session.sh` t18 (`picker_kill` still `kill-session -t =s1`),
    t29/t30/t32 (launcher parsing; `alt-x` reservation must not break them),
    t35 (`--cycle` count == 3 — do not add/remove a `--cycle`).
  - Plan 03's single-kill `ctrl-x` test in `tests/test-picker.sh` must still pass
    unchanged.
- **Verification**: `bash tests/run.sh` → exit 0, all `ok`, including the new
  bulk-kill test.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/repo-session` exits 0.
- [ ] `shellcheck bin/repo-session` exits 0 (existing `# shellcheck disable=`
      directives preserved).
- [ ] `grep -c -- '--multi' bin/repo-session` ≥ 1 and the match is in the
      `run_picker` fzf invocation.
- [ ] `grep -n 'alt-x' bin/repo-session` shows: the `parse_launchers` reservation,
      the picker bind, the hints line, and the `--help` block.
- [ ] `bin/repo-session --help` output contains `alt-x`.
- [ ] `tests/test-picker.sh` contains a new multi-select bulk-kill test that
      asserts exactly two `kill-session -t =` lines + a reload, and it passes.
- [ ] `bash tests/run.sh` exits 0 (no `FAIL`), including unchanged
      `tests/test-repo-session.sh` (t18/t29/t30/t32/t35).
- [ ] Single-row `ctrl-x` flow and its confirm string are unchanged from plan 03.
- [ ] Numbered-menu (no-fzf) path in `run_picker` is unchanged.
- [ ] `README.md` picker-keys row and "## The picker" section mention `alt-x`
      bulk kill.
- [ ] No files outside the in-scope list are modified (`git status --short`).
- [ ] `plans/README.md` status row for plan 04 updated.

## STOP conditions

Stop and report back (do not improvise) if:

- **A (primary dependency gate).** `run_picker` still uses `--expect` for the
  kill keys, or has **no** `--bind` (i.e. the PRE-03 excerpts at
  `bin/repo-session:728-731`, `748-760`, `789-799` are still live). This means
  **plan 03 has not landed.** Do not convert the picker yourself and do not bolt
  bulk-kill onto the `--expect` model — that is plan 03's job. Report "blocked on
  plan 03".
- **B.** `tests/test-picker.sh` does not exist. It is expected to be created by
  plan 03 (with the fake-fzf harness bulk-kill needs). Report "blocked on plan
  03 (no tests/test-picker.sh)". Do NOT invent a fzf harness from scratch and do
  NOT relocate the test into `tests/test-repo-session.sh`.
- **C.** Plan 03's `ctrl-x` kill callback/reload mechanism cannot be cleanly
  mirrored for a *set* of session names (e.g. it hard-codes a single field with
  no reusable callback, or its confirm/reload wiring can't accept multiple
  names). Report exactly what plan 03 built and stop, rather than inventing a
  divergent bulk callback protocol.
- **D.** The live `plans/` directory has no plan-03 file at all (there was none
  at 88cd1f4). Without plan 03's actual output you cannot verify the POST-03
  anchors — report and stop.
- **E.** Any `Current state` excerpt (PRE-03 or the reserved-key guard) does not
  match the live code in a way this plan didn't anticipate (drift beyond the
  expected plan-03 transformation).
- **F.** A verification command fails twice after a reasonable fix attempt, or a
  change would require editing a file outside the in-scope list.
- **G.** Adding `--multi`/the bind changes any non-TTY-gated output, or a
  previously green test in `tests/test-repo-session.sh` (t18/t29/t30/t32/t35)
  starts failing.

## Maintenance notes

For whoever owns this code next:

- **Key-binding choice is documented** in the README picker-keys row + "## The
  picker" section and in `--help`. `alt-x` = bulk kill; `ctrl-x` = single kill.
  `alt-x` is reserved in `parse_launchers` so a user launcher cannot shadow it —
  if a future change adds another reserved picker action key, extend the same
  guard (`bin/repo-session:171-172`).
- **Coupling to plan 03**: bulk-kill deliberately mirrors plan 03's `ctrl-x`
  bind callback + `reload`. If plan 03's callback protocol, confirm mechanism, or
  reload fragment is later refactored, the `alt-x` bind and `picker_bulk_kill`
  must be refactored in lockstep — they share the same callback path by design.
- **Reviewer scrutiny**: (1) confirm the single-row `ctrl-x` confirm string is
  byte-identical to before (bulk-kill must be additive); (2) confirm the
  `➕ new session…` label filter in `picker_bulk_kill` matches the live
  `new_label` value; (3) confirm no new line escapes the fzf/TTY path into
  non-TTY output; (4) confirm the test asserts an *exact* count of two kills, not
  just "≥1".
- **Deferred out of this plan**: MRU ordering (plan 05); delete-repo lifecycle;
  any bulk *rename*; `read -n1` single-keystroke confirm (kept as line-read to
  match the existing single-kill confirm).
