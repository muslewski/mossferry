#!/usr/bin/env bash
# tests/test-fleet-devlog.sh — fleet-devlog v1 bash emitter (hermetic XDG roots)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${ROOT}/lib/fleet-devlog.sh"
FERRY="${ROOT}/bin/mossferry"
fail=0

ok()   { printf 'ok %s\n' "$1"; }
FAIL() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
hermetic_home() {
  # Sets XDG_STATE_HOME / XDG_CONFIG_HOME under a temp dir. Unsets FLEET_DEVLOG.
  _H="$(mktemp -d)"
  export XDG_STATE_HOME="${_H}/state"
  export XDG_CONFIG_HOME="${_H}/config"
  mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
  unset FLEET_DEVLOG 2>/dev/null || true
  DEVLOG_ARGV=()
}

events_file() {
  printf '%s\n' "${XDG_STATE_HOME}/fleet-devlog/events.jsonl"
}

# ---------------------------------------------------------------------------
# Source the library (must exist after Step 2)
# ---------------------------------------------------------------------------
if [[ ! -r "$LIB" ]]; then
  FAIL "lib-present (missing $LIB)"
  printf 'tests/test-fleet-devlog.sh: %s failure(s) (pre-implementation)\n' "$fail"
  exit 1
fi
# shellcheck disable=SC1090
. "$LIB"

# ---------------------------------------------------------------------------
# 1. off by default (no env, no machine config) → no file written
# ---------------------------------------------------------------------------
{
  hermetic_home
  devlog_emit doctor 0 5
  if [[ ! -f "$(events_file)" ]]; then
    ok "off-by-default"
  else
    FAIL "off-by-default (wrote $(events_file))"
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 2. FLEET_DEVLOG=1 appends exactly ONE line per call
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  devlog_emit doctor 0 5
  devlog_emit update 0 10
  f="$(events_file)"
  if [[ -f "$f" ]]; then
    n=$(wc -l <"$f" | tr -d '[:space:]')
    if [[ "$n" == "2" ]]; then
      ok "one-line-per-call"
    else
      FAIL "one-line-per-call (got $n lines)"
    fi
  else
    FAIL "one-line-per-call (no events file)"
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 3. the line parses as JSON (node; jq not installed)
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  devlog_emit doctor 0 12 result_class=ok
  f="$(events_file)"
  line=$(head -1 "$f" 2>/dev/null || true)
  if [[ -z "$line" ]]; then
    FAIL "json-parse (empty line)"
  else
    if printf '%s\n' "$line" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' 2>/dev/null; then
      tool=$(printf '%s\n' "$line" | node -e 'const e=JSON.parse(require("fs").readFileSync(0,"utf8")); process.stdout.write(String(e.tool||""))')
      if [[ "$tool" == "mossferry" ]]; then
        ok "json-parse"
      else
        FAIL "json-parse (tool=$tool)"
      fi
    else
      FAIL "json-parse (invalid JSON: $line)"
    fi
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 4. FLEET_DEVLOG=0 beats an enabling machine config
# ---------------------------------------------------------------------------
{
  hermetic_home
  mkdir -p "${XDG_CONFIG_HOME}/fleet-devlog"
  printf '%s\n' '{"enabled":true}' >"${XDG_CONFIG_HOME}/fleet-devlog/config.json"
  export FLEET_DEVLOG=0
  devlog_emit doctor 0 5
  if [[ ! -f "$(events_file)" ]]; then
    ok "env-off-beats-config"
  else
    FAIL "env-off-beats-config (wrote despite FLEET_DEVLOG=0)"
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 5. --no-devlog in argv beats an enabling config
# ---------------------------------------------------------------------------
{
  hermetic_home
  mkdir -p "${XDG_CONFIG_HOME}/fleet-devlog"
  printf '%s\n' '{"enabled":true}' >"${XDG_CONFIG_HOME}/fleet-devlog/config.json"
  unset FLEET_DEVLOG 2>/dev/null || true
  DEVLOG_ARGV=(--no-devlog doctor)
  devlog_emit doctor 0 5
  if [[ ! -f "$(events_file)" ]]; then
    ok "no-devlog-flag-beats-config"
  else
    FAIL "no-devlog-flag-beats-config (wrote despite --no-devlog)"
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 6. unwritable root does not fail the caller (exit code unchanged)
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  # Point state at a non-writable path. /proc/… is never creatable.
  export XDG_STATE_HOME="/proc/definitely/not/writable-$$"
  set +e
  (
    # simulate a successful command then emit; exit should stay 42
    rc=42
    devlog_emit doctor "$rc" 3
    exit "$rc"
  )
  got=$?
  set -e
  if [[ "$got" -eq 42 ]]; then
    ok "unwritable-root-fail-open"
  else
    FAIL "unwritable-root-fail-open (got exit=$got want=42)"
  fi
  # restore hermetic cleanup target (state home was fake)
  rm -rf "$_H" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 7. a string sneaking into counts is dropped, not written
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  DEVLOG_ARGV=()
  devlog_emit doctor 0 5 "counts.zones=4" "counts.name=syndcast"
  f="$(events_file)"
  line=$(head -1 "$f" 2>/dev/null || true)
  if [[ -z "$line" ]]; then
    FAIL "counts-drop-string (no line)"
  else
    # zones must be present; name must not appear as a counts value/key
    has_zones=$(printf '%s\n' "$line" | node -e '
      const e=JSON.parse(require("fs").readFileSync(0,"utf8"));
      const c=e.counts||{};
      process.stdout.write(c.zones===4 && c.name===undefined ? "yes" : "no");
    ' 2>/dev/null || echo no)
    if [[ "$has_zones" == "yes" ]]; then
      ok "counts-drop-string"
    else
      FAIL "counts-drop-string (line=$line)"
    fi
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 8. machine config alone enables (sanity; supports precedence step 4)
# ---------------------------------------------------------------------------
{
  hermetic_home
  mkdir -p "${XDG_CONFIG_HOME}/fleet-devlog"
  printf '%s\n' '{"enabled":true}' >"${XDG_CONFIG_HOME}/fleet-devlog/config.json"
  unset FLEET_DEVLOG 2>/dev/null || true
  DEVLOG_ARGV=()
  devlog_emit doctor 0 1
  if [[ -f "$(events_file)" ]]; then
    ok "machine-config-enables"
  else
    FAIL "machine-config-enables (no write with enabled:true)"
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 9. wired bin/mossferry doctor emits with FLEET_DEVLOG=1 (integration)
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  export HOME="$_H/home"
  mkdir -p "$HOME"
  export PATH="${ROOT}/tests/fake-bin:${PATH}"
  # doctor needs a host or default; with empty default it may fail — still should emit
  set +e
  "$FERRY" doctor >/dev/null 2>&1
  set -e
  f="$(events_file)"
  if [[ -f "$f" ]]; then
    # Pure awk: do not use node here. This block sets HOME to a hermetic temp
    # dir; the desk node wrapper (node-from-nvm24) resolves nvm under $HOME/.nvm
    # and exits 127, leaving tool/cmd empty while the JSON line is valid.
    line=$(head -1 "$f")
    tool=$(printf '%s\n' "$line" | awk -F'"' '{for (i = 1; i <= NF; i++) if ($i == "tool") { print $(i + 2); exit }}')
    cmd=$(printf '%s\n' "$line" | awk -F'"' '{for (i = 1; i <= NF; i++) if ($i == "cmd") { print $(i + 2); exit }}')
    if [[ "$tool" == "mossferry" && "$cmd" == "doctor" ]]; then
      ok "wired-doctor-emits"
    else
      FAIL "wired-doctor-emits (tool=$tool cmd=$cmd line=$line)"
    fi
  else
    FAIL "wired-doctor-emits (no events file)"
  fi
  rm -rf "$_H"
}

# ---------------------------------------------------------------------------
# 10. wired bin: unwritable root leaves doctor exit code alone
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  export HOME="$_H/home"
  mkdir -p "$HOME"
  export PATH="${ROOT}/tests/fake-bin:${PATH}"
  # Capture baseline exit without broken state (still hermetic)
  set +e
  "$FERRY" doctor >/dev/null 2>&1
  base_rc=$?
  set -e
  # Now break the state root and re-run
  export XDG_STATE_HOME="/proc/definitely/not/writable-$$"
  set +e
  "$FERRY" doctor >/dev/null 2>&1
  bad_rc=$?
  set -e
  if [[ "$bad_rc" -eq "$base_rc" ]]; then
    ok "wired-unwritable-exit-stable"
  else
    FAIL "wired-unwritable-exit-stable (base=$base_rc bad=$bad_rc)"
  fi
  rm -rf "$_H" 2>/dev/null || true
}

if [[ $fail -ne 0 ]]; then
  printf 'tests/test-fleet-devlog.sh: %s failure(s)\n' "$fail"
  exit 1
fi
printf 'tests/test-fleet-devlog.sh: all ok\n'
exit 0
