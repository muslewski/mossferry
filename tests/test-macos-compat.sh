#!/usr/bin/env bash
# tests/test-macos-compat.sh — static portable-shell fence (macOS stock bash 3.2 / BSD)
#
# Why this exists (measured, not guessed):
#   MacBook clients often have only /bin/bash 3.2.57, no flock, no ss, no /proc.
#   mapfile / declare -A / local -A / bare /usr/bin/tmux have already failed there.
#   This suite does not need a Mac, tmux, mosh, fzf, ss, or network.
#
# What it scans (shipped shell only):
#   bin/mossferry, bin/repo-session, install.sh, lib/*.sh
#
# Assertions:
#   1. No bash-4-only constructs (mapfile, readarray, declare/local -A/-n,
#      ${var^^}/${var,,}, coproc, [[ -v , &>>, ;;&, ${a[-1]})
#   2. No unconditional absolute paths to platform-moving tools
#      (/usr/bin/tmux outside command -v fallback; bare /usr/local/bin/ or
#      /opt/homebrew/ hardcoding)
#   3. No flock unless shimmed or guarded by command -v flock
#   4. No unguarded GNU-only flag forms (readlink -f, stat -c, sed -i without
#      backup suffix, date -d, base64 -w, sha256sum, nproc, xargs -r, grep -P,
#      sed -r, timeout)
#   4b. No unguarded ${name[@]}/${name[*]} expansions (bash 3.2 + set -u dies
#      on empty arrays). Portable form: ${name[@]+"${name[@]}"}. Counts
#      ${#name[@]} are safe and not flagged.
#   5. Every source/`.` of a REPO_ROOT-relative path inside bin/* is under a
#      path present in package.json "files" (npm ship set)
#
# Allowlist (deliberate exceptions only — do not loosen the patterns):
#   A trailing comment `# portable-ok: <reason>` on the SAME line silences that
#   hit. Use when a GNU form is intentional with a documented branch, or when a
#   last-resort absolute path sits inside a command -v fallback expression that
#   the automatic guard window cannot see.
#   Same-line or recent-window `command -v <tool>` also silences tool-specific
#   GNU hits and flock. Shim names (_ferry_flock / FERRY_FLOCK) silence flock.
#   DO NOT add portable-ok markers onto product sources from this test's author
#   — workers who own those files may.
#
# Expected on main before A/B/C land: FAIL (fence around a known hole).
# Self-contained: plain bash + awk. No npm, network, shellcheck, or Mac.
#
# Output style matches tests/test-install.sh / tests/test-ui-ops.sh.
# Note: GNU awk treats \b as backspace — word edges use explicit classes.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
pass=0

ok()   { pass=$((pass + 1)); printf 'ok %s\n' "$1"; }
FAIL() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Collect scan targets
# ---------------------------------------------------------------------------
TARGETS=()
for f in \
  "$ROOT/bin/mossferry" \
  "$ROOT/bin/repo-session" \
  "$ROOT/install.sh" \
  "$ROOT"/lib/*.sh
do
  if [[ -f "$f" ]]; then
    TARGETS+=("$f")
  else
    FAIL "scan target missing: $f"
  fi
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  printf 'tests/test-macos-compat.sh: no targets\n'
  exit 1
fi

# package.json "files" entries (top-level names that npm ships)
PKG_FILES_RAW="$(
  awk '
    /"files"[[:space:]]*:/ { in_files=1; next }
    in_files && /\]/ { exit }
    in_files {
      n = split($0, a, "\"")
      for (i = 2; i <= n; i += 2) {
        if (a[i] != "") print a[i]
      }
    }
  ' "$ROOT/package.json"
)"

if [[ -z "$PKG_FILES_RAW" ]]; then
  FAIL "package.json files array readable"
else
  ok "package.json files array readable"
fi

# ---------------------------------------------------------------------------
# Awk scanner written to a temp file (avoids shell-quoting landmines)
# Prints: RELPATH:LINE:RULE:snippet
# ---------------------------------------------------------------------------
SCAN_OUT="$(mktemp "${TMPDIR:-/tmp}/mf-macos-compat.XXXXXX")"
AWK_PROG="$(mktemp "${TMPDIR:-/tmp}/mf-macos-compat-awk.XXXXXX")"
trap 'rm -f "$SCAN_OUT" "$AWK_PROG"' EXIT

cat >"$AWK_PROG" <<'AWK'
BEGIN {
  n = split(pkg_files, pf, "\n")
  for (i = 1; i <= n; i++) {
    if (pf[i] != "") allowed[pf[i]] = 1
  }
  GUARD_WIN = 8
}

# Word-edge helper (gawk \b is backspace, not a boundary)
function wbeg(s, re) { return (s ~ "(^|[^A-Za-z0-9_])" re) }

function is_comment_only(s) {
  sub(/^[[:space:]]+/, "", s)
  return (s ~ /^#/)
}

function has_portable_ok(s) {
  return (s ~ /#[[:space:]]*portable-ok:/)
}

# Drop a trailing `# ...` comment so a tool name MENTIONED in a comment is not
# reported as a call. `_FERRY_LOCK_KIND=""  # flock | mkdir | empty` is code plus
# a comment, so is_comment_only() does not catch it. Quote-aware: a `#` inside a
# string is data, not a comment.
function strip_trailing_comment(s,   i, c, sq, dq) {
  sq = 0; dq = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\") { i++; continue }
    if (c == "'" && !dq) { sq = !sq; continue }
    if (c == "\"" && !sq) { dq = !dq; continue }
    if (c == "#" && !sq && !dq) {
      if (i == 1 || substr(s, i - 1, 1) ~ /[[:space:]]/) return substr(s, 1, i - 1)
    }
  }
  return s
}

# True when `re` matches OUTSIDE a double-quoted string — so a tool name inside a
# message (e.g. die "... timeout acquiring lock ...") is not read as a call.
# Checks the first match only; a quoted first occurrence hides a later bare one,
# which is an accepted limitation of a static fence.
function unquoted_match(s, re,   pre, i, c, q) {
  if (!match(s, re)) return 0
  pre = substr(s, 1, RSTART - 1)
  q = 0
  for (i = 1; i <= length(pre); i++) {
    c = substr(pre, i, 1)
    if (c == "\\") { i++; continue }
    if (c == "\"") q++
  }
  return (q % 2 == 0)
}

function guarded_tool(tool,   j, tline) {
  for (j = 0; j < GUARD_WIN; j++) {
    tline = hist[NR - j]
    if (tline == "") continue
    if (tline ~ ("command[[:space:]]+-v[[:space:]]+" tool "([^A-Za-z0-9_]|$)")) return 1
  }
  return 0
}

function emit(rule, snippet,   s) {
  s = snippet
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
  if (length(s) > 120) s = substr(s, 1, 117) "..."
  printf "%s:%d:%s:%s\n", rel, FNR, rule, s
}

function track_assign(line,   var, path, rest) {
  if (line !~ /REPO_ROOT/) return
  if (line !~ /=/) return
  rest = line
  sub(/^[[:space:]]*local[[:space:]]+/, "", rest)
  if (match(rest, /^([A-Za-z_][A-Za-z0-9_]*)=/)) {
    var = substr(rest, RSTART, RLENGTH - 1)
  } else {
    return
  }
  if (match(line, /\$\{REPO_ROOT\}\/[^"]+/)) {
    path = substr(line, RSTART, RLENGTH)
    sub(/^\$\{REPO_ROOT\}\//, "", path)
    assign_path[var] = path
  } else if (match(line, /\$REPO_ROOT\/[^"]+/)) {
    path = substr(line, RSTART, RLENGTH)
    sub(/^\$REPO_ROOT\//, "", path)
    assign_path[var] = path
  }
}

{
  rel = FILENAME
  if (match(FILENAME, /\/(bin|lib)\/[^\/]+$/)) {
    rel = substr(FILENAME, RSTART + 1)
  } else if (FILENAME ~ /install\.sh$/) {
    rel = "install.sh"
  } else {
    sub(/^.*\//, "", rel)
  }

  hist[NR] = $0
  track_assign($0)

  if (is_comment_only($0)) next
  if (has_portable_ok($0)) next

  line = strip_trailing_comment($0)

  # ---- 1. bash-4-only ----
  if (wbeg(line, "mapfile([^A-Za-z0-9_]|$)")) emit("bash4-mapfile", line)
  if (wbeg(line, "readarray([^A-Za-z0-9_]|$)")) emit("bash4-readarray", line)
  if (wbeg(line, "declare[[:space:]]+(-[a-zA-Z]*)*A")) emit("bash4-declare-A", line)
  if (wbeg(line, "local[[:space:]]+(-[a-zA-Z]*)*A[[:space:]]")) emit("bash4-local-A", line)
  if (line ~ /(^|[^A-Za-z0-9_])declare[[:space:]]+-n([[:space:]]|=|$)/) emit("bash4-declare-n", line)
  if (line ~ /(^|[^A-Za-z0-9_])local[[:space:]]+-n([[:space:]]|=|$)/) emit("bash4-local-n", line)
  if (line ~ /\$\{[A-Za-z_][A-Za-z0-9_]*\^\^/) emit("bash4-upper", line)
  if (line ~ /\$\{[A-Za-z_][A-Za-z0-9_]*,,/) emit("bash4-lower", line)
  if (wbeg(line, "coproc([^A-Za-z0-9_]|$)")) emit("bash4-coproc", line)
  if (line ~ /\[\[([^\]])*[[:space:]]-v[[:space:]]/) emit("bash4-v-test", line)
  if (index(line, "&>>") > 0) emit("bash4-append-both", line)
  if (index(line, ";;&") > 0) emit("bash4-semi-semi", line)
  if (line ~ /\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]/) emit("bash4-neg-index", line)

  # ---- 2. absolute tool paths ----
  if (index(line, "/usr/bin/tmux") > 0) {
    if (line !~ /command[[:space:]]+-v[[:space:]]+tmux/) emit("abs-tmux", line)
  }
  if (index(line, "/usr/local/bin/") > 0) emit("abs-usr-local-bin", line)
  if (index(line, "/opt/homebrew/") > 0) emit("abs-opt-homebrew", line)

  # ---- 3. flock ----
  if (wbeg(line, "flock([[:space:]]|$)")) {
    if (line !~ /command[[:space:]]+-v[[:space:]]+flock/ \
        && index(line, "_ferry_flock") == 0 \
        && index(line, "FERRY_FLOCK") == 0 \
        && index(line, "ferry_flock") == 0 \
        && !guarded_tool("flock")) {
      emit("flock-unguarded", line)
    }
  }

  # ---- 4. GNU-only forms ----
  if (line ~ /readlink[[:space:]]+-f([[:space:]]|$)/) {
    if (!guarded_tool("readlink")) emit("gnu-readlink-f", line)
  }
  if (line ~ /stat[[:space:]]+-c([[:space:]]|$)/) {
    if (!guarded_tool("stat")) emit("gnu-stat-c", line)
  }
  # bare sed -i (GNU). Portable: sed -i.bak / sed -i "" / sed -i''
  if (line ~ /sed[[:space:]]+-i([[:space:]]|$)/) {
    if (line ~ /sed[[:space:]]+-i\.bak/) {
      # sed -i.bak — accepted
    } else if (index(line, "sed -i \"\"") > 0 || index(line, "sed -i''") > 0 || index(line, "sed -i \"\"") > 0) {
      # empty backup suffix forms
    } else if (line ~ /sed[[:space:]]+-i[A-Za-z0-9._]/) {
      # glued suffix sed -iEXT
    } else {
      emit("gnu-sed-i", line)
    }
  }
  if (line ~ /date[[:space:]]+-d([[:space:]]|$)/) {
    if (!guarded_tool("date")) emit("gnu-date-d", line)
  }
  if (line ~ /base64[[:space:]]+-w/) {
    if (!guarded_tool("base64")) emit("gnu-base64-w", line)
  }
  if (wbeg(line, "sha256sum([^A-Za-z0-9_]|$)")) {
    if (!guarded_tool("sha256sum")) emit("gnu-sha256sum", line)
  }
  if (wbeg(line, "nproc([^A-Za-z0-9_]|$)")) {
    if (!guarded_tool("nproc")) emit("gnu-nproc", line)
  }
  if (line ~ /xargs[[:space:]]+-r([[:space:]]|$)/) {
    if (!guarded_tool("xargs")) emit("gnu-xargs-r", line)
  }
  # grep -P but not pgrep -P
  if (line ~ /(^|[^A-Za-z0-9_])grep[[:space:]]+-P/) {
    if (!guarded_tool("grep")) emit("gnu-grep-P", line)
  }
  if (line ~ /sed[[:space:]]+-r([[:space:]]|$)/) {
    if (!guarded_tool("sed")) emit("gnu-sed-r", line)
  }
  if (unquoted_match(line, "(^|[^A-Za-z0-9_])timeout[[:space:]]")) {
    if (!guarded_tool("timeout")) emit("gnu-timeout", line)
  }

  # ---- 4b. unguarded empty-array expansions (bash 3.2 set -u) ----
  # Under bash 3.2 + set -u, "${arr[@]}" / "${arr[*]}" is unbound when arr is
  # empty. Portable form: ${arr[@]+"${arr[@]}"}. Counts ${#arr[@]} are safe
  # (${#name not matched — name must start with [A-Za-z_]). portable-ok on
  # the same line silences via has_portable_ok above.
  {
    rest = line
    while (match(rest, /\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}/)) {
      full = substr(rest, RSTART, RLENGTH)
      before = substr(rest, 1, RSTART - 1)
      after = substr(rest, RSTART + RLENGTH)
      # Outer half of guard: ${name[@]+...
      if (after ~ /^\+/) {
        rest = substr(rest, RSTART + RLENGTH)
        continue
      }
      # Inner half of guard: ${name[@]+"${name[@]}"} — the alternate word is
      # a quoted (or bare) re-expansion immediately after +.
      if (before ~ /\+"?$/) {
        rest = substr(rest, RSTART + RLENGTH)
        continue
      }
      emit("bash32-empty-array", full)
      rest = substr(rest, RSTART + RLENGTH)
    }
  }

  # ---- 5. source targets (bin/* only) ----
  if (FILENAME ~ /\/bin\// && line ~ /^[[:space:]]*(source|\.)[[:space:]]/) {
    rest = line
    sub(/^[[:space:]]*(source|\.)[[:space:]]+/, "", rest)
    sub(/[[:space:]]+(\|\||&&).*/, "", rest)
    src = rest
    if (match(rest, /^"[^"]+"/)) {
      src = substr(rest, RSTART + 1, RLENGTH - 2)
    } else {
      sub(/[[:space:]].*/, "", src)
    }
    var = src
    gsub(/["${}]/, "", var)
    path = ""
    if (src ~ /REPO_ROOT/) {
      path = src
      sub(/^\$\{?REPO_ROOT\}?\//, "", path)
      gsub(/["]/, "", path)
    } else if (var in assign_path) {
      path = assign_path[var]
    }
    if (path != "") {
      top = path
      sub(/\/.*/, "", top)
      if (!(top in allowed)) {
        emit("source-not-shipped", line " -> " path)
      }
    }
  }
}
AWK

awk -v pkg_files="$PKG_FILES_RAW" -f "$AWK_PROG" "${TARGETS[@]}" >"$SCAN_OUT"

# ---------------------------------------------------------------------------
# Report each violation as its own named assertion
# ---------------------------------------------------------------------------
viol_count=0
if [[ -s "$SCAN_OUT" ]]; then
  while IFS= read -r row || [[ -n "$row" ]]; do
    [[ -z "$row" ]] && continue
    rel="${row%%:*}"
    rest="${row#*:}"
    lineno="${rest%%:*}"
    rest2="${rest#*:}"
    rule="${rest2%%:*}"
    snippet="${rest2#*:}"
    viol_count=$((viol_count + 1))
    FAIL "${rule} ${rel}:${lineno}: ${snippet}"
  done <"$SCAN_OUT"
fi

for rule in \
  bash4-mapfile bash4-readarray bash4-declare-A bash4-local-A \
  bash4-declare-n bash4-local-n bash4-upper bash4-lower bash4-coproc \
  bash4-v-test bash4-append-both bash4-semi-semi bash4-neg-index \
  bash32-empty-array \
  abs-tmux abs-usr-local-bin abs-opt-homebrew \
  flock-unguarded \
  gnu-readlink-f gnu-stat-c gnu-sed-i gnu-date-d gnu-base64-w \
  gnu-sha256sum gnu-nproc gnu-xargs-r gnu-grep-P gnu-sed-r gnu-timeout \
  source-not-shipped
do
  n="$(awk -F: -v r="$rule" '$3 == r { c++ } END { print c+0 }' "$SCAN_OUT")"
  if [[ "$n" -eq 0 ]]; then
    ok "no ${rule}"
  else
    FAIL "count ${rule}=${n} (see per-line FAILs above)"
  fi
done

src_bad="$(awk -F: '$3 == "source-not-shipped" { c++ } END { print c+0 }' "$SCAN_OUT")"
if [[ "$src_bad" -eq 0 ]]; then
  ok "bin/* REPO_ROOT sources are under package.json files"
fi

if [[ "$fail" -eq 0 ]]; then
  printf 'tests/test-macos-compat.sh: all ok (%s passed)\n' "$pass"
  exit 0
fi
printf 'tests/test-macos-compat.sh: %s failure(s), %s passed (%s raw violation lines)\n' \
  "$fail" "$pass" "$viol_count"
exit 1
