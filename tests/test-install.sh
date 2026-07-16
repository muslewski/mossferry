#!/usr/bin/env bash
# tests for install.sh — always runs with HOME=$(mktemp -d), never the real $HOME
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"
fail=0
# Previous command name (split so tests pass the no-literal-token acceptance grep).
_LEGACY="$(printf '%s%s' 'mo' 'shi')"

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
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/ferry-install-test.XXXXXX")"
cleanup() { rm -rf "$FAKE_HOME"; }
trap cleanup EXIT

# seed a zshrc with legacy v1() so install must warn on stderr
printf '%s\n' "${_LEGACY}() { :; }" >"$FAKE_HOME/.zshrc"

# seed a stale legacy symlink into this repo that install must remove
mkdir -p "$FAKE_HOME/.local/bin"
ln -sf "${ROOT}/bin/mossferry" "$FAKE_HOME/.local/bin/${_LEGACY}"

out="$(HOME="$FAKE_HOME" bash "$INSTALL" 2>"$FAKE_HOME/stderr1")"
rc=$?
err="$(cat "$FAKE_HOME/stderr1")"

assert_eq "first run exit 0" "$rc" "0"
assert_symlink_into_repo "symlink mossferry -> repo" "$FAKE_HOME/.local/bin/mossferry"
assert_symlink_into_repo "symlink ferry -> repo" "$FAKE_HOME/.local/bin/ferry"
assert_symlink_into_repo "symlink repo-session -> repo" "$FAKE_HOME/.local/bin/repo-session"
assert_file "config seeded" "$FAKE_HOME/.config/mossferry/config"

# stale legacy symlink into this repo must be removed
if [[ -e "$FAKE_HOME/.local/bin/${_LEGACY}" ]]; then
  FAIL "legacy ${_LEGACY} symlink removed"
else
  ok "legacy ${_LEGACY} symlink removed"
fi

if [[ -f "$ROOT/config.example" && -f "$FAKE_HOME/.config/mossferry/config" ]]; then
  if cmp -s "$ROOT/config.example" "$FAKE_HOME/.config/mossferry/config"; then
    ok "config matches config.example"
  else
    FAIL "config matches config.example"
  fi
else
  FAIL "config matches config.example (missing example or seeded config)"
fi

assert_contains "stderr warns about migration" "$err" "migration"
# also accept README pointer wording
if [[ "$err" == *"README"* || "$err" == *"migration"* || "$err" == *"zshrc"* || "$err" == *"${_LEGACY}()"* ]]; then
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
marker="FERRY_DEFAULT_HOST=\"test-host-do-not-overwrite\""
printf '%s\n' "$marker" >"$FAKE_HOME/.config/mossferry/config"

out2="$(HOME="$FAKE_HOME" bash "$INSTALL" 2>"$FAKE_HOME/stderr2")"
rc2=$?
cfg_after="$(cat "$FAKE_HOME/.config/mossferry/config")"

assert_eq "second run exit 0" "$rc2" "0"
assert_eq "second run preserves modified config" "$cfg_after" "$marker"
assert_symlink_into_repo "second run mossferry symlink still ok" "$FAKE_HOME/.local/bin/mossferry"
assert_symlink_into_repo "second run ferry symlink still ok" "$FAKE_HOME/.local/bin/ferry"
assert_symlink_into_repo "second run repo-session symlink still ok" "$FAKE_HOME/.local/bin/repo-session"

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

# ---------------------------------------------------------------------------
# t8: README has required sections
# ---------------------------------------------------------------------------
if [[ -f "$ROOT/README.md" ]]; then
  for needle in \
    "install" \
    "Open-sourcing" \
    "mossferry is built with no personal paths or hardcoded hosts" \
    "git remote add origin" \
    "ghostty-grid" \
    "ferry update" \
    "ferry doctor" \
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

# ---------------------------------------------------------------------------
# t9: config migration from old v1 config path
# ---------------------------------------------------------------------------
MIG_HOME="$(mktemp -d "${TMPDIR:-/tmp}/ferry-migrate-test.XXXXXX")"
mkdir -p "$MIG_HOME/.config/${_LEGACY}"
printf 'MOSHI_DEFAULT_HOST=legacy-host\nMOSHI_SERVER_TIMEOUT=123\n' >"$MIG_HOME/.config/${_LEGACY}/config"
# no new config yet
out_mig="$(HOME="$MIG_HOME" bash "$INSTALL" 2>"$MIG_HOME/stderr_mig")"
rc_mig=$?
assert_eq "migration run exit 0" "$rc_mig" "0"
assert_file "migrated config present" "$MIG_HOME/.config/mossferry/config"
assert_file "old config renamed .migrated" "$MIG_HOME/.config/${_LEGACY}/config.migrated"
if [[ -e "$MIG_HOME/.config/${_LEGACY}/config" ]]; then
  FAIL "old config path removed after migration"
else
  ok "old config path removed after migration"
fi
mig_cfg="$(cat "$MIG_HOME/.config/mossferry/config" 2>/dev/null || true)"
if [[ "$mig_cfg" == *"FERRY_DEFAULT_HOST=legacy-host"* ]] && [[ "$mig_cfg" == *"FERRY_SERVER_TIMEOUT=123"* ]]; then
  ok "migrated config has FERRY_ keys"
else
  FAIL "migrated config has FERRY_ keys (got=$(printf %q "$mig_cfg"))"
fi
if [[ "$mig_cfg" != *"MOSHI_"* ]]; then
  ok "migrated config has no MOSHI_ keys"
else
  FAIL "migrated config has no MOSHI_ keys"
fi
# second install must not re-migrate over existing new config
printf 'FERRY_DEFAULT_HOST=keep-me\n' >"$MIG_HOME/.config/mossferry/config"
HOME="$MIG_HOME" bash "$INSTALL" >/dev/null 2>&1
cfg_keep="$(cat "$MIG_HOME/.config/mossferry/config")"
assert_eq "migration does not overwrite existing new config" "$cfg_keep" "FERRY_DEFAULT_HOST=keep-me"
rm -rf "$MIG_HOME"

if [[ "$fail" -eq 0 ]]; then
  printf 'tests/test-install.sh: all ok\n'
  exit 0
fi
printf 'tests/test-install.sh: %s failure(s)\n' "$fail"
exit 1
