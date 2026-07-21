# Plan 07: Fix `ferry doctor` — stop the password-host hang, short-circuit after a failed connect, reuse one SSH handshake, and check remote tmux

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan in
> `plans/README.md` **only if that file exists** (it may not yet — if absent,
> skip that step; do not create it) — unless a reviewer dispatched you and told
> you they maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/mossferry tests/fake-bin/ssh tests/test-ui-ops.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts below against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `88cd1f4`, 2026-07-18

## Why this matters

`ferry doctor` is the tool users run when connectivity is broken — so it must
never itself hang, and it must be fast. Today it does neither well.

1. **It can hang.** Of the five remote-connecting SSH calls in `cmd_doctor`,
   **only** the connectivity probe (check 3) uses `-o BatchMode=yes -o
   ConnectTimeout=5`. The four later remote checks (remote-bin `test -x`, remote
   `cat VERSION`, remote `command -v fzf`, remote `pgrep mosh-server`) use a
   plain `ssh` with **no** `BatchMode` and **no** `ConnectTimeout`. On a host
   that has no key auth (password-only), the connect check fails — and then each
   of those four checks blocks on an interactive password prompt, hanging the
   very tool meant to diagnose the connection. (Finding PERF-02 / DIR-03.)

2. **It is slow.** Even on a healthy host, doctor performs five sequential real
   SSH handshakes. Each handshake pays full TCP + crypto setup latency; on a
   high-latency link that is seconds of dead wall-time for what is logically one
   connection's worth of probes.

3. **It skips the hardest dependency.** Doctor checks remote `fzf` (a *fallback*
   nicety) but never checks remote `tmux` — the single dependency the entire
   remote brain (`bin/repo-session`) is built on. A host missing `tmux` passes
   doctor clean, then fails opaquely at session time.

This plan: (1) adds `-o BatchMode=yes -o ConnectTimeout=5` to **every**
remote-connecting SSH in doctor so no check can block on a password; (2)
short-circuits — if the connect probe fails, the remaining remote checks emit
their existing `FAIL`/`info` lines **without** attempting an SSH (they cannot
succeed and must not hang); (3) reuses one SSH connection across all probes via
`ControlMaster` (kills the per-check handshake latency while keeping every
per-check output line byte-for-byte identical); and (4) adds a remote-`tmux`
`FAIL` check next to the `fzf` check.

## Current state

### Files involved

- `bin/mossferry` — the LOCAL client. `cmd_doctor()` starts at line 414; the
  remote checks that must change are lines 464–535, and the TTY summary is
  538–550. This is the ONLY source file this plan edits.
- `tests/fake-bin/ssh` — the fake `ssh` used by the client tests. It logs every
  invocation to `$FAKE_NET_LOG` and pattern-matches argv to answer
  update/doctor probes. You will add three **env-gated, default-inert** hooks
  here (test scaffolding — in scope).
- `tests/test-ui-ops.sh` — the ops-surface test suite. **The doctor tests live
  here** (cases `f1` and `f6`), *not* in `tests/test-mossferry.sh`. You add new
  cases `f8`, `f9`, and (only if you do the optional Step 4) `f10` here.

> ⚠️ **Brief-vs-reality drift already reconciled for you.** The task brief
> referred to the doctor tests as being in `tests/test-mossferry.sh` and to the
> ssh stub as `tests/ssh`. Neither is correct in the live tree: doctor is tested
> in **`tests/test-ui-ops.sh`** and the stub is **`tests/fake-bin/ssh`**. This
> plan uses the correct paths. If you find doctor assertions in
> `tests/test-mossferry.sh`, that is new drift — STOP and report.

### Excerpt A — the five remote checks + MagicDNS, exactly as they are today (`bin/mossferry:464–535`)

```bash
  # 2. ssh -G resolves
  if ssh -G "$host" >/dev/null 2>&1; then
    _doc_emit ok "ssh config resolves host $host"
  else
    _doc_emit FAIL "ssh config does not resolve host $host"
    failed=1
  fi

  # 3. ssh BatchMode connect
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" true >/dev/null 2>&1; then
    _doc_emit ok "ssh BatchMode connect to $host"
  else
    _doc_emit FAIL "ssh BatchMode connect to $host"
    failed=1
  fi

  # 4. local mosh binary
  if command -v mosh >/dev/null 2>&1; then
    _doc_emit ok "local mosh binary"
  else
    _doc_emit FAIL "local mosh binary missing"
    failed=1
  fi

  # 5. remote FERRY_REMOTE_BIN executable (relative to remote $HOME)
  if ssh "$host" "test -x $FERRY_REMOTE_BIN || test -x \"\$HOME/$FERRY_REMOTE_BIN\"" >/dev/null 2>&1; then
    _doc_emit ok "remote $FERRY_REMOTE_BIN executable"
  else
    _doc_emit FAIL "remote $FERRY_REMOTE_BIN not executable"
    failed=1
  fi

  # 6. local vs remote VERSION match
  local v_local v_remote
  v_local="$(own_version | tr -d '[:space:]')"
  v_remote="$(ssh "$host" cat "${FERRY_REMOTE_REPO}/VERSION" 2>/dev/null || true)"
  v_remote="${v_remote//$'\r'/}"
  v_remote="${v_remote//$'\n'/}"
  v_remote="${v_remote//[[:space:]]/}"
  if [[ -n "$v_remote" && "$v_local" == "$v_remote" ]]; then
    _doc_emit ok "versions match: $v_local"
  else
    _doc_emit FAIL "versions: local $v_local / remote ${v_remote:-unknown}"
    failed=1
    version_failed=1
    fix_hints+=("run: ferry update ${host}")
  fi

  # 7. remote fzf (info if missing)
  if ssh "$host" command -v fzf >/dev/null 2>&1; then
    _doc_emit ok "remote fzf present"
  else
    _doc_emit info "remote fzf missing — numbered menu fallback available"
  fi

  # 8. remote mosh-server count (info)
  local count
  count="$(ssh "$host" pgrep -c mosh-server 2>/dev/null || true)"
  count="${count//$'\n'/}"
  : "${count:=0}"
  _doc_emit info "remote mosh-server count: $count"

  # 9. MagicDNS note (info): whether HostName is an IP
  local hostname
  hostname="$(ssh -G "$host" 2>/dev/null | awk 'tolower($1)=="hostname"{print $2; exit}')"
  if [[ -z "$hostname" ]]; then
    _doc_emit info "MagicDNS: could not read HostName for $host"
  elif [[ "$hostname" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    _doc_emit info "MagicDNS: HostName is IP ($hostname) — not using MagicDNS name"
  else
    _doc_emit info "MagicDNS: HostName is $hostname"
  fi
```

The four hang-prone calls are the **plain `ssh "$host" …`** invocations at
checks 5, 6, 7, 8. Checks 2 and 9 use `ssh -G`, which is a **local config
resolver** — it never opens a network connection and can never hang, so it is
left untouched by this plan.

### Excerpt B — the locals declared at the top of `cmd_doctor` (`bin/mossferry:421–423`)

```bash
  local failed=0 checks=0 cfg="${HOME}/.config/mossferry/config"
  local chrome=0 version_failed=0
  local fix_hints=()
```

You will add ONE new locals line right after line 423.

### Excerpt C — the TTY summary tail, unchanged by this plan except the teardown insert (`bin/mossferry:537–550`)

```bash
  # TTY summary + fix hints
  if (( chrome )); then
    if (( failed )); then
      printf '%s%d checks · %s failed%s\n' "${UI_R-}" "$checks" "some" "${UI_Z-}" >&2
    else
      printf '%s%s%s %d checks · all ok%s\n' "${UI_G-}" "${UI_OK-OK}" "${UI_Z-}" "$checks" "" >&2
    fi
    local h
    for h in "${fix_hints[@]+"${fix_hints[@]}"}"; do
      printf '%s%s%s\n' "${UI_D-}" "$h" "${UI_Z-}" >&2
    done
  fi

  return "$failed"
}
```

### Repo conventions that constrain this change (READ — the tests enforce these)

- **`set -u` is ON, `set -e` is OFF** in `bin/mossferry`. A failing `ssh` in an
  `if` condition does not abort the function — the `else` branch runs. Do not
  add `set -e`. Guard array expansions against unbound errors with the
  `"${arr[@]+"${arr[@]}"}"` form (see the `fix_hints` loop in Excerpt C). A
  literally-initialized non-empty array (like the `SSH_OPTS` you add) is always
  populated, so a plain `"${SSH_OPTS[@]}"` is safe.
- **`bin/mossferry` must run on bash 3.2 (macOS) and Linux.** Arrays,
  `local -a`, and `mapfile`-free code are required. Everything this plan adds
  (indexed arrays, `(( ... ))` arithmetic, `ssh -o`) is bash-3.2-safe. Do NOT
  use `mapfile`/`readarray` or `${var,,}` here.
- **Non-TTY output is byte-stable and asserted by tests.** Every user-facing
  line goes through `_doc_emit <kind> <msg>`; in non-TTY mode it prints exactly
  `<kind> <msg>` (see `_doc_emit`, `bin/mossferry:432–455`). The asserted tokens
  are the literal messages, e.g. `ok versions match: <v>`, `FAIL versions: local
  <v> / remote <v>`, `info remote fzf missing …`. **The short-circuit branches
  you add MUST emit the identical `FAIL`/`info` message strings the existing
  `else` branches already emit** — same words, same order — so the byte output
  is unchanged whether a probe was skipped or actually attempted.
- **`_doc_emit` increments `checks`** on every call, and the TTY summary prints
  `$checks`. Adding the new tmux check adds exactly one `_doc_emit`, so the
  TTY-only `N checks` number rises by 1. That number is **not** asserted by any
  test (it appears only in the TTY summary line f1 does not pin), so this is
  fine — but do not add stray `_doc_emit` calls beyond the one tmux check.

### Design note on `ControlMaster` (there is no prior art to match)

The task brief said "ControlMaster … should match the `~/.ssh/config` approach
the design docs prescribe." **No such approach is prescribed anywhere in this
repo** — `grep -rn 'ControlMaster' .` returns nothing, and the design spec
`docs/superpowers/specs/2026-07-17-mossferry-ui-ops-design.md` says nothing
about connection multiplexing. So this plan defines a **self-contained,
per-invocation** ControlMaster socket local to the `doctor` run (opened by the
connect check, torn down at the end). Do NOT write into the user's
`~/.ssh/config`. If you discover a repo convention for SSH multiplexing that
contradicts this, STOP and report.

## Commands you will need

| Purpose            | Command                                             | Expected on success                     |
|--------------------|-----------------------------------------------------|-----------------------------------------|
| Syntax check       | `bash -n bin/mossferry`                             | exit 0, no output                       |
| Full test suite    | `bash tests/run.sh`                                 | ends `tests/test-ui-ops.sh: all ok`, exit 0 |
| Doctor tests only  | `bash tests/test-ui-ops.sh`                         | ends `tests/test-ui-ops.sh: all ok`, exit 0 |
| Lint (if present)  | `shellcheck bin/mossferry`                          | exit 0 (see note)                       |

> **shellcheck note**: `shellcheck` was **not installed** on the machine this
> plan was written on. If it is absent in your environment, `command -v
> shellcheck` prints nothing — that is not a failure; skip the lint gate and
> rely on `bash -n` + the suite. If it IS present, it must pass with no new
> warnings; honor any existing `# shellcheck disable=` directives in the file.

## Scope

**In scope** (the only files you may modify):

- `bin/mossferry` — `cmd_doctor()` only (lines 414–551). Do not touch any other
  function.
- `tests/fake-bin/ssh` — add three env-gated, default-inert hooks.
- `tests/test-ui-ops.sh` — add new test cases `f8`, `f9` (and `f10` only if you
  do optional Step 4).

**Out of scope** (do NOT touch, even though they look related):

- `cmd_update` in `bin/mossferry` — its serial SSH pattern is a **separate**
  finding (PERF-04) that was not selected for this plan. Leave it exactly as is.
- The launch pre-validate path (`launch_remote` / `--validate`) — separate
  concern; do not add `BatchMode`/`ControlMaster` there.
- `bin/repo-session`, `lib/green-ui.sh`, `install.sh` — untouched.
- The existing `_doc_emit` helper (`bin/mossferry:432–455`), the config check
  (457–462), checks 2/3/4/9, and the TTY summary wording (538–548) — do not
  reword any of them. You will edit checks 3, 5, 6, 7, 8 and *insert* a tmux
  check, nothing else.
- Any existing non-TTY token or check ordering — do NOT reorder checks 2→9. The
  new tmux check is *inserted* directly after the `fzf` check; the relative
  order of every pre-existing check is preserved.
- `tests/test-mossferry.sh` — the client contract suite; no doctor assertions
  live there, so it needs no change.

## Git workflow

- Branch: `advisor/07-doctor-overhaul` (create off `main`; do not commit
  directly to `main`).
- Commit style is Conventional Commits (see `git log --oneline`, e.g.
  `chore(demo): …`). Suggested commits: one for the `bin/mossferry` fix, one for
  the test scaffolding + new cases. Example subject:
  `fix(doctor): batchmode every probe, short-circuit, reuse one ssh, check tmux`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

Order matters: Steps 1–2 alone eliminate the hang and are the low-risk core.
Step 3 is the perf win (connection reuse). Step 4 is the additive tmux check.
Step 5 is tests. The codebase stays runnable and byte-stable after each step.

### Step 1: Add a shared `SSH_OPTS` array and put `BatchMode`+`ConnectTimeout` on every remote-connecting probe

**1a.** In `cmd_doctor`, immediately AFTER the existing line 423
(`  local fix_hints=()`), add one new locals line:

```bash
  # Shared options for every remote-connecting probe. BatchMode + ConnectTimeout
  # guarantee no check can ever block on an interactive password prompt — the
  # tool that diagnoses connectivity must never hang. ControlMaster (added in
  # Step 3) reuses ONE ssh handshake across all probes. connect_ok gates the
  # remote checks so they are skipped entirely when the connect probe failed.
  local connect_ok=0
  local -a SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5)
```

(Do NOT add the ControlMaster flags yet — Step 3 appends them to this same
array.)

**1b.** Rewrite check 3 (the connect probe, lines 472–478) to reuse `SSH_OPTS`
and record success in `connect_ok`:

```bash
  # 3. ssh BatchMode connect (opens the shared connection for checks 5–8)
  if ssh "${SSH_OPTS[@]}" "$host" true >/dev/null 2>&1; then
    _doc_emit ok "ssh BatchMode connect to $host"
    connect_ok=1
  else
    _doc_emit FAIL "ssh BatchMode connect to $host"
    failed=1
  fi
```

The emitted messages are unchanged (`ok ssh BatchMode connect to <host>` /
`FAIL ssh BatchMode connect to <host>`); only the connection options moved into
the array and `connect_ok=1` was added.

**1c.** Change every remaining **plain** remote `ssh "$host" …` (checks 5, 6, 7,
8) to `ssh "${SSH_OPTS[@]}" "$host" …`. Step 2 gates them on `connect_ok`, so do
1c and 2 together per check using the final shapes in Step 2. (If you prefer to
verify 1c independently first: just swap `ssh "$host"` → `ssh "${SSH_OPTS[@]}"
"$host"` for checks 5/6/7/8 and run `bash -n bin/mossferry`.)

**Verify (after 1a+1b, before Step 2)**: `bash -n bin/mossferry` → exit 0, no
output.

### Step 2: Short-circuit the remote checks when the connect probe failed

Gate every remote probe on `connect_ok`. When `connect_ok` is 0, the probe is
**not run** (no `ssh`, no hang) and the existing `FAIL`/`info` line is emitted
anyway so the output token shape is unchanged.

**2a.** Check 5 (remote bin, lines 488–494) becomes:

```bash
  # 5. remote FERRY_REMOTE_BIN executable (relative to remote $HOME)
  if (( connect_ok )) && ssh "${SSH_OPTS[@]}" "$host" "test -x $FERRY_REMOTE_BIN || test -x \"\$HOME/$FERRY_REMOTE_BIN\"" >/dev/null 2>&1; then
    _doc_emit ok "remote $FERRY_REMOTE_BIN executable"
  else
    _doc_emit FAIL "remote $FERRY_REMOTE_BIN not executable"
    failed=1
  fi
```

When `connect_ok` is 0, `(( connect_ok ))` is false, `ssh` is never evaluated,
the `else` runs → identical `FAIL remote <bin> not executable` line.

**2b.** Check 6 (VERSION, lines 496–510) becomes — note `v_remote` is now
initialized to empty and the `ssh` only runs when connected:

```bash
  # 6. local vs remote VERSION match
  local v_local v_remote=""
  v_local="$(own_version | tr -d '[:space:]')"
  if (( connect_ok )); then
    v_remote="$(ssh "${SSH_OPTS[@]}" "$host" cat "${FERRY_REMOTE_REPO}/VERSION" 2>/dev/null || true)"
  fi
  v_remote="${v_remote//$'\r'/}"
  v_remote="${v_remote//$'\n'/}"
  v_remote="${v_remote//[[:space:]]/}"
  if [[ -n "$v_remote" && "$v_local" == "$v_remote" ]]; then
    _doc_emit ok "versions match: $v_local"
  else
    _doc_emit FAIL "versions: local $v_local / remote ${v_remote:-unknown}"
    failed=1
    version_failed=1
    fix_hints+=("run: ferry update ${host}")
  fi
```

When `connect_ok` is 0, `v_remote` stays `""` → `${v_remote:-unknown}` → the
existing `FAIL versions: local <v> / remote unknown` line (byte-identical to the
current failure output).

**2c.** Check 7 (fzf, lines 512–517) becomes:

```bash
  # 7. remote fzf (info if missing)
  if (( connect_ok )) && ssh "${SSH_OPTS[@]}" "$host" command -v fzf >/dev/null 2>&1; then
    _doc_emit ok "remote fzf present"
  else
    _doc_emit info "remote fzf missing — numbered menu fallback available"
  fi
```

When `connect_ok` is 0 → the existing `info remote fzf missing …` line. (Like
today, missing fzf does not set `failed` — leave it that way.)

**2d.** Check 8 (mosh-server count, lines 519–524) becomes:

```bash
  # 8. remote mosh-server count (info)
  local count=""
  if (( connect_ok )); then
    count="$(ssh "${SSH_OPTS[@]}" "$host" pgrep -c mosh-server 2>/dev/null || true)"
  fi
  count="${count//$'\n'/}"
  : "${count:=0}"
  _doc_emit info "remote mosh-server count: $count"
```

When `connect_ok` is 0 → `count` empty → `0` → the existing `info remote
mosh-server count: 0` line.

**Verify**: `bash -n bin/mossferry` → exit 0. Then
`bash tests/test-ui-ops.sh` → ends `tests/test-ui-ops.sh: all ok`, exit 0.
(f1 all-ok and f1 version-mismatch fixtures still pass because their fake `ssh`
answers the connect probe as reachable, so `connect_ok` becomes 1 and every
probe runs exactly as before.)

### Step 3: Reuse ONE SSH handshake across all probes via ControlMaster

This is the perf win (PERF-02). It keeps every per-check `ssh` call — and thus
every per-check output line — **exactly as in Steps 1–2**, so it introduces
zero byte-stability risk; it only adds connection-reuse options.

**3a.** Change the `SSH_OPTS` initializer from Step 1a to append the
ControlMaster options:

```bash
  local -a SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 \
    -o ControlMaster=auto -o "ControlPath=/tmp/ferry-cm-$$-%C" \
    -o ControlPersist=15s)
```

Rationale for the socket path: `%C` expands to a short fixed-length connection
hash, keeping the path well under macOS's ~104-char `AF_UNIX` socket-path limit
even though this is the low-risk win. `$$` scopes the socket to this process so
concurrent `doctor` runs never collide. The connect probe (check 3) opens the
master; checks 5/6/7/tmux/8 reuse it (no new handshake); `ControlPersist=15s`
lets any straggler reuse it briefly before it self-closes.

**3b.** Add a best-effort master teardown right BEFORE the `# TTY summary + fix
hints` block (i.e. before line 537, Excerpt C):

```bash
  # Close the shared master connection (best-effort; no-op if never opened).
  if (( connect_ok )); then
    ssh -O exit -o "ControlPath=/tmp/ferry-cm-$$-%C" "$host" >/dev/null 2>&1 || true
  fi
```

**If ControlMaster proves fiddly** (e.g. `bash -n` is fine but the suite regresses
in a way you trace to the added `-o` flags, or you cannot construct the socket
path safely): **SKIP Step 3 entirely** — revert 3a to the Step-1a two-element
array and drop 3b. Steps 1+2+4 already fix the hang (the P1 bug); connection
reuse is a bonus. Record the skip in your final report and in the plan status.
Do NOT substitute a single `ssh … sh -s` round trip instead — see STOP
conditions (it would break the `f1` version-mismatch fixture, which matches the
`ssh` argv for `cat VERSION`).

**Verify**: `bash -n bin/mossferry` → exit 0. `bash tests/test-ui-ops.sh` →
`all ok`. (The fake `ssh` ignores the `-o` flags — it only logs argv and
pattern-matches — so the ControlMaster flags are inert in tests and every
existing assertion still holds.)

### Step 4: Add the remote-`tmux` check

Insert a NEW check **immediately after** check 7 (fzf) and **before** check 8
(mosh-server count). This preserves the relative order of every existing check.

```bash
  # 7b. remote tmux (the hard dependency of the remote brain — FAIL if absent)
  if (( connect_ok )) && ssh "${SSH_OPTS[@]}" "$host" command -v tmux >/dev/null 2>&1; then
    _doc_emit ok "remote tmux present"
  else
    _doc_emit FAIL "remote tmux missing"
    failed=1
  fi
```

Notes:
- New non-TTY tokens: `ok remote tmux present` and `FAIL remote tmux missing`.
  You will assert these in Step 5 (f9). Do NOT change this wording afterward
  without updating f9.
- When `connect_ok` is 0, this emits `FAIL remote tmux missing` without an SSH
  (consistent with the other short-circuited checks).
- Optional (NOT required; skip unless you have time and stay byte-safe): a
  minor-version warning parsed from `tmux -V`. It would need its own reuse of
  `SSH_OPTS` and a new `info` line; because it risks a new asserted token and
  buys little, this plan **defers it** to Maintenance. Do not add it as part of
  meeting the Done criteria.

**Verify**: `bash -n bin/mossferry` → exit 0. `bash tests/test-ui-ops.sh` →
`all ok` (f1 all-ok still passes — the default fake `ssh` answers `command -v
tmux` with exit 0, so the new line is `ok remote tmux present`, and f1 only
asserts the `ok versions match:` token + zero ANSI).

### Step 5: Tests — hang-safety, short-circuit, and the tmux check

Add three env-gated hooks to the fake `ssh`, then two new cases to
`tests/test-ui-ops.sh` (f8, f9). All hooks are **default-inert** — they change
nothing unless a doctor test sets their env var, so the existing suite is
unaffected.

**5a. Extend `tests/fake-bin/ssh`.** The current stub logs each call and
pattern-matches argv (read it fully first). Add hooks at two points.

Point ① — right after the line `joined="$*"` (line 5), before the
`# Pre-validation` block:

```bash
# --- doctor test hooks (env-gated; inert unless a doctor test sets these) ---
# A host that requires an interactive password: any CONNECTING ssh invoked
# WITHOUT BatchMode=yes blocks, exactly as a real password prompt would. `ssh -G`
# is a local config resolver (never connects) and is exempt. With the doctor fix
# in place, every remote probe carries BatchMode=yes, so this never fires.
if [[ -n "${FAKE_SSH_REQUIRE_BATCH:-}" && "$1" != "-G" && "$joined" != *"BatchMode=yes"* ]]; then
  sleep 30
fi
# Simulate an unreachable / no-key host: fail ONLY the BatchMode connectivity
# probe (`ssh <opts> <host> true`), leaving `ssh -G` resolution intact so the
# earlier checks still pass and the SHORT-CIRCUIT path is what gets exercised.
if [[ -n "${FAKE_SSH_CONNECT_FAIL:-}" && "$joined" == *BatchMode* && "$joined" == *" true" ]]; then
  exit 255
fi
```

Point ② — right after the `cat … VERSION` block (after line 50), before the
final `exit 0`:

```bash
# Remote tmux presence toggle for the doctor tmux check.
if [[ -n "${FAKE_SSH_NO_TMUX:-}" && "$joined" == *"command -v tmux"* ]]; then
  exit 1
fi
```

Document these three vars in a one-line comment near the top of the stub (the
existing header comment block is a fine place):
`# FAKE_SSH_REQUIRE_BATCH / FAKE_SSH_CONNECT_FAIL / FAKE_SSH_NO_TMUX: doctor test hooks.`

**5b. Add case f8 (hang-safety + short-circuit)** to `tests/test-ui-ops.sh`,
before the final `if [[ $fail -ne 0 ]]; then` tail (before line 410). Model it
on the f1 block's structure (`mktemp` HOME/log/out/err, `export HOME …
FAKE_NET_LOG … PATH="${FAKE_BIN}:${PATH}"`, `set +e … rc=$? … set -e`). Target
shape:

```bash
# ---------------------------------------------------------------------------
# f8: doctor never hangs on a password-only host; short-circuits after a
#     failed connect (no remote probe SSH is attempted)
# ---------------------------------------------------------------------------
{
  name=f8
  home="$(mktemp -d)"; logf="$(mktemp)"; outf="$(mktemp)"; errf="$(mktemp)"
  export HOME="$home" FAKE_NET_LOG="$logf" PATH="${FAKE_BIN}:${PATH}"

  # (a) healthy host, but the stub would BLOCK any non-BatchMode connecting ssh.
  #     With the fix every probe carries BatchMode, so doctor completes fast.
  : >"$logf"
  set +e
  FAKE_SSH_REQUIRE_BATCH=1 timeout 8 "$FERRY" doctor h >"$outf" 2>"$errf"
  rc=$?
  set -e
  out="$(cat "$outf")"
  if [[ $rc -ne 124 && $rc -eq 0 \
        && "$out" == *"ok versions match: ${VERSION}"* ]]; then
    ok "${name}-no-hang"
  else
    FAIL "${name}-no-hang (rc=$rc)"
    printf '  out=%s\n' "$(printf %q "$out")" >&2
  fi

  # (b) connect fails (no key auth): remaining remote checks must be SKIPPED
  #     (no ssh) and emit their FAIL/info lines without hanging.
  : >"$logf"
  set +e
  FAKE_SSH_CONNECT_FAIL=1 FAKE_SSH_REQUIRE_BATCH=1 \
    timeout 8 "$FERRY" doctor h >"$outf" 2>"$errf"
  rc=$?
  set -e
  out="$(cat "$outf")"
  log="$(cat "$logf")"
  no_probe=1
  for needle in "test -x" "command -v" "pgrep" "cat Repositories"; do
    if [[ "$log" == *"$needle"* ]]; then no_probe=0; fi
  done
  if [[ $rc -ne 124 && $rc -ne 0 \
        && "$out" == *"FAIL ssh BatchMode connect to h"* \
        && "$out" == *"FAIL versions: local ${VERSION} / remote unknown"* \
        && $no_probe -eq 1 ]]; then
    ok "${name}-short-circuit"
  else
    FAIL "${name}-short-circuit (rc=$rc no_probe=$no_probe)"
    printf '  out=%s\n  log=%s\n' "$(printf %q "$out")" "$(printf %q "$log")" >&2
  fi

  rm -rf "$home" "$outf" "$errf" "$logf"
}
```

> Why the `no_probe` needles are safe: after a failed connect, checks 5/6/7/8 +
> tmux are all short-circuited, so the log must contain **no** `test -x`,
> `command -v`, `pgrep`, or `cat Repositories/…/VERSION` argv line. The only
> remote-touching lines left are the two `ssh -G` resolver calls (checks 2 and
> 9) and the failed BatchMode `… true` connect — none of those contain the
> needles. If Step 3's ControlMaster teardown ran, its argv is `-O exit …
> ControlPath …` — also free of the needles. (Teardown is gated on
> `connect_ok`, which is 0 here, so it does not even run.)

**5c. Add case f9 (remote tmux present / absent)** likewise before the tail:

```bash
# ---------------------------------------------------------------------------
# f9: doctor checks remote tmux — ok when present, FAIL when absent
# ---------------------------------------------------------------------------
{
  name=f9
  home="$(mktemp -d)"; logf="$(mktemp)"; outf="$(mktemp)"; errf="$(mktemp)"
  export HOME="$home" FAKE_NET_LOG="$logf" PATH="${FAKE_BIN}:${PATH}"

  # present (default stub answers command -v tmux with exit 0)
  : >"$logf"
  set +e
  "$FERRY" doctor h >"$outf" 2>"$errf"
  rc=$?
  set -e
  out="$(cat "$outf")"
  if [[ $rc -eq 0 && "$out" == *"ok remote tmux present"* ]]; then
    ok "${name}-tmux-present"
  else
    FAIL "${name}-tmux-present (rc=$rc)"
    printf '  out=%s\n' "$(printf %q "$out")" >&2
  fi

  # absent
  : >"$logf"
  set +e
  FAKE_SSH_NO_TMUX=1 "$FERRY" doctor h >"$outf" 2>"$errf"
  rc=$?
  set -e
  out="$(cat "$outf")"
  if [[ $rc -ne 0 \
        && "$out" == *"FAIL remote tmux missing"* \
        && "$out" == *"ok versions match: ${VERSION}"* ]]; then
    ok "${name}-tmux-absent"
  else
    FAIL "${name}-tmux-absent (rc=$rc)"
    printf '  out=%s\n' "$(printf %q "$out")" >&2
  fi

  rm -rf "$home" "$outf" "$errf" "$logf"
}
```

**5d. (Optional — ONLY if you did Step 3) Add case f10 (connection reuse
configured).** Because the fake `ssh` cannot emulate real multiplexing, assert
the *evidence of reuse*: every remote probe carries the shared `ControlPath`.

```bash
# ---------------------------------------------------------------------------
# f10: doctor probes share ONE ssh connection (ControlPath on every remote call)
# ---------------------------------------------------------------------------
{
  name=f10
  home="$(mktemp -d)"; logf="$(mktemp)"; outf="$(mktemp)"; errf="$(mktemp)"
  export HOME="$home" FAKE_NET_LOG="$logf" PATH="${FAKE_BIN}:${PATH}"
  : >"$logf"
  set +e
  "$FERRY" doctor h >"$outf" 2>"$errf"
  set -e
  log="$(cat "$logf")"
  # Every line that runs a remote command (has BatchMode) must carry ControlPath.
  bad=0
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == *"BatchMode=yes"* ]] || continue
    [[ "$l" == *"ControlPath="* ]] || bad=1
  done <<<"$log"
  if [[ $bad -eq 0 ]] && [[ "$log" == *"ControlPath="* ]]; then
    ok "${name}-reuse"
  else
    FAIL "${name}-reuse (bad=$bad)"
    printf '  log=%s\n' "$(printf %q "$log")" >&2
  fi
  rm -rf "$home" "$outf" "$errf" "$logf"
}
```

If you SKIPPED Step 3, do **not** add f10 (there is no `ControlPath` to assert);
note the skip.

**Verify (whole plan)**: `bash tests/run.sh` → ends `tests/test-ui-ops.sh: all
ok`, exit 0, and the run includes new `ok f8-…`, `ok f9-…` (and `ok f10-reuse`
if Step 3 done) lines.

## Test plan

- New tests, all in `tests/test-ui-ops.sh`, modeled structurally on the existing
  `f1` block:
  - `f8-no-hang`: healthy host under `FAKE_SSH_REQUIRE_BATCH=1` completes within
    `timeout 8` (rc ≠ 124), rc 0, `ok versions match:` present — proves every
    probe carries `BatchMode`.
  - `f8-short-circuit`: `FAKE_SSH_CONNECT_FAIL=1` → rc ≠ 124 (no hang), rc ≠ 0,
    `FAIL ssh BatchMode connect` + `FAIL versions: … remote unknown` present, and
    the SSH log contains **no** `test -x` / `command -v` / `pgrep` / `cat
    Repositories` probe line — proves the short-circuit.
  - `f9-tmux-present`: default stub → `ok remote tmux present`, rc 0.
  - `f9-tmux-absent`: `FAKE_SSH_NO_TMUX=1` → `FAIL remote tmux missing`, rc ≠ 0,
    other checks (`ok versions match:`) still pass.
  - `f10-reuse` (only if Step 3 done): every `BatchMode` ssh log line also
    carries `ControlPath=`.
- Scaffolding: three env-gated hooks in `tests/fake-bin/ssh`
  (`FAKE_SSH_REQUIRE_BATCH`, `FAKE_SSH_CONNECT_FAIL`, `FAKE_SSH_NO_TMUX`),
  default-inert so `t*`, `m*`, and existing `f*` cases are unaffected.
- Regression guard: the existing `f1` (non-TTY tokens, forced-TTY chrome,
  version-mismatch fix-hint) and `f6` (kit-absent doctor rc 0) MUST still pass
  unchanged — do not edit them.
- Verification: `bash tests/run.sh` → `all ok`, exit 0.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash -n bin/mossferry` exits 0.
- [ ] `bash -n tests/fake-bin/ssh` exits 0.
- [ ] Every remote-connecting `ssh` in `cmd_doctor` (checks 3, 5, 6, 7, the new
      tmux check, 8) uses `"${SSH_OPTS[@]}"` (which contains `BatchMode=yes` and
      `ConnectTimeout=5`). Confirm: `grep -n 'ssh "\${SSH_OPTS\[@\]}"' bin/mossferry`
      returns 6 lines inside `cmd_doctor`; `grep -n 'ssh "\$host"' bin/mossferry`
      returns **no** line inside `cmd_doctor` (only the `ssh -G` resolver calls
      and, if Step 3 done, the `ssh -O exit` teardown remain without `SSH_OPTS`).
- [ ] Checks 5, 6, 7, tmux, 8 are each gated on `(( connect_ok ))` (or, for 6/8,
      the `ssh` is inside an `if (( connect_ok ))`).
- [ ] `bash tests/run.sh` exits 0 and ends with `tests/test-ui-ops.sh: all ok`;
      the output contains `ok f8-no-hang`, `ok f8-short-circuit`,
      `ok f9-tmux-present`, `ok f9-tmux-absent` (and `ok f10-reuse` iff Step 3
      was done).
- [ ] Existing `ok f1-nontty-tokens`, `ok f1-forced-tty-chrome`,
      `ok f1-fail-hint`, `ok f6-kit-absent` still print (no regression).
- [ ] If `shellcheck` is installed: `shellcheck bin/mossferry` exits 0 with no
      new warnings. If absent, this box is N/A.
- [ ] `git status` shows only `bin/mossferry`, `tests/fake-bin/ssh`, and
      `tests/test-ui-ops.sh` modified — no other files.
- [ ] `plans/README.md` status row updated **iff** that file exists.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at lines 421–535 of `bin/mossferry` does not match Excerpts A/B/C
  (drift since this plan was written).
- You find doctor assertions in `tests/test-mossferry.sh`, or the doctor tests
  are no longer in `tests/test-ui-ops.sh` as `f1`/`f6` (test layout drifted).
- Preserving byte-stable non-TTY tokens forces you toward a single `ssh … sh -s`
  round trip that changes any existing check token or the check order. **Do not
  take that path** — it also breaks the `f1` version-mismatch fixture (which
  matches the `ssh` argv for `cat VERSION`). Prefer ControlMaster reuse (Step 3),
  which keeps per-check calls, or ship Steps 1+2+4 without Step 3. If you believe
  the round-trip collapse is unavoidable, STOP and report instead.
- Any existing `t*`, `m*`, `f1`–`f7` assertion regresses and you cannot trace it
  to your change and fix it within two attempts.
- You discover a repo/`~/.ssh/config` SSH-multiplexing convention that
  contradicts the self-contained ControlMaster socket this plan prescribes.
- `bash -n` passes but `bash tests/run.sh` fails twice after a reasonable fix
  attempt.

## Maintenance notes

For whoever owns `cmd_doctor` next:

- **The `SSH_OPTS` array is the single source of truth** for how doctor connects.
  Any future remote check MUST be written as `ssh "${SSH_OPTS[@]}" "$host" …`
  and gated on `(( connect_ok ))`, or it reintroduces the password-hang and the
  extra-handshake regressions this plan removed. Do not use bare `ssh "$host"`
  in doctor again (except `ssh -G`, which is a local resolver and intentionally
  bare).
- **Deferred: `tmux -V` minor-version warning.** Step 4 checks only tmux
  *presence*. A follow-up could parse `tmux -V` (reusing `SSH_OPTS`) and emit an
  `info`/`FAIL` when below a known-good minor. It was deferred because it adds a
  new asserted token for little value; add it as its own small plan with its own
  test if desired.
- **Deferred: `cmd_update` handshake batching (finding PERF-04).** `cmd_update`
  has the same serial-SSH shape and would benefit from the same `SSH_OPTS` /
  ControlMaster treatment. It was explicitly out of scope here; a separate plan
  should apply the identical pattern.
- **Reviewer focus**: (1) confirm no non-TTY token changed — diff the non-TTY
  doctor output before/after on a mock host and expect only the added
  `ok remote tmux present` line; (2) confirm the short-circuit emits the same
  `FAIL`/`info` strings as a live-but-failing probe would; (3) confirm the
  `tests/fake-bin/ssh` hooks are all env-gated and cannot alter default-suite
  behavior (run `bash tests/run.sh` with none of the FAKE_SSH_* vars set).
- **macOS caveat for ControlMaster**: the `ControlPath` uses `%C` specifically to
  stay under the ~104-char `AF_UNIX` socket-path limit on macOS. If you ever
  change the path, keep it short and keep `%C` (or another fixed-length token).
```
