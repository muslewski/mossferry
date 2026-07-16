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

# ---- t20: --list applies hidden-window display rule ----
t20() {
  setup
  local out
  export FAKE_TMUX_SESSIONS="s1"
  export FAKE_TMUX_META="s1|_curtain|2w detached bash"
  export FAKE_TMUX_WINDOWS=$'s1:0:_curtain\ns1:1:Real Name'
  out=$(bash "$RS" --list 2>/dev/null)
  if [[ "$out" == *"Real Name"* ]] && [[ "$out" != *"_curtain"* ]]; then
    ok t20
  else
    fail t20 "out=[$out]"
  fi
  teardown
}

# ---- t21: create_repo side-quest → dir + .git under mktemp base ----
t21() {
  setup
  local rc dir
  export REPO_SESSION_TMUXBIN="$FAKE"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    create_repo side-quest
  )
  rc=$?
  dir="$FERRY_REPO_BASE/side-quest"
  if [[ $rc -eq 0 ]] && [[ -d "$dir" ]] && [[ -d "$dir/.git" ]]; then
    ok t21
  else
    fail t21 "rc=$rc dir=[$dir] exists=$([[ -d "$dir" ]] && echo y || echo n) git=$([[ -d "$dir/.git" ]] && echo y || echo n)"
  fi
  teardown
}

# ---- t22: create_repo invalid names → nonzero, nothing created ----
t22() {
  setup
  local rc1 rc2 base_before base_after
  export REPO_SESSION_TMUXBIN="$FAKE"
  base_before=$(ls -1A "$FERRY_REPO_BASE" 2>/dev/null | wc -l)
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    create_repo '../evil'
  )
  rc1=$?
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    create_repo 'has space'
  )
  rc2=$?
  base_after=$(ls -1A "$FERRY_REPO_BASE" 2>/dev/null | wc -l)
  if [[ $rc1 -ne 0 ]] && [[ $rc2 -ne 0 ]] && [[ "$base_before" -eq "$base_after" ]] \
     && [[ ! -e "$FERRY_REPO_BASE/../evil" || ! -d "$FERRY_REPO_BASE/evil" ]]; then
    # nothing under base; path traversal must not create either
    if [[ ! -d "$FERRY_REPO_BASE/evil" ]] && [[ ! -d "$FERRY_REPO_BASE/has space" ]]; then
      ok t22
    else
      fail t22 "unexpected dirs under base"
    fi
  else
    fail t22 "rc1=$rc1 rc2=$rc2 before=$base_before after=$base_after"
  fi
  teardown
}

# ---- t23: create_repo existing dir → nonzero + message ----
t23() {
  setup
  local out rc
  mkdir -p "$FERRY_REPO_BASE/exists-already"
  export REPO_SESSION_TMUXBIN="$FAKE"
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    create_repo exists-already 2>&1
  )
  rc=$?
  if [[ $rc -ne 0 ]] && [[ -n "$out" ]]; then
    ok t23
  else
    fail t23 "rc=$rc out=[$out]"
  fi
  teardown
}

# ---- t24: create_home_session home → new-session -c $HOME then attach ----
t24() {
  setup
  local log
  export FAKE_TMUX_SESSIONS=""
  export REPO_SESSION_TMUXBIN="$FAKE"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    create_home_session home
  ) >/dev/null 2>&1
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -qF "new-session -d -s home -c $HOME" <<<"$log" \
     && grep -q 'attach -t home' <<<"$log"; then
    ok t24
  else
    fail t24 "log=[$log] HOME=[$HOME]"
  fi
  teardown
}

# ---- t25: create_home_session existing name → attach only, no new-session ----
t25() {
  setup
  local log
  export FAKE_TMUX_SESSIONS="home"
  export FAKE_TMUX_META="home|w|1w detached bash"
  export REPO_SESSION_TMUXBIN="$FAKE"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    create_home_session home
  ) >/dev/null 2>&1
  log=$(cat "$FAKE_TMUX_LOG")
  if grep -q 'attach -t home' <<<"$log" && ! grep -q 'new-session' <<<"$log"; then
    ok t25
  else
    fail t25 "log=[$log]"
  fi
  teardown
}

# Strip ANSI SGR sequences for byte-exact art comparison.
_strip_ansi() {
  sed $'s/\033\\[[0-9;]*m//g'
}

# ---- t26: LINES=30 ferry_banner 40 → 6-line MEDIUM art (ANSI-stripped) ----
t26() {
  setup
  local out stripped expected nlines rc
  expected=$(cat <<'EOF'
           |>
         __|__
      __|_o_o_|__
    _|___________|_
   \   mossferry   /
 ~~~\_____________/~~~
EOF
)
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    LINES=30 ferry_banner 40
  )
  rc=$?
  nlines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  stripped=$(printf '%s' "$out" | _strip_ansi)
  if [[ $rc -eq 0 ]] && [[ $nlines -eq 6 ]] && [[ "$stripped" == "$expected" ]]; then
    ok t26
  else
    fail t26 "rc=$rc nlines=$nlines stripped=[$(printf '%s' "$stripped" | cat -A)]"
  fi
  teardown
}

# ---- t27: LINES=10 ferry_banner → 1 line with ⛴ mossferry ----
t27() {
  setup
  local out stripped nlines rc
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    LINES=10 ferry_banner
  )
  rc=$?
  nlines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  # Name is green (ANSI); compare after strip so the line is exactly "⛴ mossferry"
  stripped=$(printf '%s' "$out" | _strip_ansi)
  if [[ $rc -eq 0 ]] && [[ $nlines -eq 1 ]] && [[ "$stripped" == "⛴ mossferry" ]]; then
    ok t27
  else
    fail t27 "rc=$rc nlines=$nlines stripped=[$stripped] out=[$out]"
  fi
  teardown
}

# ---- t28: FERRY_BANNER=off and =0 → empty stdout, exit 0 ----
t28() {
  setup
  local out1 out2 rc1 rc2
  out1=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    LINES=30 FERRY_BANNER=off ferry_banner
  )
  rc1=$?
  out2=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    LINES=30 FERRY_BANNER=0 ferry_banner
  )
  rc2=$?
  if [[ $rc1 -eq 0 ]] && [[ $rc2 -eq 0 ]] && [[ -z "$out1" ]] && [[ -z "$out2" ]]; then
    ok t28
  else
    fail t28 "rc1=$rc1 rc2=$rc2 out1=[$out1] out2=[$out2]"
  fi
  teardown
}

# ---- t33: LINES=30 ferry_banner 100 → 6-line WIDE art (ANSI-stripped) ----
t33() {
  setup
  local out stripped expected nlines rc
  expected=$(cat <<'EOF'
           |>
         __|__               __
      __|_o_o_|__           / _|___ _ _ _ _ _  _
    _|___________|_        |  _/ -_) '_| '_| || |
   \   o   o   o   /       |_| \___|_| |_|  \_, |
 ~~~\_____________/~~~~~~~~~~~~~~~~~~~~~~~~ |__/ ~~
EOF
)
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    LINES=30 ferry_banner 100
  )
  rc=$?
  nlines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  stripped=$(printf '%s' "$out" | _strip_ansi)
  if [[ $rc -eq 0 ]] && [[ $nlines -eq 6 ]] && [[ "$stripped" == "$expected" ]]; then
    ok t33
  else
    fail t33 "rc=$rc nlines=$nlines stripped=[$(printf '%s' "$stripped" | cat -A)]"
  fi
  teardown
}

# ---- t34: LINES=30 ferry_banner 20 → SMALL (narrow wins when tall) ----
t34() {
  setup
  local out stripped nlines rc
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    LINES=30 ferry_banner 20
  )
  rc=$?
  nlines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  stripped=$(printf '%s' "$out" | _strip_ansi)
  if [[ $rc -eq 0 ]] && [[ $nlines -eq 1 ]] && [[ "$stripped" == "⛴ mossferry" ]]; then
    ok t34
  else
    fail t34 "rc=$rc nlines=$nlines stripped=[$stripped] out=[$out]"
  fi
  teardown
}

# ---- t35: --cycle on all three fzf invocations ----
t35() {
  local n
  n=$(grep -c -- '--cycle' "$RS" || true)
  if [[ "$n" -eq 3 ]]; then
    ok t35
  else
    fail t35 "grep -c -- '--cycle' = $n (want 3)"
  fi
}

# ---- t29: default FERRY_LAUNCHERS → parse_launchers + launcher_cmd ----
t29() {
  setup
  local keys="" cmds="" lc="" out
  unset FERRY_LAUNCHERS 2>/dev/null || true
  export REPO_SESSION_TMUXBIN="$FAKE"
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    load_config
    parse_launchers
    printf 'KEYS:%s\n' "${LAUNCHER_KEYS[*]-}"
    printf 'CMDS:%s\n' "${LAUNCHER_CMDS[*]-}"
    printf 'LC:%s\n' "$(launcher_cmd ctrl-g 2>/dev/null || true)"
  ) 2>/dev/null || true
  keys=$(printf '%s\n' "$out" | sed -n 's/^KEYS://p')
  cmds=$(printf '%s\n' "$out" | sed -n 's/^CMDS://p')
  lc=$(printf '%s\n' "$out" | sed -n 's/^LC://p')
  if [[ "$keys" == "ctrl-a ctrl-g" ]] && [[ "$cmds" == "claude grok" ]] && [[ "$lc" == "grok" ]]; then
    ok t29
  else
    fail t29 "keys=[$keys] cmds=[$cmds] lc=[$lc] out=[$out]"
  fi
  teardown
}

# ---- t30: reserved/invalid skipped; first-colon split keeps args ----
t30() {
  setup
  local keys="" cmds="" lc="" n="" out
  export FERRY_LAUNCHERS="ctrl-x:evil,banana:claude,alt-c:claude code"
  export REPO_SESSION_TMUXBIN="$FAKE"
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    parse_launchers
    printf 'N:%s\n' "${#LAUNCHER_KEYS[@]}"
    printf 'KEYS:%s\n' "${LAUNCHER_KEYS[*]-}"
    printf 'CMDS:%s\n' "${LAUNCHER_CMDS[*]-}"
    printf 'LC:%s\n' "$(launcher_cmd alt-c 2>/dev/null || true)"
  ) 2>/dev/null || true
  n=$(printf '%s\n' "$out" | sed -n 's/^N://p')
  keys=$(printf '%s\n' "$out" | sed -n 's/^KEYS://p')
  cmds=$(printf '%s\n' "$out" | sed -n 's/^CMDS://p')
  lc=$(printf '%s\n' "$out" | sed -n 's/^LC://p')
  if [[ "$n" == "1" ]] && [[ "$keys" == "alt-c" ]] && [[ "$cmds" == "claude code" ]] \
     && [[ "$lc" == "claude code" ]]; then
    ok t30
  else
    fail t30 "n=$n keys=[$keys] cmds=[$cmds] lc=[$lc] out=[$out]"
  fi
  teardown
}

# ---- t31: armed launcher overrides start command (home + repo); bare default ----
t31() {
  setup
  local log1="" log2="" log3=""
  mkdir -p "$FERRY_REPO_BASE/myrepo"
  export FAKE_TMUX_SESSIONS=""
  export REPO_SESSION_TMUXBIN="$FAKE"
  unset FERRY_LAUNCHERS 2>/dev/null || true

  # Home path with launcher armed (ctrl-a → claude)
  : >"$FAKE_TMUX_LOG"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    load_config
    parse_launchers
    startcmd=$(launcher_cmd ctrl-a)
    create_home_session home
  ) >/dev/null 2>&1 || true
  log1=$(cat "$FAKE_TMUX_LOG")

  # Repo path with launcher armed (ctrl-g → grok)
  : >"$FAKE_TMUX_LOG"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    load_config
    parse_launchers
    startcmd=$(launcher_cmd ctrl-g)
    repo=myrepo
    _create_session_locked myrepo
  ) >/dev/null 2>&1 || true
  log2=$(cat "$FAKE_TMUX_LOG")

  # No launcher → FERRY_DEFAULT_CMD (neofetch)
  : >"$FAKE_TMUX_LOG"
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    load_config
    startcmd=""
    create_home_session home2
  ) >/dev/null 2>&1 || true
  log3=$(cat "$FAKE_TMUX_LOG")

  if grep -qE 'send-keys -t home[[:space:]]+claude([[:space:]]+C-m)?$' <<<"$log1" \
     && grep -qE 'send-keys -t myrepo[[:space:]]+grok([[:space:]]+C-m)?$' <<<"$log2" \
     && grep -qE 'send-keys -t home2[[:space:]]+neofetch([[:space:]]+C-m)?$' <<<"$log3"; then
    ok t31
  else
    fail t31 "log1=[$log1] log2=[$log2] log3=[$log3]"
  fi
  teardown
}

# ---- t32: empty FERRY_LAUNCHERS disables; launcher_cmd unknown → nonzero ----
t32() {
  setup
  local n="" rc=0
  export FERRY_LAUNCHERS=""
  export REPO_SESSION_TMUXBIN="$FAKE"
  n=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    parse_launchers
    printf '%s' "${#LAUNCHER_KEYS[@]}"
  ) 2>/dev/null || true
  (
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    parse_launchers
    launcher_cmd ctrl-a
  ) >/dev/null 2>&1
  rc=$?
  if [[ "$n" == "0" ]] && [[ $rc -ne 0 ]]; then
    ok t32
  else
    fail t32 "n=$n rc=$rc"
  fi
  teardown
}

export TEST_TMPDIR_ROOT="${TMPDIR:-/tmp}"
set +e
t1; t2; t3; t4; t5; t6; t7; t8; t9; t10; t11; t12
t13; t14; t15; t16; t17; t18; t19; t20
t21; t22; t23; t24; t25
t26; t27; t28
t29; t30; t31; t32
t33; t34; t35
exit $FAIL
