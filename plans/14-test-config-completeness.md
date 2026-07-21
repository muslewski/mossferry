# Plan 14: Extend the config.example completeness test to guard all 9 documented keys

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index (this repo may not have a `plans/README.md` yet; if it
> does not exist, do NOT create one — just report completion).
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- tests/test-install.sh config.example README.md`
> If any of those files changed since this plan was written, compare the
> "Current state" excerpts below against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

The install test that keeps `config.example` complete only asserts **6 of the 9**
documented `FERRY_` keys. A regression that dropped `FERRY_LAUNCHERS`,
`FERRY_BANNER`, or `FERRY_HIDDEN_WINDOW_GLOB` from `config.example` would pass the
suite green while the README config table still promises all nine — an onboarding
trap: users copy `config.example` expecting a template for every documented knob,
and silently lose the three newest ones. This plan makes the test enforce the full
documented key set so `config.example` can no longer drift below the README without
turning the suite red. It is a **test-only** change: `config.example` and the README
already contain all nine keys today (verified below); this plan only teaches the
test to check them.

## Current state

Files involved:

- `tests/test-install.sh` — install-script test suite. The `t7` block asserts that
  `config.example` mentions each documented key. It currently lists only 6 keys.
- `config.example` — the seed template copied to `~/.config/mossferry/config`. Already
  contains all 9 keys (verified). **OUT OF SCOPE — do not edit.**
- `README.md` — the "Configuration" table is the human-facing source of truth for the
  full key set. Already lists all 9 keys (verified). **OUT OF SCOPE — do not edit.**

### `tests/test-install.sh`, lines 138–151 (the `t7` block — the ONLY code you change)

```bash
# ---------------------------------------------------------------------------
# t7: config.example has the six keys (commented)
# ---------------------------------------------------------------------------
if [[ -f "$ROOT/config.example" ]]; then
  for key in FERRY_REMOTE_BIN FERRY_REPO_BASE FERRY_DEFAULT_CMD FERRY_DEFAULT_HOST FERRY_SERVER_TIMEOUT FERRY_REMOTE_REPO; do
    if grep -q "$key" "$ROOT/config.example"; then
      ok "config.example has $key"
    else
      FAIL "config.example has $key"
    fi
  done
else
  FAIL "config.example exists"
fi
```

The `for key in …` loop names exactly **6** keys. The three missing ones are
`FERRY_HIDDEN_WINDOW_GLOB`, `FERRY_BANNER`, `FERRY_LAUNCHERS`.

### `config.example`, lines 1–11 (source data — verified complete; DO NOT edit)

```
# mossferry configuration — every key is optional; env > file > default.
#FERRY_REMOTE_BIN=".local/bin/repo-session"  # repo-session path, relative to remote $HOME
#FERRY_REPO_BASE="$HOME/Repositories"        # remote: where repos live
#FERRY_DEFAULT_CMD="neofetch"                # remote: startup command in fresh sessions
#FERRY_DEFAULT_HOST=""                       # local: host used by bare `ferry`
#FERRY_SERVER_TIMEOUT="86400"                # local: mosh-server self-exit after N s clientless
#FERRY_REMOTE_REPO="Repositories/mossferry"  # remote: repo checkout, relative to remote $HOME
#FERRY_HIDDEN_WINDOW_GLOB="_*"               # skip matching windows in picker names/previews
#FERRY_BANNER="on"                           # green ferry art in picker / --help (off|0 to hide)
#FERRY_LAUNCHERS="ctrl-a:claude,ctrl-g:grok" # picker AI launchers: comma-separated key:command
#                                            # (first colon splits; empty disables; ctrl-x/ctrl-r reserved)
```

All 9 keys are present. Confirmed with:
`rg -o 'FERRY_[A-Z_]+' config.example | sort -u` → prints exactly these 9 (alphabetical):
`FERRY_BANNER`, `FERRY_DEFAULT_CMD`, `FERRY_DEFAULT_HOST`, `FERRY_HIDDEN_WINDOW_GLOB`,
`FERRY_LAUNCHERS`, `FERRY_REMOTE_BIN`, `FERRY_REMOTE_REPO`, `FERRY_REPO_BASE`,
`FERRY_SERVER_TIMEOUT`.

### `README.md`, lines 147–157 (the "Configuration" table — the source of truth; DO NOT edit)

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
```

These 9 table rows are the authoritative documented set. The extended test list must
equal exactly this set.

### Why extend the explicit list rather than auto-derive from the README

The brief noted a "derive the list from the README table" option. **Do not do that** —
it is fragile for this repo, for two concrete reasons found during planning:

- `README.md:185` contains `FERRY_UPDATE_VERBOSE=1`, an **env-only** knob that is
  deliberately *not* in `config.example`. A naive backtick/`FERRY_`-grep over the whole
  README risks pulling it in and making the test demand a key that must never be in the
  template.
- `README.md:112` contains `FERRY_BANNER=off` (prose example), a second textual form of
  a key.

The backtick-wrapped bare-key set happens to equal the 9 today only by coincidence; a
future doc edit could break the derivation and fail the suite for the wrong reason. The
robust, weak-executor-safe fix is an **explicit 9-key list** plus a comment naming the
README table as the source of truth. That is what the steps below do.

### Test-harness conventions (so you don't break aggregation)

- `tests/run.sh` (lines 8–11) runs each `tests/test-*.sh` and only checks its **exit
  code** — it does NOT count `ok`/`FAIL` lines. Adding three more `ok "config.example
  has …"` lines is expected and safe.
- `ok`/`FAIL` are defined at `tests/test-install.sh:11-12`. Each present key prints one
  `ok` line; each missing key prints `FAIL` and sets `fail=1`, which makes the file exit
  nonzero (lines 212–217).
- The `t7` comment says "the six keys". That comment is a plain shell comment (never
  printed), so updating its wording to "nine keys" is safe and is part of this change.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift check | `git diff --stat 88cd1f4..HEAD -- tests/test-install.sh config.example README.md` | empty (no output) |
| Syntax check | `bash -n tests/test-install.sh` | exit 0, no output |
| Run this test file | `bash tests/test-install.sh` | last line `tests/test-install.sh: all ok`, exit 0 |
| Full suite | `bash tests/run.sh` | exit 0 (no failing test file) |
| Lint (best-effort) | `shellcheck tests/test-install.sh` | exit 0 (see note) |

Note on `shellcheck`: it was **not installed** in the planning environment
(`command -v shellcheck` → not found). If it is present in yours, run it and honor any
existing `# shellcheck disable=` directives; if it is absent, skip it and rely on
`bash -n`. Do not treat an absent `shellcheck` as a failure.

Note on `grep`: `tests/test-install.sh` already uses `grep -q` (lines 143, 167) and runs
under a plain `bash tests/test-install.sh` subprocess (real `grep`). Keep using `grep -q`
in the loop — do not switch it to `rg` or anything else.

## Scope

**In scope** (the only file you may modify):
- `tests/test-install.sh` — the `t7` block only (lines 138–151).

**Out of scope** (do NOT touch, even though they look related):
- `config.example` — already complete; editing it is the opposite of what this plan
  verifies. Any permanent edit here is a bug.
- `README.md` — source of truth, already complete; do not edit.
- `bin/mossferry`, `bin/repo-session`, `lib/green-ui.sh`, `install.sh`, any other test
  file — untouched.
- Do NOT add a `plans/README.md` if one does not already exist.

## Git workflow

- Branch: `advisor/14-test-config-completeness` (create from `main` if you are on `main`;
  do not commit directly to `main`).
- One commit for this change. Message style (conventional commits, matching repo `git
  log`, e.g. `chore(demo): …`):
  `test(install): assert config.example documents all 9 FERRY_ keys`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Extend the `t7` key list to all 9 keys and update the comment

In `tests/test-install.sh`, replace the `t7` block (current lines 138–151) so that:

1. The comment header reads "nine keys" (not "six") and names the README table as the
   source of truth.
2. The `for key in …` loop lists all **9** keys, appending
   `FERRY_HIDDEN_WINDOW_GLOB FERRY_BANNER FERRY_REMOTE_REPO`… — precisely, append the
   three missing ones (`FERRY_HIDDEN_WINDOW_GLOB`, `FERRY_BANNER`, `FERRY_LAUNCHERS`) to
   the existing six, preserving the existing six in place.

Do not change the loop body (`if grep -q "$key" … ok/FAIL`) or the `else FAIL
"config.example exists"` branch — only the comment and the `for` list change.

Target result (the whole `t7` block after your edit):

```bash
# ---------------------------------------------------------------------------
# t7: config.example documents all nine keys (commented)
#   Source of truth = README.md "Configuration" table. Keep this list in sync
#   with that table and with load_config defaults; a key documented there but
#   missing from config.example is an onboarding trap and must fail here.
# ---------------------------------------------------------------------------
if [[ -f "$ROOT/config.example" ]]; then
  for key in FERRY_REMOTE_BIN FERRY_REPO_BASE FERRY_DEFAULT_CMD FERRY_DEFAULT_HOST FERRY_SERVER_TIMEOUT FERRY_REMOTE_REPO FERRY_HIDDEN_WINDOW_GLOB FERRY_BANNER FERRY_LAUNCHERS; do
    if grep -q "$key" "$ROOT/config.example"; then
      ok "config.example has $key"
    else
      FAIL "config.example has $key"
    fi
  done
else
  FAIL "config.example exists"
fi
```

**Verify**:
- `bash -n tests/test-install.sh` → exit 0, no output.
- `bash tests/test-install.sh` → prints nine `ok config.example has FERRY_…` lines
  (one per key, including the three new ones) and ends with
  `tests/test-install.sh: all ok`; exit 0.
- Confirm the three new keys appear in the run output:
  `bash tests/test-install.sh 2>&1 | rg 'ok config.example has (FERRY_HIDDEN_WINDOW_GLOB|FERRY_BANNER|FERRY_LAUNCHERS)'`
  → three matching lines.

### Step 2: Prove the extended test actually FAILS when a documented key is removed (temporary, then restore — DO NOT COMMIT)

This step confirms the guard bites. You will remove one key from `config.example`
**temporarily**, run the test, see it fail, then restore. `config.example` MUST end this
step byte-identical to how it started.

1. Snapshot: `git stash` is NOT needed — instead capture the clean state:
   `git status --short config.example` → empty (no changes) before you start.
2. Temporarily delete the `FERRY_LAUNCHERS` line from `config.example` (e.g. edit the
   file and remove line 10, the `#FERRY_LAUNCHERS=…` line).
3. Run: `bash tests/test-install.sh; echo "exit=$?"` →
   expect a line `FAIL config.example has FERRY_LAUNCHERS`, a final
   `tests/test-install.sh: 1 failure(s)` (or similar nonzero-count line), and `exit=1`.
   This proves the new assertion catches a dropped key.
4. Restore `config.example` exactly: `git checkout -- config.example`.
5. Confirm restoration: `git status --short config.example` → empty (no changes), and
   `git diff config.example` → empty.

**Verify**: after Step 2, `git status --short` shows changes **only** in
`tests/test-install.sh` (your Step 1 edit). `config.example` is unmodified.

> If you cannot fully restore `config.example` to its committed state, STOP and report —
> do not commit a modified `config.example`.

### Step 3: Run the full suite

**Verify**:
- `bash tests/run.sh; echo "exit=$?"` → `exit=0` (every test file passed).
- `git status --short` → only `tests/test-install.sh` is modified; no other file
  (especially not `config.example` or `README.md`) is changed.

## Test plan

- No new test **file** — this extends the existing `t7` block in
  `tests/test-install.sh` from 6 asserted keys to all 9.
- Cases covered after the change:
  - Happy path: all 9 documented keys present in `config.example` → 9 `ok` lines, suite
    green (Step 1).
  - Regression the plan fixes: any one of the 3 previously-unguarded keys
    (`FERRY_HIDDEN_WINDOW_GLOB`, `FERRY_BANNER`, `FERRY_LAUNCHERS`) dropped from
    `config.example` → `FAIL` + nonzero exit (proven in Step 2).
- Structural pattern to match: the existing `t7` loop itself — reuse its exact
  `if grep -q … ok/FAIL` body; only the key list and comment change.
- Verification: `bash tests/run.sh` → exit 0; `bash tests/test-install.sh` prints nine
  `ok config.example has FERRY_…` lines.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n tests/test-install.sh` exits 0.
- [ ] `bash tests/test-install.sh` ends with `tests/test-install.sh: all ok` and exits 0.
- [ ] `bash tests/run.sh` exits 0.
- [ ] The `t7` `for key in …` loop in `tests/test-install.sh` names all 9 keys:
      `FERRY_REMOTE_BIN`, `FERRY_REPO_BASE`, `FERRY_DEFAULT_CMD`, `FERRY_DEFAULT_HOST`,
      `FERRY_SERVER_TIMEOUT`, `FERRY_REMOTE_REPO`, `FERRY_HIDDEN_WINDOW_GLOB`,
      `FERRY_BANNER`, `FERRY_LAUNCHERS`. Check:
      `rg -o 'FERRY_[A-Z_]+' tests/test-install.sh | sort -u` includes all three new keys.
- [ ] `git status --short` shows **only** `tests/test-install.sh` modified — no change to
      `config.example`, `README.md`, or any source/lib/other-test file.
- [ ] (If `plans/README.md` exists) its status row for plan 14 is updated; otherwise this
      criterion is N/A.

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows `tests/test-install.sh`, `config.example`, or `README.md` changed
  since commit `88cd1f4` and the "Current state" excerpts no longer match the live code.
- **`config.example` is actually missing one of the 9 documented keys** (i.e.
  `rg -o 'FERRY_[A-Z_]+' config.example | sort -u` does NOT list all 9). That is a real
  product gap, not a test gap — report it; do NOT paper over it by editing the test or
  `config.example`.
- The README "Configuration" table (lines 147–157) documents a **different** set of keys
  than the nine listed here (e.g. a key was added/removed). Report the mismatch; do not
  guess which set is correct.
- After Step 2 you cannot restore `config.example` to its committed state.
- Any verification command fails twice after a reasonable fix attempt.
- The change appears to require editing any out-of-scope file.

## Maintenance notes

For whoever owns this next:

- This `t7` block is the **guard that keeps three artifacts in sync**: the README
  "Configuration" table (documentation), `config.example` (the seeded template), and
  `load_config`'s built-in defaults in `bin/mossferry` / `bin/repo-session`. When a new
  `FERRY_` config key is added, it must be added in all three places **and** appended to
  this test's key list — otherwise the template silently lags the docs.
- The test only checks **presence** of the key substring in `config.example`, not its
  default value or comment. If a future plan wants stricter checking (e.g. default value
  matches the README), that is a separate enhancement, deliberately deferred here to keep
  this change test-only and low-risk.
- Reviewer scrutiny for the PR: confirm the diff touches **only** the `t7` block of
  `tests/test-install.sh` (comment + `for` list), that `config.example` is untouched, and
  that the key list equals the README table's nine rows exactly (no `FERRY_UPDATE_VERBOSE`
  — that env-only knob must NOT be in this list).
