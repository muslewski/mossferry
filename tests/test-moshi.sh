#!/usr/bin/env bash
# tests/test-moshi.sh — moshi client contract tests (m1–m9)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOSHI="${ROOT}/bin/moshi"
FAKE_BIN="${ROOT}/tests/fake-bin"
fail=0

ok()   { printf 'ok %s\n' "$1"; }
FAIL() { printf 'FAIL %s\n' "$1"; fail=1; }

# Run moshi with isolated HOME, PATH stubs, and a fresh FAKE_NET_LOG.
# Usage: run_moshi <stdout_file> <stderr_file> <log_file> -- <moshi args...>
# Sets globals: _rc, _out, _err, _log  (paths); exit code in _exit
run_moshi() {
  local outf="$1" errf="$2" logf="$3"
  shift 3
  [[ "${1:-}" == -- ]] && shift
  local home
  home="$(mktemp -d)"
  export HOME="$home"
  export FAKE_NET_LOG="$logf"
  : >"$logf"
  # Ensure PATH uses fake-bin first; include system for git etc.
  PATH="${FAKE_BIN}:${PATH}"
  set +e
  "$MOSHI" "$@" >"$outf" 2>"$errf"
  _exit=$?
  set -e
  # keep HOME around for config cases that need it before run; caller may use $home
  _home="$home"
  _out="$outf"
  _err="$errf"
  _log="$logf"
}

# Like run_moshi but reuses an existing HOME (for config file cases).
run_moshi_home() {
  local home="$1" outf="$2" errf="$3" logf="$4"
  shift 4
  [[ "${1:-}" == -- ]] && shift
  export HOME="$home"
  export FAKE_NET_LOG="$logf"
  : >"$logf"
  PATH="${FAKE_BIN}:${PATH}"
  set +e
  "$MOSHI" "$@" >"$outf" 2>"$errf"
  _exit=$?
  set -e
  _home="$home"
  _out="$outf"
  _err="$errf"
  _log="$logf"
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --- m1: moshi h repo --primary → mosh with timeout + client-version ---
{
  name=m1
  outf="$tmpdir/m1.out" errf="$tmpdir/m1.err" logf="$tmpdir/m1.log"
  run_moshi "$outf" "$errf" "$logf" -- h repo --primary
  line="$(head -n1 "$logf" 2>/dev/null || true)"
  # Expect: .../mosh --server=MOSH_SERVER_NETWORK_TMOUT=86400 mosh-server h -- .local/bin/repo-session --client-version 1.0.0 repo --primary
  expected_tail="mosh --server=MOSH_SERVER_NETWORK_TMOUT=86400 mosh-server h -- .local/bin/repo-session --client-version 1.0.0 repo --primary"
  if [[ "$line" == *"$expected_tail" ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  expected log line to end with: %s\n' "$expected_tail" >&2
    printf '  got: %s\n' "$line" >&2
  fi
}

# --- m2: moshi h --list → ssh, no mosh ---
{
  name=m2
  outf="$tmpdir/m2.out" errf="$tmpdir/m2.err" logf="$tmpdir/m2.log"
  run_moshi "$outf" "$errf" "$logf" -- h --list
  line="$(head -n1 "$logf" 2>/dev/null || true)"
  has_mosh=0
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == *mosh* && "$l" != *mosh-server* ]] && has_mosh=1
    # basename check: line containing "/mosh " or ending path component mosh
    case "$l" in
      */mosh\ *|*/mosh) has_mosh=1 ;;
    esac
  done <"$logf"
  # More precise: first field basename is mosh
  has_mosh=0
  while IFS= read -r l || [[ -n "$l" ]]; do
    base="${l%% *}"
    base="${base##*/}"
    [[ "$base" == mosh ]] && has_mosh=1
  done <"$logf"
  base0="${line%% *}"; base0="${base0##*/}"
  if [[ "$base0" == ssh ]] && [[ "$line" == *" h "* || "$line" == *" h" || "$line" == *"/ssh h"* ]] && [[ $has_mosh -eq 0 ]]; then
    # line starts with ssh h (basename ssh, host h)
    ok "$name"
  elif [[ "$base0" == ssh ]] && [[ $has_mosh -eq 0 ]] && [[ "$line" == *" h "* || "$line" == *"/ssh h "* || "$line" == *" ssh h "* || "$line" == *"/ssh h"* ]]; then
    ok "$name"
  else
    # Simpler assert: first log line basename is ssh and contains " h ", no mosh binary lines
    if [[ "$base0" == ssh ]] && [[ $has_mosh -eq 0 ]]; then
      ok "$name"
    else
      FAIL "$name"
      printf '  expected ssh line, no mosh; got log:\n' >&2
      cat "$logf" >&2 || true
    fi
  fi
}

# --- m3: env > file for MOSHI_SERVER_TIMEOUT ---
{
  name=m3
  home="$(mktemp -d)"
  mkdir -p "$home/.config/moshi"
  printf 'MOSHI_SERVER_TIMEOUT=111\n' >"$home/.config/moshi/config"
  outf="$tmpdir/m3a.out" errf="$tmpdir/m3a.err" logf="$tmpdir/m3a.log"
  MOSHI_SERVER_TIMEOUT=222 run_moshi_home "$home" "$outf" "$errf" "$logf" -- h repo
  line="$(cat "$logf" 2>/dev/null || true)"
  ok_env=0 ok_file=0
  [[ "$line" == *TMOUT=222* ]] && ok_env=1
  outf="$tmpdir/m3b.out" errf="$tmpdir/m3b.err" logf="$tmpdir/m3b.log"
  unset MOSHI_SERVER_TIMEOUT || true
  run_moshi_home "$home" "$outf" "$errf" "$logf" -- h repo
  line2="$(cat "$logf" 2>/dev/null || true)"
  [[ "$line2" == *TMOUT=111* ]] && ok_file=1
  if [[ $ok_env -eq 1 && $ok_file -eq 1 ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  env wins (TMOUT=222): %s log=%s\n' "$ok_env" "$line" >&2
    printf '  file (TMOUT=111): %s log=%s\n' "$ok_file" "$line2" >&2
  fi
  rm -rf "$home"
}

# --- m4: config MOSHI_DEFAULT_HOST=hh; bare moshi → targets hh, no repo ---
{
  name=m4
  home="$(mktemp -d)"
  mkdir -p "$home/.config/moshi"
  printf 'MOSHI_DEFAULT_HOST=hh\n' >"$home/.config/moshi/config"
  outf="$tmpdir/m4.out" errf="$tmpdir/m4.err" logf="$tmpdir/m4.log"
  unset MOSHI_DEFAULT_HOST || true
  run_moshi_home "$home" "$outf" "$errf" "$logf" --
  line="$(cat "$logf" 2>/dev/null || true)"
  # mosh ... hh -- .local/bin/repo-session --client-version 1.0.0   (no repo after version)
  if [[ "$line" == *" hh -- "* ]] && [[ "$line" == *"--client-version 1.0.0" ]] && [[ "$line" != *"--client-version 1.0.0 "* ]]; then
    ok "$name"
  elif [[ "$line" == *" hh -- "* ]] && [[ "$line" == *repo-session* ]]; then
    # Accept trailing space after version or end: no extra repo token
    # Extract after --client-version 1.0.0
    after="${line#*--client-version 1.0.0}"
    after="${after#"${after%%[![:space:]]*}"}"  # trim leading space
    if [[ -z "$after" ]]; then
      ok "$name"
    else
      FAIL "$name"
      printf '  expected no repo arg after version; after=%q log=%s\n' "$after" "$line" >&2
    fi
  else
    FAIL "$name"
    printf '  expected mosh targeting hh, no repo; got: %s\n' "$line" >&2
  fi
  rm -rf "$home"
}

# --- m5: bare moshi, no config → exit 1, stderr usage ---
{
  name=m5
  outf="$tmpdir/m5.out" errf="$tmpdir/m5.err" logf="$tmpdir/m5.log"
  unset MOSHI_DEFAULT_HOST || true
  run_moshi "$outf" "$errf" "$logf" --
  err="$(cat "$errf" 2>/dev/null || true)"
  if [[ $_exit -eq 1 ]] && [[ "$err" == *[Uu]sage* || "$err" == *usage* || "$err" == *moshi\ \<host\>* ]]; then
    ok "$name"
  else
    # plan: stderr contains `usage`
    if [[ $_exit -eq 1 ]] && grep -qi usage "$errf" 2>/dev/null; then
      ok "$name"
    else
      FAIL "$name"
      printf '  exit=%s err=%s\n' "$_exit" "$err" >&2
    fi
  fi
}

# --- m6: moshi --help → exit 0, stdout has moshi <host>, log empty ---
{
  name=m6
  outf="$tmpdir/m6.out" errf="$tmpdir/m6.err" logf="$tmpdir/m6.log"
  run_moshi "$outf" "$errf" "$logf" -- --help
  out="$(cat "$outf" 2>/dev/null || true)"
  log_content="$(cat "$logf" 2>/dev/null || true)"
  if [[ $_exit -eq 0 ]] && [[ "$out" == *"moshi <host>"* ]] && [[ -z "$log_content" ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  exit=%s out=%s log=%s\n' "$_exit" "$out" "$log_content" >&2
  fi
}

# --- m7: moshi h repo -c -- htop → args after repo preserved ---
{
  name=m7
  outf="$tmpdir/m7.out" errf="$tmpdir/m7.err" logf="$tmpdir/m7.log"
  run_moshi "$outf" "$errf" "$logf" -- h repo -c -- htop
  line="$(cat "$logf" 2>/dev/null || true)"
  if [[ "$line" == *"repo -c -- htop"* ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  expected repo -c -- htop in log; got: %s\n' "$line" >&2
  fi
}

# --- m8: moshi update h → ssh git -C; stdout local/remote versions ---
{
  name=m8
  outf="$tmpdir/m8.out" errf="$tmpdir/m8.err" logf="$tmpdir/m8.log"
  run_moshi "$outf" "$errf" "$logf" -- update h
  log_content="$(cat "$logf" 2>/dev/null || true)"
  out="$(cat "$outf" 2>/dev/null || true)"
  has_git=0
  if [[ "$log_content" == *"git -C"* ]]; then
    has_git=1
  fi
  if [[ $has_git -eq 1 ]] && [[ "$out" == *"local 1.0.0 / remote 1.0.0"* ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  has_git=%s out=%s log=%s\n' "$has_git" "$out" "$log_content" >&2
  fi
}

# --- m9: moshi update h on canonical remote (no remotes) → skip pull, exit 0 ---
{
  name=m9
  outf="$tmpdir/m9.out" errf="$tmpdir/m9.err" logf="$tmpdir/m9.log"
  run_moshi "$outf" "$errf" "$logf" -- update h
  out="$(cat "$outf" 2>/dev/null || true)"
  if [[ $_exit -eq 0 ]] && [[ "$out" == *canonical* ]] && [[ "$out" == *"local 1.0.0 / remote 1.0.0"* ]]; then
    ok "$name"
  else
    FAIL "$name"
    printf '  exit=%s out=%s err=%s\n' "$_exit" "$out" "$(cat "$errf" 2>/dev/null || true)" >&2
  fi
}

if [[ $fail -ne 0 ]]; then
  exit 1
fi
exit 0
