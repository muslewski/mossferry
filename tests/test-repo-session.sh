#!/usr/bin/env bash
# tests for bin/repo-session (Task 1). Plain bash; no framework.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RS="$ROOT/bin/repo-session"
FAKE="$ROOT/tests/fake-tmux"
VERSION_FILE="$ROOT/VERSION"
FAIL=0

ok()  { printf 'ok %s\n' "$1"; }
fail(){ printf 'FAIL %s — %s\n' "$1" "$2"; FAIL=1; }

# Shared arrange: temp HOME with config dir, temp repo base, log file.
setup() {
  export TMPDIR="${TEST_TMPDIR_ROOT:-/tmp}"
  export HOME="$(mktemp -d "${TMPDIR}/moshi-home.XXXXXX")"
  _TEST_TMP="$(mktemp -d "${TMPDIR}/moshi-tmp.XXXXXX")"
  export TMPDIR="$_TEST_TMP"
  export MOSHI_REPO_BASE="$(mktemp -d "${TMPDIR}/moshi-base.XXXXXX")"
  export FAKE_TMUX_LOG="$(mktemp "${TMPDIR}/moshi-log.XXXXXX")"
  export REPO_SESSION_TMUXBIN="$FAKE"
  unset MOSHI_NO_FZF 2>/dev/null || true
  unset REPO_SESSION_LIB 2>/dev/null || true
  : >"$FAKE_TMUX_LOG"
  export FAKE_TMUX_SESSIONS=""
  export FAKE_TMUX_META=""
  mkdir -p "$HOME/.config/moshi"
}

teardown() {
  local home="${HOME:-}" tmp="${_TEST_TMP:-}" base="${MOSHI_REPO_BASE:-}" log="${FAKE_TMUX_LOG:-}"
  export TMPDIR="${TEST_TMPDIR_ROOT:-/tmp}"
  unset _TEST_TMP MOSHI_REPO_BASE FAKE_TMUX_LOG MOSHI_NO_FZF REPO_SESSION_LIB 2>/dev/null || true
  rm -rf "$home" "$tmp" "$base" 2>/dev/null || true
  rm -f "$log" 2>/dev/null || true
}

# ---- t1: typo'd repo → exit 1, message, no new-session ----
t1() {
  setup
  local out rc log
  out=$(bash "$RS" nope 2>&1)
  rc=$?
  log=$(cat "$FAKE_TMUX_LOG")
  if [[ $rc -eq 1 ]] && [[ "$out" == *"no repo 'nope'"* ]] && ! grep -q 'new-session' <<<"$log"; then
    ok t1
  else
    fail t1 "rc=$rc out=[$out] log=[$log]"
  fi
  teardown
}

# ---- t2: client-version mismatch warns ----
t2() {
  setup
  local err
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|win|1w detached bash"
  err=$(bash "$RS" --client-version 0.0.1 --list 2>&1 >/dev/null)
  if [[ "$err" == *"run 'moshi update'"* ]]; then
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
  if [[ "$err" != *"moshi update"* ]]; then
    ok t3
  else
    fail t3 "stderr unexpectedly contains update: [$err]"
  fi
  teardown
}

# ---- t4: --primary with no sessions creates + attaches ----
t4() {
  setup
  local log
  mkdir -p "$MOSHI_REPO_BASE/myrepo"
  export FAKE_TMUX_SESSIONS=""
  bash "$RS" myrepo --primary >/dev/null 2>&1
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'new-session -d -s myrepo' <<<"$log" && grep -q 'attach -t myrepo' <<<"$log"; then
    ok t4
  else
    fail t4 "log=[$log]"
  fi
  teardown
}

# ---- t5: default action zero-session fast path ----
t5() {
  setup
  local out log
  mkdir -p "$MOSHI_REPO_BASE/myrepo"
  export FAKE_TMUX_SESSIONS=""
  out=$(bash "$RS" myrepo 2>&1)
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'new-session -d -s myrepo' <<<"$log" \
     && grep -q 'attach -t myrepo' <<<"$log" \
     && [[ "$out" == *"created primary"* ]]; then
    ok t5
  else
    fail t5 "out=[$out] log=[$log]"
  fi
  teardown
}

# ---- t6: numbered menu attaches second session ----
t6() {
  setup
  local log last_attach
  mkdir -p "$MOSHI_REPO_BASE/myrepo"
  export MOSHI_NO_FZF=1
  export FAKE_TMUX_SESSIONS=$'myrepo\nmyrepo-2'
  export FAKE_TMUX_META=$'myrepo|w1|1w detached bash\nmyrepo-2|w2|1w detached bash'
  printf '2\n' | bash "$RS" myrepo >/dev/null 2>&1
  log=$(cat "$FAKE_TMUX_LOG")
  last_attach=$(grep 'attach' <<<"$log" | tail -1)
  if [[ "$last_attach" == *'myrepo-2'* ]]; then
    ok t6
  else
    fail t6 "last_attach=[$last_attach] log=[$log]"
  fi
  teardown
}

# ---- t7: global zero-session picker quit → 130 ----
t7() {
  setup
  local rc log
  export MOSHI_NO_FZF=1
  export FAKE_TMUX_SESSIONS=""
  printf 'q\n' | bash "$RS" >/dev/null 2>&1
  rc=$?
  log=$(cat "$FAKE_TMUX_LOG")
  if [[ $rc -eq 130 ]] && ! grep -q 'attach' <<<"$log"; then
    ok t7
  else
    fail t7 "rc=$rc log=[$log]"
  fi
  teardown
}

# ---- t8: REPO_SESSION_LIB build_session_rows ----
t8() {
  setup
  local rows n f1 f2
  export FAKE_TMUX_SESSIONS=$'alpha\nbeta'
  export FAKE_TMUX_META=$'alpha|Awin|2w attached claude\nbeta|Bwin|1w detached bash'
  export REPO_SESSION_TMUXBIN="$FAKE"
  rows=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    build_session_rows
  )
  n=$(printf '%s\n' "$rows" | grep -c . || true)
  f1=$(printf '%s\n' "$rows" | head -1 | cut -f1)
  f2=$(printf '%s\n' "$rows" | sed -n '2p' | cut -f1)
  if [[ $n -eq 2 ]] && [[ "$f1" == "alpha" ]] && [[ "$f2" == "beta" ]] \
     && [[ "$(printf '%s\n' "$rows" | head -1)" == *$'\t'* ]]; then
    ok t8
  else
    fail t8 "n=$n rows=[$rows]"
  fi
  teardown
}

# ---- t9: unknown flag warns; list still works ----
t9() {
  setup
  local out
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|win|1w detached bash"
  out=$(bash "$RS" --bogus --list 2>&1)
  if [[ "$out" == *"ignoring unknown flag '--bogus'"* ]] && [[ "$out" == *"s1"* ]]; then
    ok t9
  else
    fail t9 "out=[$out]"
  fi
  teardown
}

# ---- t10: --resume-closed claim + attach -d ----
t10() {
  setup
  local log
  mkdir -p "$MOSHI_REPO_BASE/myrepo"
  export FAKE_TMUX_SESSIONS="myrepo"
  export FAKE_TMUX_META="myrepo|w|1w detached bash"
  bash "$RS" myrepo --resume-closed >/dev/null 2>&1
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -qE 'set-option .*@claim_ts' <<<"$log" && grep -q 'attach -d -t' <<<"$log"; then
    ok t10
  else
    fail t10 "log=[$log]"
  fi
  teardown
}

# ---- t11: MOSHI_REPO_BASE env wins (custom base) ----
t11() {
  setup
  local custom log rc
  custom="$(mktemp -d "${TEST_TMPDIR_ROOT:-/tmp}/moshi-custom.XXXXXX")"
  mkdir -p "$custom/customrepo"
  # Only under custom base — baseline hardcodes $HOME/Repositories so this fails until env wins.
  export MOSHI_REPO_BASE="$custom"
  export FAKE_TMUX_SESSIONS=""
  bash "$RS" customrepo --primary >/dev/null 2>&1
  rc=$?
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'new-session -d -s customrepo' <<<"$log" && grep -q 'attach -t customrepo' <<<"$log"; then
    ok t11
  else
    fail t11 "rc=$rc log=[$log]"
  fi
  rm -rf "$custom"
  teardown
}

# ---- t12: fallback new-session chain n then 1 ----
t12() {
  setup
  local log
  mkdir -p "$MOSHI_REPO_BASE/myrepo"
  export MOSHI_NO_FZF=1
  export FAKE_TMUX_SESSIONS=""
  printf 'n\n1\n' | bash "$RS" >/dev/null 2>&1
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'new-session -d -s myrepo' <<<"$log" && grep -q 'attach -t myrepo' <<<"$log"; then
    ok t12
  else
    fail t12 "log=[$log]"
  fi
  teardown
}

export TEST_TMPDIR_ROOT="${TMPDIR:-/tmp}"
set +e
t1; t2; t3; t4; t5; t6; t7; t8; t9; t10; t11; t12
exit $FAIL
