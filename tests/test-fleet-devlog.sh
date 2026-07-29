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
# JSON field helpers — pure awk (no node, no jq, no $HOME).
#
# The desk node shim (~/.local/bin/node → node-from-nvm24) resolves nvm under
# $HOME/.nvm. Under hermetic_home (and any block that sets HOME to a temp
# dir) that shim exits 127. `node -e ... 2>/dev/null || echo parse-fail`
# then masquerades as a product assertion failure. Extract with awk instead.
# ---------------------------------------------------------------------------
# String field value (first match). Empty stdout if key absent / non-string.
json_str() {
  # usage: json_str <line> <key>
  printf '%s\n' "$1" | awk -F'"' -v key="$2" '
    { for (i = 1; i <= NF; i++) if ($i == key) { print $(i + 2); exit } }
  '
}

# String/null field status: absent | null | empty | present:<value>
# Distinguishes missing key from null/empty — required by repo_id omit contract.
json_str_status() {
  # usage: json_str_status <line> <key>
  printf '%s\n' "$1" | awk -F'"' -v key="$2" '
    {
      for (i = 1; i <= NF; i++) {
        if ($i != key) continue
        nxt = $(i + 1)
        if (nxt ~ /^:[[:space:]]*null/) { print "null"; exit }
        if (nxt == ":" || nxt ~ /^:[[:space:]]*$/) {
          val = $(i + 2)
          if (val == "") print "empty"
          else print "present:" val
          exit
        }
        # e.g. :"value" collapsed oddly — still surface i+2 if any
        val = $(i + 2)
        if (val == "") print "empty"
        else print "present:" val
        exit
      }
      print "absent"
    }
  '
}

# Numeric counts.<name> value via `"name":N` after the counts object starts.
# Prints the number or empty if absent.
json_counts_num() {
  # usage: json_counts_num <line> <name>
  printf '%s\n' "$1" | awk -v name="$2" '
    {
      if (match($0, "\"counts\"[[:space:]]*:[[:space:]]*\\{[^}]*\"" name "\"[[:space:]]*:[[:space:]]*-?[0-9]+([.][0-9]+)?")) {
        frag = substr($0, RSTART, RLENGTH)
        if (match(frag, /-?[0-9]+([.][0-9]+)?$/)) {
          print substr(frag, RSTART, RLENGTH)
          exit
        }
      }
    }
  '
}

# True if $1 is an executable node that actually starts (desk shim exits 127
# when $HOME/.nvm has no v24.* — "exists on PATH" is not enough).
_node_runs() {
  local bin=${1-}
  [[ -n "$bin" && -x "$bin" ]] || return 1
  "$bin" -e 'process.exit(0)' >/dev/null 2>&1
}

# Resolve a real Node ≥24 binary BEFORE any hermetic HOME. The desk shim
# documents DOGFOOD_NODE_BIN and NVM_DIR as escape hatches — use them.
# Only needed when a test must invoke a JS tool (cross-tool repo_id compare).
resolve_suite_node() {
  if _node_runs "${DOGFOOD_NODE_BIN:-}"; then
    printf '%s\n' "$DOGFOOD_NODE_BIN"
    return 0
  fi
  local nvm base
  nvm="${NVM_DIR:-${HOME}/.nvm}"
  base="$(ls -1d "$nvm/versions/node"/v24.* 2>/dev/null | sort -V | tail -1 || true)"
  if _node_runs "${base:+$base/bin/node}"; then
    printf '%s\n' "$base/bin/node"
    return 0
  fi
  # Last resort: PATH node, but only if it actually runs under current HOME.
  local p
  p=$(command -v node 2>/dev/null) || true
  if _node_runs "$p"; then
    # Prefer the real nvm binary if the PATH hit is the shim that only works
    # because HOME currently has .nvm — still record whatever runs.
    printf '%s\n' "$p"
    return 0
  fi
  return 1
}

# Capture once at suite load (cwd is still the real user environment).
SUITE_NODE_BIN=""
if SUITE_NODE_BIN=$(resolve_suite_node); then
  :
else
  SUITE_NODE_BIN=""
fi

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
# 3. the line is well-formed hand-rolled JSON (no node/jq — both unavailable
#    under hermetic HOME / on this host respectively)
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
    # Structural check without node/jq: required string keys present, tool=mossferry.
    tool=$(json_str "$line" tool)
    cmd=$(json_str "$line" cmd)
    if [[ "$tool" == "mossferry" && "$cmd" == "doctor" && "$line" == \{*\} ]]; then
      ok "json-parse"
    else
      FAIL "json-parse (tool=$tool cmd=$cmd line=$line)"
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
    # zones must be present as number 4; name must not appear as a counts key
    zones=$(json_counts_num "$line" zones)
    name_status=$(json_str_status "$line" name)
    # "name" as a top-level string key should be absent; also no "name" inside counts.
    # Emitter drops non-numeric counts.name — ensure the token "name" is not a key.
    if [[ "$zones" == "4" && "$name_status" == "absent" && "$line" != *'"name"'* ]]; then
      ok "counts-drop-string"
    else
      FAIL "counts-drop-string (zones=$zones name_status=$name_status line=$line)"
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

# ---------------------------------------------------------------------------
# 11. main checkout event carries expected repo_id (<basename>-<sha256-8>)
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  DEVLOG_ARGV=()
  _base=$(mktemp -d)
  main="$_base/acme"
  mkdir -p "$main"
  git -C "$main" init -q
  git -C "$main" config user.email "t@example.com"
  git -C "$main" config user.name "t"
  git -C "$main" commit --allow-empty -q -m init
  main_real=$(cd "$main" && pwd -P)
  expect_hash=$(printf '%s' "$main_real" | sha256sum | awk '{print substr($1,1,8)}')
  expect_id="acme-${expect_hash}"
  (
    cd "$main_real" || exit 1
    # shellcheck disable=SC1090
    . "$LIB"
    devlog_emit doctor 0 5
  )
  f="$(events_file)"
  line=$(head -1 "$f" 2>/dev/null || true)
  if [[ -z "$line" ]]; then
    FAIL "repo-id-main-checkout (harness: empty events line)"
  else
    got=$(json_str "$line" repo_id)
    if [[ "$got" == "$expect_id" ]]; then
      ok "repo-id-main-checkout"
    else
      FAIL "repo-id-main-checkout (got=$got want=$expect_id line=$line)"
    fi
  fi
  rm -rf "$_H" "$_base"
}

# ---------------------------------------------------------------------------
# 12. worktree event carries the SAME repo_id as the main checkout
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  DEVLOG_ARGV=()
  _base=$(mktemp -d)
  main="$_base/acme"
  mkdir -p "$main"
  git -C "$main" init -q
  git -C "$main" config user.email "t@example.com"
  git -C "$main" config user.name "t"
  git -C "$main" commit --allow-empty -q -m init
  main_real=$(cd "$main" && pwd -P)
  wt="$_base/wt-child"
  git -C "$main_real" worktree add -q "$wt" -b wtbranch
  wt_real=$(cd "$wt" && pwd -P)
  (
    cd "$main_real" || exit 1
    # shellcheck disable=SC1090
    . "$LIB"
    devlog_emit doctor 0 1
  )
  (
    cd "$wt_real" || exit 1
    # shellcheck disable=SC1090
    . "$LIB"
    devlog_emit update 0 2
  )
  f="$(events_file)"
  if [[ ! -f "$f" ]]; then
    FAIL "repo-id-worktree-folds (harness: no events file)"
  else
    line1=$(sed -n '1p' "$f")
    line2=$(sed -n '2p' "$f")
    if [[ -z "$line1" || -z "$line2" ]]; then
      FAIL "repo-id-worktree-folds (harness: need 2 event lines)"
    else
      id_main=$(json_str "$line1" repo_id)
      id_wt=$(json_str "$line2" repo_id)
      if [[ -n "$id_main" && "$id_main" == "$id_wt" ]]; then
        ok "repo-id-worktree-folds"
      else
        FAIL "repo-id-worktree-folds (main=$id_main wt=$id_wt same=$([[ "$id_main" == "$id_wt" ]] && echo same || echo diff))"
      fi
    fi
  fi
  git -C "$main_real" worktree remove -f "$wt_real" 2>/dev/null || true
  rm -rf "$_H" "$_base"
}

# ---------------------------------------------------------------------------
# 13. outside a git repo → repo_id field absent (not empty, not null)
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  DEVLOG_ARGV=()
  _norepo=$(mktemp -d)
  (
    cd "$_norepo" || exit 1
    # shellcheck disable=SC1090
    . "$LIB"
    devlog_emit doctor 0 5
  )
  f="$(events_file)"
  line=$(head -1 "$f" 2>/dev/null || true)
  if [[ -z "$line" ]]; then
    FAIL "repo-id-absent-outside-git (harness: empty events line)"
  else
    status=$(json_str_status "$line" repo_id)
    if [[ "$status" == "absent" ]]; then
      ok "repo-id-absent-outside-git"
    else
      FAIL "repo-id-absent-outside-git (status=$status line=$line)"
    fi
  fi
  rm -rf "$_H" "$_norepo"
}

# ---------------------------------------------------------------------------
# 14. repo_id matches agentic-sage resolveRepoId for the same repo
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  DEVLOG_ARGV=()
  _base=$(mktemp -d)
  main="$_base/acme"
  mkdir -p "$main"
  git -C "$main" init -q
  git -C "$main" config user.email "t@example.com"
  git -C "$main" config user.name "t"
  git -C "$main" commit --allow-empty -q -m init
  main_real=$(cd "$main" && pwd -P)
  # Cross-tool compare requires Node. Use the pre-hermetic absolute binary
  # (DOGFOOD_NODE_BIN / nvm v24.*) — never the $HOME-sensitive PATH shim alone.
  if [[ -z "$SUITE_NODE_BIN" || ! -x "$SUITE_NODE_BIN" ]]; then
    FAIL "repo-id-matches-js-tool (harness: no usable Node ≥24; set DOGFOOD_NODE_BIN or NVM_DIR)"
    rm -rf "$_H" "$_base"
  else
    set +e
    js_id=$("$SUITE_NODE_BIN" --input-type=module -e '
      import { resolveRepoId } from "/home/kento/Repositories/agentic-sage/lib/repo-id.mjs";
      const id = resolveRepoId(process.argv[1]);
      process.stdout.write(id == null ? "" : id);
    ' "$main_real" 2>/dev/null)
    js_rc=$?
    set -e
    if [[ "$js_rc" -ne 0 ]]; then
      FAIL "repo-id-matches-js-tool (harness: JS resolveRepoId exit=$js_rc via $SUITE_NODE_BIN)"
      rm -rf "$_H" "$_base"
    else
      (
        cd "$main_real" || exit 1
        # shellcheck disable=SC1090
        . "$LIB"
        devlog_emit doctor 0 5
      )
      f="$(events_file)"
      line=$(head -1 "$f" 2>/dev/null || true)
      if [[ -z "$line" ]]; then
        FAIL "repo-id-matches-js-tool (harness: empty events line)"
      else
        got=$(json_str "$line" repo_id)
        if [[ -n "$js_id" && "$got" == "$js_id" ]]; then
          ok "repo-id-matches-js-tool"
        else
          FAIL "repo-id-matches-js-tool (js=$js_id bash=$got line=$line)"
        fi
      fi
      rm -rf "$_H" "$_base"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 15. hashing tool unavailable → event still written, repo_id absent, exit unchanged
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  DEVLOG_ARGV=()
  _base=$(mktemp -d)
  main="$_base/acme"
  mkdir -p "$main"
  git -C "$main" init -q
  git -C "$main" config user.email "t@example.com"
  git -C "$main" config user.name "t"
  git -C "$main" commit --allow-empty -q -m init
  main_real=$(cd "$main" && pwd -P)
  # Restricted PATH: keep git/coreutils, omit sha256sum and openssl
  _rbin=$(mktemp -d)
  for c in bash sh git printf tr date mkdir cat head wc od dirname basename \
           realpath awk sed node touch mv rm ls uname env; do
    p=$(command -v "$c" 2>/dev/null) || continue
    ln -s "$p" "$_rbin/$c" 2>/dev/null || true
  done
  # Ensure the hashers are not reachable via leftover PATH.
  # set -e is on after earlier wired tests; capture non-zero without aborting.
  set +e
  (
    export PATH="$_rbin"
    cd "$main_real" || exit 99
    # shellcheck disable=SC1090
    . "$LIB"
    rc=77
    devlog_emit doctor "$rc" 3
    exit "$rc"
  )
  got_rc=$?
  set -e
  f="$(events_file)"
  line=$(head -1 "$f" 2>/dev/null || true)
  # Emitter must still write the event (without repo_id) and preserve rc=77.
  # Do not use node here — restricted PATH / hermetic HOME make the desk shim
  # exit 127 and the old `|| echo no-event` hid a harness failure as no-event.
  if [[ -z "$line" ]]; then
    FAIL "repo-id-hash-missing-fail-open (rc=$got_rc status=no-event line=)"
  else
    status=$(json_str_status "$line" repo_id)
    if [[ "$got_rc" -eq 77 && "$status" == "absent" ]]; then
      ok "repo-id-hash-missing-fail-open"
    else
      FAIL "repo-id-hash-missing-fail-open (rc=$got_rc status=$status line=$line)"
    fi
  fi
  rm -rf "$_H" "$_base" "$_rbin"
}

# ---------------------------------------------------------------------------
# 16. log root unwritable → command exit code unchanged (wired doctor)
#     (duplicates invariant of test 10; required acceptance proof)
# ---------------------------------------------------------------------------
{
  hermetic_home
  export FLEET_DEVLOG=1
  export HOME="$_H/home"
  mkdir -p "$HOME"
  export PATH="${ROOT}/tests/fake-bin:${PATH}"
  set +e
  "$FERRY" doctor >/dev/null 2>&1
  base_rc=$?
  set -e
  export XDG_STATE_HOME="/proc/definitely/not/writable-$$"
  set +e
  "$FERRY" doctor >/dev/null 2>&1
  bad_rc=$?
  set -e
  if [[ "$bad_rc" -eq "$base_rc" ]]; then
    ok "repo-id-unwritable-exit-stable"
  else
    FAIL "repo-id-unwritable-exit-stable (base=$base_rc bad=$bad_rc)"
  fi
  rm -rf "$_H" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 17. silent by default: no config, no env → zero new lines (wired doctor)
# ---------------------------------------------------------------------------
{
  hermetic_home
  unset FLEET_DEVLOG 2>/dev/null || true
  export HOME="$_H/home"
  mkdir -p "$HOME"
  export PATH="${ROOT}/tests/fake-bin:${PATH}"
  f="$(events_file)"
  before=0
  [[ -f "$f" ]] && before=$(wc -l <"$f" | tr -d '[:space:]')
  set +e
  "$FERRY" doctor >/dev/null 2>&1
  set -e
  after=0
  [[ -f "$f" ]] && after=$(wc -l <"$f" | tr -d '[:space:]')
  if [[ "$before" -eq 0 && "$after" -eq 0 && ! -f "$f" ]]; then
    ok "silent-by-default-zero-lines"
  elif [[ "$before" -eq "$after" ]]; then
    ok "silent-by-default-zero-lines"
  else
    FAIL "silent-by-default-zero-lines (before=$before after=$after)"
  fi
  rm -rf "$_H"
}

if [[ $fail -ne 0 ]]; then
  printf 'tests/test-fleet-devlog.sh: %s failure(s)\n' "$fail"
  exit 1
fi
printf 'tests/test-fleet-devlog.sh: all ok\n'
exit 0
