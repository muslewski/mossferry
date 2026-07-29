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
  got=$(printf '%s\n' "$line" | node -e '
    const e=JSON.parse(require("fs").readFileSync(0,"utf8"));
    process.stdout.write(e.repo_id === undefined || e.repo_id === null ? "" : String(e.repo_id));
  ' 2>/dev/null || true)
  if [[ "$got" == "$expect_id" ]]; then
    ok "repo-id-main-checkout"
  else
    FAIL "repo-id-main-checkout (got=$got want=$expect_id line=$line)"
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
  ids=$(node -e '
    const fs=require("fs");
    const lines=fs.readFileSync(process.argv[1],"utf8").trim().split("\n");
    const a=JSON.parse(lines[0]).repo_id;
    const b=JSON.parse(lines[1]).repo_id;
    process.stdout.write(String(a)+"\n"+String(b)+"\n"+(a&&a===b?"same":"diff"));
  ' "$f" 2>/dev/null || echo "parse-fail")
  id_main=$(printf '%s\n' "$ids" | sed -n '1p')
  id_wt=$(printf '%s\n' "$ids" | sed -n '2p')
  same=$(printf '%s\n' "$ids" | sed -n '3p')
  if [[ "$same" == "same" && -n "$id_main" && "$id_main" != "undefined" && "$id_main" != "null" ]]; then
    ok "repo-id-worktree-folds"
  else
    FAIL "repo-id-worktree-folds (main=$id_main wt=$id_wt same=$same)"
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
  status=$(printf '%s\n' "$line" | node -e '
    const e=JSON.parse(require("fs").readFileSync(0,"utf8"));
    if (!Object.prototype.hasOwnProperty.call(e, "repo_id")) process.stdout.write("absent");
    else if (e.repo_id === null) process.stdout.write("null");
    else if (e.repo_id === "") process.stdout.write("empty");
    else process.stdout.write("present:"+e.repo_id);
  ' 2>/dev/null || echo parse-fail)
  if [[ "$status" == "absent" ]]; then
    ok "repo-id-absent-outside-git"
  else
    FAIL "repo-id-absent-outside-git (status=$status line=$line)"
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
  js_id=$(node --input-type=module -e '
    import { resolveRepoId } from "/home/kento/Repositories/agentic-sage/lib/repo-id.mjs";
    const id = resolveRepoId(process.argv[1]);
    process.stdout.write(id == null ? "" : id);
  ' "$main_real" 2>/dev/null || true)
  (
    cd "$main_real" || exit 1
    # shellcheck disable=SC1090
    . "$LIB"
    devlog_emit doctor 0 5
  )
  f="$(events_file)"
  line=$(head -1 "$f" 2>/dev/null || true)
  got=$(printf '%s\n' "$line" | node -e '
    const e=JSON.parse(require("fs").readFileSync(0,"utf8"));
    process.stdout.write(e.repo_id == null ? "" : String(e.repo_id));
  ' 2>/dev/null || true)
  if [[ -n "$js_id" && "$got" == "$js_id" ]]; then
    ok "repo-id-matches-js-tool"
  else
    FAIL "repo-id-matches-js-tool (js=$js_id bash=$got line=$line)"
  fi
  rm -rf "$_H" "$_base"
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
  status=$(printf '%s\n' "$line" | node -e '
    let e;
    try { e=JSON.parse(require("fs").readFileSync(0,"utf8")); }
    catch (err) { process.stdout.write("bad-json"); process.exit(0); }
    if (!e || typeof e !== "object") {
      process.stdout.write("no-event");
    } else if (!Object.prototype.hasOwnProperty.call(e, "repo_id")) {
      process.stdout.write("absent");
    } else {
      process.stdout.write("present:"+e.repo_id);
    }
  ' 2>/dev/null || echo no-event)
  if [[ "$got_rc" -eq 77 && -n "$line" && "$status" == "absent" ]]; then
    ok "repo-id-hash-missing-fail-open"
  else
    FAIL "repo-id-hash-missing-fail-open (rc=$got_rc status=$status line=$line)"
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
