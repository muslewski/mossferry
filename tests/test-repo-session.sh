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
  export HOME="$(mktemp -d "${TMPDIR}/ferry-home.XXXXXX")"
  _TEST_TMP="$(mktemp -d "${TMPDIR}/ferry-tmp.XXXXXX")"
  export TMPDIR="$_TEST_TMP"
  export FERRY_REPO_BASE="$(mktemp -d "${TMPDIR}/ferry-base.XXXXXX")"
  export FAKE_TMUX_LOG="$(mktemp "${TMPDIR}/ferry-log.XXXXXX")"
  export REPO_SESSION_TMUXBIN="$FAKE"
  unset FERRY_NO_FZF 2>/dev/null || true
  unset REPO_SESSION_LIB 2>/dev/null || true
  : >"$FAKE_TMUX_LOG"
  export FAKE_TMUX_SESSIONS=""
  export FAKE_TMUX_META=""
  export FAKE_TMUX_WINDOWS=""
  unset FERRY_HIDDEN_WINDOW_GLOB 2>/dev/null || true
  mkdir -p "$HOME/.config/mossferry"
}

teardown() {
  local home="${HOME:-}" tmp="${_TEST_TMP:-}" base="${FERRY_REPO_BASE:-}" log="${FAKE_TMUX_LOG:-}"
  export TMPDIR="${TEST_TMPDIR_ROOT:-/tmp}"
  unset _TEST_TMP FERRY_REPO_BASE FAKE_TMUX_LOG FERRY_NO_FZF REPO_SESSION_LIB 2>/dev/null || true
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

# ---- t4: --primary with no sessions creates + attaches ----
t4() {
  setup
  local log
  mkdir -p "$FERRY_REPO_BASE/myrepo"
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
  mkdir -p "$FERRY_REPO_BASE/myrepo"
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
  mkdir -p "$FERRY_REPO_BASE/myrepo"
  export FERRY_NO_FZF=1
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
  export FERRY_NO_FZF=1
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

# ---- t8: REPO_SESSION_LIB build_session_rows (6-field format) ----
t8() {
  setup
  local rows n f1 f2 fields preview
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
  fields=$(printf '%s\n' "$rows" | head -1 | awk -F'\t' '{print NF}')
  preview=$(printf '%s\n' "$rows" | head -1 | cut -f6)
  if [[ $n -eq 2 ]] && [[ "$f1" == "alpha" ]] && [[ "$f2" == "beta" ]] \
     && [[ "$fields" -eq 6 ]] && [[ "$preview" == "alpha:0" ]]; then
    ok t8
  else
    fail t8 "n=$n fields=$fields preview=[$preview] rows=[$rows]"
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
  mkdir -p "$FERRY_REPO_BASE/myrepo"
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

# ---- t11: FERRY_REPO_BASE env wins (custom base) ----
t11() {
  setup
  local custom log rc
  custom="$(mktemp -d "${TEST_TMPDIR_ROOT:-/tmp}/ferry-custom.XXXXXX")"
  mkdir -p "$custom/customrepo"
  # Only under custom base — baseline hardcodes $HOME/Repositories so this fails until env wins.
  export FERRY_REPO_BASE="$custom"
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
  mkdir -p "$FERRY_REPO_BASE/myrepo"
  export FERRY_NO_FZF=1
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

# ---- t13: --validate goodrepo → exit 0, silent, no tmux ----
t13() {
  setup
  local out rc log
  mkdir -p "$FERRY_REPO_BASE/goodrepo"
  out=$(bash "$RS" --validate goodrepo 2>&1)
  rc=$?
  log=$(cat "$FAKE_TMUX_LOG")
  if [[ $rc -eq 0 ]] && [[ -z "$out" ]] && [[ -z "$log" ]]; then
    ok t13
  else
    fail t13 "rc=$rc out=[$out] log=[$log]"
  fi
  teardown
}

# ---- t14: --validate nope → exit 1, message + list, no tmux ----
t14() {
  setup
  local out rc log
  mkdir -p "$FERRY_REPO_BASE/other"
  out=$(bash "$RS" --validate nope 2>&1)
  rc=$?
  log=$(cat "$FAKE_TMUX_LOG")
  if [[ $rc -eq 1 ]] && [[ "$out" == *"no repo 'nope'"* ]] \
     && [[ "$out" == *"other"* ]] && [[ -z "$log" ]]; then
    ok t14
  else
    fail t14 "rc=$rc out=[$out] log=[$log]"
  fi
  teardown
}

# ---- t15: hidden active window → display first non-hidden + preview_target ----
t15() {
  setup
  local rows name win preview
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|_curtain|2w detached bash"
  export FAKE_TMUX_WINDOWS=$'s1:0:_curtain\ns1:1:Syndcast Backlog'
  export REPO_SESSION_TMUXBIN="$FAKE"
  rows=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    build_session_rows
  )
  name=$(printf '%s\n' "$rows" | cut -f1)
  win=$(printf '%s\n' "$rows" | cut -f2)
  preview=$(printf '%s\n' "$rows" | cut -f6)
  if [[ "$name" == "s1" ]] && [[ "$win" == "Syndcast Backlog" ]] \
     && [[ "$preview" == "s1:1" ]]; then
    ok t15
  else
    fail t15 "rows=[$rows]"
  fi
  teardown
}

# ---- t16: all windows hidden → keep active name ----
t16() {
  setup
  local rows win preview
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|_curtain|2w detached bash"
  export FAKE_TMUX_WINDOWS=$'s1:0:_curtain\ns1:1:_hidden'
  export REPO_SESSION_TMUXBIN="$FAKE"
  rows=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    build_session_rows
  )
  win=$(printf '%s\n' "$rows" | cut -f2)
  preview=$(printf '%s\n' "$rows" | cut -f6)
  if [[ "$win" == "_curtain" ]] && [[ "$preview" == "s1:0" ]]; then
    ok t16
  else
    fail t16 "rows=[$rows]"
  fi
  teardown
}

# ---- t17: FERRY_HIDDEN_WINDOW_GLOB env override ----
t17() {
  setup
  local rows win
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|_curtain|2w detached bash"
  export FAKE_TMUX_WINDOWS=$'s1:0:_curtain\ns1:1:Syndcast Backlog'
  export FERRY_HIDDEN_WINDOW_GLOB="zzz*"
  export REPO_SESSION_TMUXBIN="$FAKE"
  rows=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    build_session_rows
  )
  win=$(printf '%s\n' "$rows" | cut -f2)
  if [[ "$win" == "_curtain" ]]; then
    ok t17
  else
    fail t17 "rows=[$rows]"
  fi
  teardown
}

# ---- t18: LIB picker_kill ----
t18() {
  setup
  local log
  export REPO_SESSION_TMUXBIN="$FAKE"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    picker_kill s1
  )
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'kill-session -t =s1' <<<"$log"; then
    ok t18
  else
    fail t18 "log=[$log]"
  fi
  teardown
}

# ---- t19: LIB picker_rename ----
t19() {
  setup
  local log
  export REPO_SESSION_TMUXBIN="$FAKE"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    picker_rename s1 newname
  )
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'rename-session -t =s1 newname' <<<"$log"; then
    ok t19
  else
    fail t19 "log=[$log]"
  fi
  teardown
}

export TEST_TMPDIR_ROOT="${TMPDIR:-/tmp}"
set +e
t1; t2; t3; t4; t5; t6; t7; t8; t9; t10; t11; t12
t13; t14; t15; t16; t17; t18; t19
exit $FAIL
