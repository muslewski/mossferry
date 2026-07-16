#!/usr/bin/env bash
# tests for install.sh — always runs with HOME=$(mktemp -d), never the real $HOME
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"
fail=0

ok()  { printf 'ok %s\n' "$1"; }
FAIL() { printf 'FAIL %s\n' "$1"; fail=1; }

assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    ok "$name"
  else
    FAIL "$name (got=$(printf %q "$got") want=$(printf %q "$want"))"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$name"
  else
    FAIL "$name (missing $(printf %q "$needle") in $(printf %q "$haystack"))"
  fi
}

assert_file() {
  local name="$1" path="$2"
  if [[ -e "$path" ]]; then
    ok "$name"
  else
    FAIL "$name (missing $path)"
  fi
}

assert_symlink_into_repo() {
  local name="$1" link="$2"
  if [[ ! -L "$link" ]]; then
    FAIL "$name (not a symlink: $link)"
    return
  fi
  local target
  target="$(readlink -f "$link")"
  case "$target" in
    "$ROOT"/*) ok "$name" ;;
    *) FAIL "$name (target $target not under $ROOT)" ;;
  esac
}

# ---------------------------------------------------------------------------
# t1: install.sh must exist and be runnable
# ---------------------------------------------------------------------------
if [[ ! -f "$INSTALL" ]]; then
  FAIL "install.sh exists"
  printf 'tests/test-install.sh: %s failures (install.sh missing — remaining cases skipped)\n' "$fail"
  exit 1
fi
ok "install.sh exists"

# ---------------------------------------------------------------------------
# t2–t5: first run under fake HOME
# ---------------------------------------------------------------------------
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/moshi-install-test.XXXXXX")"
cleanup() { rm -rf "$FAKE_HOME"; }
trap cleanup EXIT

# seed a zshrc with moshi() so install must warn on stderr
printf '%s\n' 'moshi() { :; }' >"$FAKE_HOME/.zshrc"

out="$(HOME="$FAKE_HOME" bash "$INSTALL" 2>"$FAKE_HOME/stderr1")"
rc=$?
err="$(cat "$FAKE_HOME/stderr1")"

assert_eq "first run exit 0" "$rc" "0"
assert_symlink_into_repo "symlink moshi -> repo" "$FAKE_HOME/.local/bin/moshi"
assert_symlink_into_repo "symlink repo-session -> repo" "$FAKE_HOME/.local/bin/repo-session"
assert_file "config seeded" "$FAKE_HOME/.config/moshi/config"

if [[ -f "$ROOT/config.example" && -f "$FAKE_HOME/.config/moshi/config" ]]; then
  if cmp -s "$ROOT/config.example" "$FAKE_HOME/.config/moshi/config"; then
    ok "config matches config.example"
  else
    FAIL "config matches config.example"
  fi
else
  FAIL "config matches config.example (missing example or seeded config)"
fi

assert_contains "stderr warns about moshi() / migration" "$err" "migration"
# also accept README pointer wording
if [[ "$err" == *"README"* || "$err" == *"migration"* || "$err" == *"zshrc"* || "$err" == *"moshi()"* ]]; then
  ok "stderr mentions legacy shell config"
else
  FAIL "stderr mentions legacy shell config (got=$(printf %q "$err"))"
fi

# one line per action on stdout (at least mkdir/link/seed style messages)
line_count="$(printf '%s\n' "$out" | grep -c . || true)"
if [[ "$line_count" -ge 1 ]]; then
  ok "stdout has action lines ($line_count)"
else
  FAIL "stdout has action lines"
fi

# ---------------------------------------------------------------------------
# t6: second run is idempotent and does not overwrite a modified config
# ---------------------------------------------------------------------------
marker="MOSHI_DEFAULT_HOST=\"test-host-do-not-overwrite\""
printf '%s\n' "$marker" >"$FAKE_HOME/.config/moshi/config"

out2="$(HOME="$FAKE_HOME" bash "$INSTALL" 2>"$FAKE_HOME/stderr2")"
rc2=$?
cfg_after="$(cat "$FAKE_HOME/.config/moshi/config")"

assert_eq "second run exit 0" "$rc2" "0"
assert_eq "second run preserves modified config" "$cfg_after" "$marker"
assert_symlink_into_repo "second run moshi symlink still ok" "$FAKE_HOME/.local/bin/moshi"
assert_symlink_into_repo "second run repo-session symlink still ok" "$FAKE_HOME/.local/bin/repo-session"

# ---------------------------------------------------------------------------
# t7: config.example has the six keys (commented)
# ---------------------------------------------------------------------------
if [[ -f "$ROOT/config.example" ]]; then
  for key in MOSHI_REMOTE_BIN MOSHI_REPO_BASE MOSHI_DEFAULT_CMD MOSHI_DEFAULT_HOST MOSHI_SERVER_TIMEOUT MOSHI_REMOTE_REPO; do
    if grep -q "$key" "$ROOT/config.example"; then
      ok "config.example has $key"
    else
      FAIL "config.example has $key"
    fi
  done
else
  FAIL "config.example exists"
fi

# ---------------------------------------------------------------------------
# t8: README has required sections
# ---------------------------------------------------------------------------
if [[ -f "$ROOT/README.md" ]]; then
  for needle in \
    "install" \
    "Open-sourcing" \
    "moshi is built with no personal paths or hardcoded hosts" \
    "git remote add origin" \
    "ghostty-grid" \
    "moshi update" \
    "moshi doctor" \
    "tests/run.sh"
  do
    if grep -qiF "$needle" "$ROOT/README.md"; then
      ok "README mentions: $needle"
    else
      FAIL "README mentions: $needle"
    fi
  done
else
  FAIL "README.md exists"
fi

if [[ "$fail" -eq 0 ]]; then
  printf 'tests/test-install.sh: all ok\n'
  exit 0
fi
printf 'tests/test-install.sh: %s failure(s)\n' "$fail"
exit 1
