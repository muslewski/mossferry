---
type: plan
summary: "Implements snapshot + restore: lib/snapshot.sh (rows, take, rotate, pre-boot pick, candidates, restore runner, hooks, timer install), repo-session flags and the ♻ picker row, tests/test-snapshot.sh, docs and 2.9.0."
status: active
created: 2026-10-15
---

# Snapshot + restore — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A host reboot becomes one picker press: snapshots every 60 s, and a ♻ row that resumes tmux sessions and their Claude conversations.

**Architecture:** All logic lives in a new `lib/snapshot.sh` of pure functions that take `TMUXBIN` and env, so tests source it directly with a stub tmux. `bin/repo-session` loads it with a stub fallback, the same way it loads `lib/servers.sh`, and adds flags plus one synthetic picker row.

**Tech Stack:** bash (3.2-compatible), awk, sed, tmux, systemd user units. No node or jq.

**Spec:** `mossferry-mind/specs/2026-10-15-snapshot-restore-design.md`

## Global Constraints

- bash 3.2 rules: no `mapfile`, no `${x,,}`, no `declare -A`, no `head -n -N`, no `tac`, no GNU-only `date -d` without a BSD `date -r` fallback.
- `send-keys` targets are never `=`-prefixed.
- No node or jq in any snapshot or restore path.
- Non-Claude windows get `FERRY_DEFAULT_CMD`, never a replayed command.
- Defaults: `FERRY_SNAPSHOT_KEEP=200`, `FERRY_RESTORE_STAGGER=15`, `FERRY_RESTORE_MAX_LOAD`=CPU count, `FERRY_RESTORE_LOAD_WAIT=300`, `FERRY_RESTORE_CLAUDE_CMD="claude --resume"`.
- State dir: `${FERRY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mossferry}`.
- Nothing restores without the operator pressing the row (or running `--restore`).

## Deviations from spec (fold into the spec in Task 1's commit)

- Identical content **rewrites the newest file's `# taken` line in place**
  instead of `touch`, so the label time needs no portable `stat`.
- The dismiss/done marker is keyed by the **snapshot's epoch**
  (`restore-done-<epoch>`), not the boot id, so it works when the boot id is
  `unknown`.
- Tests use a **test-local tmux stub** instead of extending `tests/fake-tmux`,
  which is tuned for picker tests and has no pane model.

## Review Focus

- Session names with spaces or dots (`my app`, `o.neil`) — rows, candidates and restore must keep them byte-exact. Test in Task 1 and Task 3.
- A Claude session file whose pid is alive but whose `tmux` field is empty (Claude run outside tmux) — must be ignored, not crash. Test in Task 1.
- The snapshot dir holds non-snapshot files (`.tmp.*`, editor backups) — must be ignored by list and rotate. Test in Task 2.
- A restore started twice (double Enter) — the second must refuse while the first holds the lock. Test in Task 3.
- A snapshot whose cwd no longer exists — the restore uses `$HOME` instead of failing. Test in Task 3.

---

### Task 1: rows — tmux panes joined with live Claude sessions

**Files:**
- Create: `lib/snapshot.sh`
- Create: `tests/test-snapshot.sh`
- Modify: `mossferry-mind/specs/2026-10-15-snapshot-restore-design.md` (deviations above)

**Interfaces:**
- Produces: `snap_state_dir`, `snap_dir`, `snap_boot_id`, `snap_claude_panes` (prints `pane_id\tsession_id\tname`), `snap_rows` (prints `session\twidx\twname\tcwd\tkind\tid\tname`), `_snap_json_str json key`.

- [ ] **Step 1: Write the failing test** — `tests/test-snapshot.sh`:

```bash
#!/usr/bin/env bash
# tests/test-snapshot.sh — snapshot + restore (lib/snapshot.sh) with a stub tmux.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export FERRY_STATE_DIR="$T/state" CLAUDE_CONFIG_DIR="$T/claude" FERRY_BOOT_ID="boot-B"
mkdir -p "$CLAUDE_CONFIG_DIR/sessions"

# Stub tmux: list-panes ← STUB_PANES, list-sessions ← STUB_SESSIONS,
# has-session checks STUB_SESSIONS, -P prints "<session>:<n>", every call logged.
cat >"$T/tmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_LOG:-/dev/null}"
case "$1" in
  list-panes)    [ -n "${STUB_PANES:-}" ] && printf '%s\n' "$STUB_PANES"; exit 0 ;;
  list-sessions) [ -n "${STUB_SESSIONS:-}" ] && printf '%s\n' "$STUB_SESSIONS"; exit 0 ;;
  has-session)   t="${3#=}"; printf '%s\n' "${STUB_SESSIONS:-}" | grep -qxF -- "$t"; exit $? ;;
  display-message) printf '%s\n' "${STUB_START:-0}"; exit 0 ;;
  new-session|new-window)
    s=""; while [ $# -gt 0 ]; do case "$1" in -s) s="$2"; shift 2;; -t) s="${2%:}"; shift 2;; *) shift;; esac; done
    n=$(grep -c "^new-.* $s" "${STUB_LOG:-/dev/null}" 2>/dev/null); printf '%s:%s\n' "$s" "$(( ${n:-1} - 1 ))"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$T/tmux"; export TMUXBIN="$T/tmux"

. "$ROOT/lib/snapshot.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n     want: %s\n     got:  %s\n' "$1" "$2" "$3"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }
TAB=$'\t'

echo "== snap_rows =="
mkdir -p "$T/w/a" "$T/w/b"
# live claude in synd1 (pane %3); stale pid file; live pid with empty tmux field
printf '{"pid":%s,"sessionId":"aaaa-1111","cwd":"%s","tmux":"old-name:@1.%%3","name":"synd1"}\n' "$$" "$T/w/a" >"$CLAUDE_CONFIG_DIR/sessions/1.json"
printf '{"pid":999999999,"sessionId":"dead-0000","tmux":"x:@9.%%9","name":"dead"}\n' >"$CLAUDE_CONFIG_DIR/sessions/2.json"
printf '{"pid":%s,"sessionId":"bbbb-2222","tmux":"","name":"outside"}\n' "$$" >"$CLAUDE_CONFIG_DIR/sessions/3.json"
export STUB_PANES="synd1${TAB}0${TAB}main${TAB}%2${TAB}0${TAB}$T/w/b
synd1${TAB}0${TAB}main${TAB}%3${TAB}1${TAB}$T/w/a
synd1${TAB}1${TAB}logs${TAB}%4${TAB}1${TAB}$T/w/b
my app${TAB}0${TAB}zsh${TAB}%9${TAB}1${TAB}$T/w/b"
eq "claude pane map ignores stale + empty-tmux" "%3${TAB}aaaa-1111${TAB}synd1" "$(snap_claude_panes)"
rows="$(snap_rows)"
eq "one row per window" "3" "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
eq "claude window joined by pane id after rename" "synd1${TAB}0${TAB}main${TAB}$T/w/a${TAB}claude${TAB}aaaa-1111${TAB}synd1" "$(printf '%s\n' "$rows" | sed -n 1p)"
eq "shell window uses active pane cwd" "synd1${TAB}1${TAB}logs${TAB}$T/w/b${TAB}shell${TAB}-${TAB}-" "$(printf '%s\n' "$rows" | sed -n 2p)"
eq "name with space kept" "my app" "$(printf '%s\n' "$rows" | sed -n 3p | cut -f1)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it, expect failure**

Run: `bash tests/test-snapshot.sh`
Expected: `lib/snapshot.sh: No such file` and a nonzero exit.

- [ ] **Step 3: Implement** — `lib/snapshot.sh`:

```bash
#!/usr/bin/env bash
# lib/snapshot.sh — reboot-proof hosts. Records every tmux window with its folder
# and, for Claude Code panes, the conversation id (from ~/.claude/sessions/<pid>.json,
# which Claude deletes when the process dies); replays them after a reboot.
# Sourced by bin/repo-session and tests. Needs TMUXBIN. bash 3.2, no node/jq.
# Spec: mossferry-mind/specs/2026-10-15-snapshot-restore-design.md

snap_state_dir() { printf '%s\n' "${FERRY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mossferry}"; }
snap_dir()       { printf '%s/snapshots\n' "$(snap_state_dir)"; }

# First "key":"value" string field (same contract as repo-session's _ferry_json_str_field).
_snap_json_str() {
  printf '%s' "${1-}" | awk -F'"' -v key="${2-}" '
    { for (i = 1; i <= NF; i++) if ($i == key && $(i + 1) ~ /^[[:space:]]*:[[:space:]]*$/) { print $(i + 2); exit } }'
}

snap_boot_id() {
  local b=""
  if [[ -n "${FERRY_BOOT_ID:-}" ]]; then printf '%s\n' "$FERRY_BOOT_ID"; return 0; fi
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  elif command -v sysctl >/dev/null 2>&1; then
    b=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\).*/\1/p')
  fi
  printf '%s\n' "${b:-unknown}"
}

# pane_id \t session_id \t name — live Claude Code sessions that run inside tmux.
snap_claude_panes() {
  local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions" f json pid tm sid name pane
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.json; do
    [[ -r "$f" ]] || continue
    json=$(cat "$f" 2>/dev/null) || continue
    pid=$(printf '%s' "$json" | sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || continue
    tm=$(_snap_json_str "$json" tmux)
    sid=$(_snap_json_str "$json" sessionId)
    name=$(_snap_json_str "$json" name)
    pane="${tm##*.}"
    [[ "$pane" == %* && -n "$sid" ]] || continue
    printf '%s\t%s\t%s\n' "$pane" "$sid" "${name:--}"
  done
}

# session \t window_index \t window_name \t cwd \t kind \t claude_id \t claude_name
# One row per window, in tmux order. A Claude pane wins the window; else the active pane.
snap_rows() {
  local fmt
  fmt='#{session_name}	#{window_index}	#{window_name}	#{pane_id}	#{pane_active}	#{pane_current_path}'
  {
    snap_claude_panes | sed 's/^/C	/'
    "$TMUXBIN" list-panes -a -F "$fmt" 2>/dev/null | sed 's/^/P	/'
  } | awk -F'\t' '
    $1 == "C" { cid[$2] = $3; cnm[$2] = $4; next }
    $1 == "P" {
      key = $2 "\t" $3
      if (!(key in seen)) { seen[key] = 1; order[++k] = key; wn[key] = $4; cwd[key] = $7 }
      if (($5 in cid) && !(key in id)) { id[key] = cid[$5]; nm[key] = cnm[$5]; cwd[key] = $7 }
      else if ($6 == "1" && !(key in id)) { cwd[key] = $7 }
    }
    END {
      for (i = 1; i <= k; i++) {
        key = order[i]
        if (key in id) printf "%s\t%s\t%s\tclaude\t%s\t%s\n", key, wn[key], cwd[key], id[key], nm[key]
        else           printf "%s\t%s\t%s\tshell\t-\t-\n", key, wn[key], cwd[key]
      }
    }'
}
```

- [ ] **Step 4: Run, expect pass**

Run: `bash tests/test-snapshot.sh` → `5 passed, 0 failed`.

- [ ] **Step 5: Commit** — `feat(snapshot): rows join tmux panes with live Claude sessions`, plus the spec deviation edits.

---

### Task 2: take, list, rotate, pre-boot pick, candidates, row label

**Files:** Modify `lib/snapshot.sh`, `tests/test-snapshot.sh`.

**Interfaces:**
- Consumes: `snap_rows`, `snap_boot_id`, `snap_dir`.
- Produces: `snap_take`, `snap_list` (ascending paths), `snap_list_desc`, `snap_boot_of f`, `snap_taken_of f`, `snap_body f`, `snap_rotate`, `snap_preboot` (prints path or nothing), `snap_candidates f` (session names), `snap_marker f`, `snap_dismiss f`, `snap_fmt_time epoch`, `snap_restore_label` (prints label or nothing).

- [ ] **Step 1: Failing tests** (append before the summary line):

```bash
echo "== snap_take / list / rotate =="
export FERRY_BOOT_ID="boot-A"
snap_take
eq "first snapshot written" "1" "$(snap_list | wc -l | tr -d ' ')"
f1="$(snap_list | tail -n 1)"
eq "header boot" "boot-A" "$(snap_boot_of "$f1")"
sleep 1; snap_take
eq "identical content rewrites in place" "1" "$(snap_list | wc -l | tr -d ' ')"
: >"$(snap_dir)/.tmp.123"; : >"$(snap_dir)/notes.txt~"
eq "junk files ignored by list" "1" "$(snap_list | wc -l | tr -d ' ')"
for e in 100 200 300; do cp "$f1" "$(snap_dir)/$e.tsv"; done
FERRY_SNAPSHOT_KEEP=2 snap_rotate
eq "rotate keeps newest N" "2" "$(snap_list | wc -l | tr -d ' ')"
eq "rotate keeps the real one" "$f1" "$(snap_list | tail -n 1)"
STUB_PANES="" snap_take
eq "no panes → no write" "2" "$(snap_list | wc -l | tr -d ' ')"

echo "== snap_preboot / candidates / label =="
export FERRY_BOOT_ID="boot-B"
eq "pre-boot = newest from another boot" "$f1" "$(snap_preboot)"
export STUB_SESSIONS="synd1"
eq "candidates skip live sessions" "my app" "$(snap_candidates "$f1")"
case "$(snap_restore_label)" in "♻ restore 1 session from "*) ok "label for one candidate" ;; *) bad "label" "♻ restore 1 session from …" "$(snap_restore_label)" ;; esac
snap_dismiss "$f1"
eq "dismissed → no label" "" "$(snap_restore_label)"
rm -f "$(snap_marker "$f1")"; export STUB_SESSIONS="synd1
my app"
eq "all live → no label" "" "$(snap_restore_label)"
export STUB_SESSIONS=""
eq "unknown boot → older than tmux start" "$f1" "$(FERRY_BOOT_ID=unknown STUB_START="$(( $(snap_taken_of "$f1") + 5 ))" snap_preboot)"
eq "unknown boot, snapshot after start → none" "" "$(FERRY_BOOT_ID=unknown STUB_START=1 snap_preboot)"
```

- [ ] **Step 2: Run** → the new cases fail (`snap_take: command not found`).

- [ ] **Step 3: Implement** (append to `lib/snapshot.sh`):

```bash
snap_list() {
  local d; d=$(snap_dir)
  [[ -d "$d" ]] || return 0
  ls "$d" 2>/dev/null | grep -E '^[0-9]+\.tsv$' | sort -n | sed "s|^|$d/|"
}
snap_list_desc() { snap_list | awk '{ a[NR] = $0 } END { for (i = NR; i >= 1; i--) print a[i] }'; }
snap_boot_of()  { sed -n 's/^# boot //p' "$1" 2>/dev/null | head -n 1; }
snap_taken_of() { sed -n 's/^# taken //p' "$1" 2>/dev/null | head -n 1; }
snap_body()     { grep -v '^#' "$1" 2>/dev/null; }

_snap_write() { # path boot epoch rows
  local tmp; tmp="$(dirname "$1")/.tmp.$$"
  { printf '# mossferry-snapshot v1\n# boot %s\n# taken %s\n' "$2" "$3"; printf '%s\n' "$4"; } >"$tmp" && mv -f "$tmp" "$1"
}

snap_take() {
  local rows dir boot now newest
  rows=$(snap_rows)
  [[ -n "$rows" ]] || return 0
  dir=$(snap_dir); mkdir -p "$dir" 2>/dev/null || return 0
  boot=$(snap_boot_id); now=$(date +%s)
  newest=$(snap_list | tail -n 1)
  if [[ -n "$newest" && "$(snap_boot_of "$newest")" == "$boot" && "$(snap_body "$newest")" == "$rows" ]]; then
    _snap_write "$newest" "$boot" "$now" "$rows"
    return 0
  fi
  _snap_write "$dir/$now.tsv" "$boot" "$now" "$rows"
  snap_rotate
}

snap_rotate() {
  local keep="${FERRY_SNAPSHOT_KEEP:-200}" total excess
  total=$(snap_list | wc -l | tr -d ' ')
  excess=$(( total - keep ))
  (( excess > 0 )) || return 0
  snap_list | head -n "$excess" | while IFS= read -r f; do rm -f "$f"; done
}

# Newest snapshot taken before this boot: different boot id, or — when either
# side is unknown — taken before the tmux server started.
snap_preboot() {
  local boot f fb start
  boot=$(snap_boot_id)
  start=$("$TMUXBIN" display-message -p '#{start_time}' 2>/dev/null)
  [[ "$start" =~ ^[0-9]+$ ]] || start=$(date +%s)
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    fb=$(snap_boot_of "$f")
    if [[ "$boot" != unknown && -n "$fb" && "$fb" != unknown ]]; then
      [[ "$fb" != "$boot" ]] && { printf '%s\n' "$f"; return 0; }
    else
      (( $(snap_taken_of "$f") < start )) && { printf '%s\n' "$f"; return 0; }
    fi
  done < <(snap_list_desc)
}

# Session names in snapshot $1 that are not live now, first-seen order.
snap_candidates() {
  {
    "$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null | sed 's/^/L	/'
    snap_body "$1" | cut -f1 | sed 's/^/S	/'
  } | awk -F'\t' '$1 == "L" { live[$2] = 1; next } $1 == "S" && !($2 in live) && !($2 in seen) { seen[$2] = 1; print $2 }'
}

snap_marker()  { printf '%s/restore-done-%s\n' "$(snap_state_dir)" "$(basename "$1" .tsv)"; }
snap_dismiss() { mkdir -p "$(snap_state_dir)" && : >"$(snap_marker "$1")"; }

snap_fmt_time() {
  date -d "@$1" '+%a %H:%M' 2>/dev/null || date -r "$1" '+%a %H:%M' 2>/dev/null || printf '%s\n' "$1"
}

snap_restore_label() {
  local f n s=""
  f=$(snap_preboot); [[ -n "$f" ]] || return 0
  [[ -e "$(snap_marker "$f")" ]] && return 0
  n=$(snap_candidates "$f" | grep -c .)
  (( n > 0 )) || return 0
  (( n == 1 )) || s=s
  printf '♻ restore %d session%s from %s\n' "$n" "$s" "$(snap_fmt_time "$(snap_taken_of "$f")")"
}
```

- [ ] **Step 4: Run** → all pass.
- [ ] **Step 5: Commit** — `feat(snapshot): take/rotate and pre-boot restore candidates`.

---

### Task 3: restore runner, pacing, hooks, dry run

**Files:** Modify `lib/snapshot.sh`, `tests/test-snapshot.sh`.

**Interfaces:**
- Consumes: Task 2 functions.
- Produces: `snap_plan f names…` (prints `session\twidx\twname\tcwd\tkind\tcmd`), `snap_restore_run f names…` (0 on success, 1 when locked), `snap_log msg`, `snap_log_file`, `snap_dry_run f names…`.

- [ ] **Step 1: Failing tests:**

```bash
echo "== restore =="
export FERRY_RESTORE_STAGGER=0 FERRY_RESTORE_LOAD_WAIT=0 FERRY_DEFAULT_CMD="true" STUB_SESSIONS=""
snapf="$(snap_dir)/500.tsv"
_snap_write "$snapf" boot-A 500 "synd1${TAB}0${TAB}main${TAB}$T/w/a${TAB}claude${TAB}aaaa-1111${TAB}synd1
synd1${TAB}1${TAB}logs${TAB}$T/gone${TAB}shell${TAB}-${TAB}-
o.neil${TAB}0${TAB}zsh${TAB}$T/w/b${TAB}claude${TAB}cccc-3333${TAB}o"
plan="$(snap_plan "$snapf" synd1)"
eq "plan claude cmd" "claude --resume aaaa-1111" "$(printf '%s\n' "$plan" | sed -n 1p | cut -f6)"
eq "missing cwd falls back to HOME" "$HOME" "$(printf '%s\n' "$plan" | sed -n 2p | cut -f4)"
eq "shell gets FERRY_DEFAULT_CMD" "true" "$(printf '%s\n' "$plan" | sed -n 2p | cut -f6)"
export STUB_LOG="$T/log"; : >"$STUB_LOG"
mkdir -p "$HOME/.config/mossferry/restore.d"
printf '#!/bin/sh\necho "h1 $1 [$FERRY_RESTORED_SESSIONS]" >>"%s/hooks"\nexit 3\n' "$T" >"$HOME/.config/mossferry/restore.d/10-a"
printf '#!/bin/sh\necho "h2" >>"%s/hooks"\n' "$T" >"$HOME/.config/mossferry/restore.d/20-b"
chmod +x "$HOME/.config/mossferry/restore.d/"*
snap_restore_run "$snapf" synd1 o.neil 2>/dev/null
eq "new-session for synd1" "1" "$(grep -c '^new-session -d -P -F #{session_name}:#{window_index} -s synd1 -n main -c ' "$STUB_LOG")"
eq "new-window for second window" "1" "$(grep -c '^new-window -P -F #{session_name}:#{window_index} -t synd1: -n logs -c ' "$STUB_LOG")"
eq "resume sent to returned target" "1" "$(grep -c '^send-keys -t synd1:0 claude --resume aaaa-1111 C-m' "$STUB_LOG")"
eq "dotted name restored" "1" "$(grep -c '^new-session .* -s o.neil ' "$STUB_LOG")"
eq "hooks ran in order, failure did not stop next" "h1 $snapf [synd1 o.neil]
h2" "$(cat "$T/hooks")"
eq "marker written" "yes" "$([ -e "$(snap_marker "$snapf")" ] && echo yes)"
: >"$STUB_LOG"; export STUB_SESSIONS="synd1"
snap_restore_run "$snapf" synd1 2>/dev/null
eq "live session skipped" "0" "$(grep -c '^new-session' "$STUB_LOG")"
mkdir -p "$(snap_state_dir)/restore.lock"
snap_restore_run "$snapf" o.neil 2>/dev/null; eq "second restore refuses while locked" "1" "$?"
rmdir "$(snap_state_dir)/restore.lock"
eq "dry run prints, runs nothing" "0" "$(: >"$STUB_LOG"; snap_dry_run "$snapf" o.neil >/dev/null; grep -c '^new-' "$STUB_LOG")"
```

- [ ] **Step 2: Run** → the new cases fail.

- [ ] **Step 3: Implement** (append):

```bash
snap_log_file() { printf '%s/restore.log\n' "$(snap_state_dir)"; }
snap_log() {
  mkdir -p "$(snap_state_dir)" 2>/dev/null
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$(snap_log_file)" >&2
}

snap_plan() {
  local f="$1" name s widx wname cwd kind id cname cmd; shift
  for name in "$@"; do
    while IFS=$'\t' read -r s widx wname cwd kind id cname; do
      [[ "$s" == "$name" ]] || continue
      [[ -d "$cwd" ]] || cwd="$HOME"
      if [[ "$kind" == claude && "$id" != - ]]; then cmd="${FERRY_RESTORE_CLAUDE_CMD:-claude --resume} $id"
      else cmd="${FERRY_DEFAULT_CMD:-}"; kind=shell; fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$widx" "$wname" "$cwd" "$kind" "$cmd"
    done < <(snap_body "$f")
  done
}

snap_dry_run() {
  local s widx wname cwd kind cmd
  while IFS=$'\t' read -r s widx wname cwd kind cmd; do
    printf '%-20s %-3s %-16s %s\n      → %s\n' "$s" "$widx" "$wname" "$cwd" "${cmd:-(empty shell)}"
  done < <(snap_plan "$@")
}

snap_ncpu() { getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4; }
snap_load1() {
  if [[ -n "${FERRY_TEST_LOAD:-}" ]]; then printf '%s\n' "$FERRY_TEST_LOAD"; return; fi
  if [[ -r /proc/loadavg ]]; then cut -d' ' -f1 /proc/loadavg
  else sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }'; fi
}
_snap_pace() {
  local stagger="${FERRY_RESTORE_STAGGER:-15}" max="${FERRY_RESTORE_MAX_LOAD:-$(snap_ncpu)}"
  local cap="${FERRY_RESTORE_LOAD_WAIT:-300}" waited=0
  (( stagger > 0 )) && sleep "$stagger"
  while (( waited < cap )) && awk -v l="$(snap_load1)" -v m="$max" 'BEGIN { exit !(l > m) }'; do
    (( waited == 0 )) && snap_log "load $(snap_load1) > $max — waiting (max ${cap}s)"
    sleep 5; waited=$(( waited + 5 ))
  done
}

_snap_hooks() {
  local f="$1" restored="$2" d h rc
  d="${FERRY_CONFIG_DIR:-$HOME/.config/mossferry}/restore.d"
  [[ -d "$d" ]] || return 0
  for h in "$d"/*; do
    [[ -f "$h" && -x "$h" ]] || continue
    FERRY_RESTORED_SESSIONS="$restored" "$h" "$f" >>"$(snap_log_file)" 2>&1; rc=$?
    if (( rc == 0 )); then snap_log "hook ok: $(basename "$h")"; else snap_log "hook FAILED rc=$rc: $(basename "$h")"; fi
  done
}

# Recreate the named sessions from snapshot $1. One run at a time (mkdir lock).
snap_restore_run() {
  local f="$1" lock prev="" skip=0 claude_seen=0 restored="" tgt
  local s widx wname cwd kind cmd
  shift
  lock="$(snap_state_dir)/restore.lock"
  mkdir -p "$(snap_state_dir)" 2>/dev/null
  if ! mkdir "$lock" 2>/dev/null; then snap_log "restore already running ($lock)"; return 1; fi
  snap_log "restore from $(basename "$f"): $*"
  while IFS=$'\t' read -r s widx wname cwd kind cmd <&3; do
    if [[ "$s" != "$prev" ]]; then
      prev="$s"; skip=0
      if "$TMUXBIN" has-session -t "=$s" 2>/dev/null; then snap_log "skip $s (already live)"; skip=1; continue; fi
      [[ "$kind" == claude ]] && { (( claude_seen )) && _snap_pace; claude_seen=1; }
      tgt=$("$TMUXBIN" new-session -d -P -F '#{session_name}:#{window_index}' -s "$s" -n "$wname" -c "$cwd")
      restored="${restored:+$restored }$s"
    else
      (( skip )) && continue
      [[ "$kind" == claude ]] && { (( claude_seen )) && _snap_pace; claude_seen=1; }
      tgt=$("$TMUXBIN" new-window -P -F '#{session_name}:#{window_index}' -t "$s:" -n "$wname" -c "$cwd")
    fi
    [[ -n "$cmd" ]] && "$TMUXBIN" send-keys -t "${tgt:-$s:}" "$cmd" C-m
    snap_log "restored $s:$wname ($kind)"
  done 3< <(snap_plan "$f" "$@")
  _snap_hooks "$f" "$restored"
  snap_dismiss "$f"
  rmdir "$lock" 2>/dev/null
  snap_log "restore done: ${restored:-nothing}"
}
```

- [ ] **Step 4: Run** → all pass.
- [ ] **Step 5: Commit** — `feat(snapshot): staggered restore runner with restore.d hooks`.

---

### Task 4: timer install

**Files:** Modify `lib/snapshot.sh`, `tests/test-snapshot.sh`.

**Interfaces:** Produces `snap_install_timer self [remove]`.

- [ ] **Step 1: Failing tests:**

```bash
echo "== timer install =="
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "systemctl $*" >>"%s/sysctl.log"\nexit 0\n' "$T" >"$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
PATH="$T/bin:$PATH" XDG_CONFIG_HOME="$T/xdg" snap_install_timer /opt/mf/repo-session >/dev/null
eq "service ExecStart" "ExecStart=/opt/mf/repo-session --snapshot" "$(grep '^ExecStart=' "$T/xdg/systemd/user/mossferry-snapshot.service")"
eq "timer every 60s" "OnUnitActiveSec=60" "$(grep '^OnUnitActiveSec=' "$T/xdg/systemd/user/mossferry-snapshot.timer")"
eq "enabled" "1" "$(grep -c 'enable --now mossferry-snapshot.timer' "$T/sysctl.log")"
PATH="$T/bin:$PATH" XDG_CONFIG_HOME="$T/xdg" snap_install_timer /opt/mf/repo-session remove >/dev/null
eq "remove deletes units" "no" "$([ -e "$T/xdg/systemd/user/mossferry-snapshot.timer" ] && echo yes || echo no)"
```

- [ ] **Step 2: Run** → fails.
- [ ] **Step 3: Implement:**

```bash
snap_install_timer() {
  local self="$1" mode="${2:-}" ud
  ud="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
    printf 'No systemd user manager here. Add this line with `crontab -e` instead:\n* * * * * %s --snapshot\n' "$self"
    return 0
  fi
  if [[ "$mode" == remove ]]; then
    systemctl --user disable --now mossferry-snapshot.timer >/dev/null 2>&1
    rm -f "$ud/mossferry-snapshot.timer" "$ud/mossferry-snapshot.service"
    systemctl --user daemon-reload >/dev/null 2>&1
    printf 'snapshot timer removed\n'; return 0
  fi
  mkdir -p "$ud" || return 1
  printf '[Unit]\nDescription=mossferry snapshot (tmux windows + Claude conversations)\n\n[Service]\nType=oneshot\nEnvironment=PATH=%s\nExecStart=%s --snapshot\n' \
    "$PATH" "$self" >"$ud/mossferry-snapshot.service"
  printf '[Unit]\nDescription=mossferry snapshot every 60s\n\n[Timer]\nOnBootSec=60\nOnUnitActiveSec=60\nAccuracySec=10\n\n[Install]\nWantedBy=timers.target\n' \
    >"$ud/mossferry-snapshot.timer"
  systemctl --user daemon-reload && systemctl --user enable --now mossferry-snapshot.timer
  printf 'snapshot timer on: every 60s → %s\n' "$(snap_dir)"
}
```

- [ ] **Step 4: Run** → pass. **Step 5: Commit** — `feat(snapshot): systemd user timer install/remove`.

---

### Task 5: repo-session wiring — flags, ♻ row, restore flow

**Files:** Modify `bin/repo-session` (loader near `_ferry_load_servers`, `picker_kill`, `print_picker_rows`, `run_picker`, `main` flag parsing, help text); `tests/test-repo-session.sh`.

**Interfaces:** Consumes everything above. New flags: `--snapshot`, `--snapshot-install [--remove]`, `--restore [--dry-run]`, internal `--restore-run <file> <names…>`, `--restore-preview <file> <name>`.

- [ ] **Step 1: Failing tests** in `tests/test-repo-session.sh`, matching its existing harness (fake tmux on PATH, `FERRY_NO_FZF=1`):
  - `repo-session --snapshot` with `FERRY_STATE_DIR` set and fake sessions exits 0.
  - `repo-session --picker-rows` prints a line starting `♻ restore` when a pre-boot snapshot fixture (boot `old`, `FERRY_BOOT_ID=new`) names a session that isn't live, and prints none after `repo-session --picker-kill "♻ restore 1 session from x"`.
  - `repo-session --restore --dry-run` prints the fixture's session name and `claude --resume`.
  - `repo-session --help` mentions `--snapshot-install` and `--restore`.

- [ ] **Step 2: Implement:**

```bash
# ---- snapshot/restore (lib/snapshot.sh) — missing lib degrades to no row ----
_ferry_load_snapshot() {
  local s="${REPO_ROOT}/lib/snapshot.sh"
  [[ -r "$s" ]] && source "$s"
  if ! declare -F snap_restore_label >/dev/null 2>&1; then
    snap_restore_label() { return 0; }
    snap_take() { return 0; }
  fi
}
_ferry_load_snapshot
```

`picker_kill`: right after the quote-strip, add
`if [[ "$name" == ♻* ]]; then local f; f=$(snap_preboot); [[ -n "$f" ]] && snap_dismiss "$f"; return 0; fi`.

`print_picker_rows`: before the `➕` label,
`local rl; rl=$(snap_restore_label 2>/dev/null); [[ -n "$rl" ]] && printf '%s\n' "$rl"`.

New function next to `_do_new_session_flow`:

```bash
# ♻ row: multi-select candidates (all preselected), restore in the background.
_do_restore_flow() {
  local f self picks n log
  f=$(snap_preboot); [[ -n "$f" ]] || return 1
  self=$(_ferry_resolve_self "${BASH_SOURCE[0]}")
  if command -v fzf >/dev/null 2>&1 && [[ -z "${FERRY_NO_FZF:-}" ]]; then
    picks=$(snap_candidates "$f" | fzf --multi --bind 'load:select-all' --layout=reverse \
      --header "♻ restore from $(snap_fmt_time "$(snap_taken_of "$f")") · tab=toggle · enter=restore · esc=back" \
      --preview "bash $(printf '%q' "$self") --restore-preview $(printf '%q' "$f") {}" --preview-window=right:60%) || return 1
  else
    picks=$(snap_candidates "$f")
  fi
  [[ -n "$picks" ]] || return 1
  n=$(printf '%s\n' "$picks" | grep -c .)
  log=$(snap_log_file); mkdir -p "$(dirname "$log")"
  # shellcheck disable=SC2046
  ( IFS=$'\n'; nohup bash "$self" --restore-run "$f" $picks >>"$log" 2>&1 & )
  printf 'restoring %d session(s) in the background — log: %s\n' "$n" "$log" >/dev/tty 2>/dev/null || true
  sleep 1
  return 0
}
```

`run_picker`: at the top, `( snap_take >/dev/null 2>&1 & )`. In the fzf
dispatch, after the judge-row check:
`if [[ "$name" == ♻* ]]; then _do_restore_flow || true; continue; fi`.
In the numbered fallback, print `r) <label>` when the label is non-empty and
handle `r|R) _do_restore_flow || true; continue ;;`.

`main` flags (alongside `--servers`):

```bash
      --snapshot)          snap_take; exit 0 ;;
      --snapshot-install)  if [[ "${2:-}" == --remove ]]; then snap_install_timer "$(_ferry_resolve_self "${BASH_SOURCE[0]}")" remove; else snap_install_timer "$(_ferry_resolve_self "${BASH_SOURCE[0]}")"; fi; exit $? ;;
      --restore)           _rf=$(snap_preboot); [[ -n "$_rf" ]] || { echo "nothing to restore"; exit 0; }
                           _rn=(); while IFS= read -r _l; do [[ -n "$_l" ]] && _rn+=("$_l"); done < <(snap_candidates "$_rf")
                           (( ${#_rn[@]} )) || { echo "nothing to restore — every snapshotted session is live"; exit 0; }
                           if [[ "${2:-}" == --dry-run ]]; then snap_dry_run "$_rf" "${_rn[@]}"; else snap_restore_run "$_rf" "${_rn[@]}"; fi; exit $? ;;
      --restore-run)       shift; _rf="$1"; shift; snap_restore_run "$_rf" "$@"; exit $? ;;
      --restore-preview)   snap_body "${2:-}" | awk -F'\t' -v s="${3:-}" '$1 == s { printf "%s  %-14s %s\n   %s %s\n", $2, $3, $4, $5, ($5 == "claude" ? $7 " · " $6 : "") }'; exit 0 ;;
```

These flags need `TMUXBIN`. Place them after `_require_tmux` sets it, or call
`_require_tmux` first inside each branch, whichever matches the existing
order in `main`.

Help: add under Primary commands:
```
  repo-session --snapshot-install   record sessions every 60s (systemd user timer); --remove to undo
  repo-session --restore [--dry-run]  bring back sessions that were alive before the last reboot
```

- [ ] **Step 3: Run** `bash tests/run.sh` → every suite green.
- [ ] **Step 4: Commit** — `feat(picker): ♻ restore row and snapshot/restore flags`.

---

### Task 6: docs, config, version, recollection

**Files:** `config.example`, `docs/configuration.md`, `docs/command-reference.md`, `docs/troubleshooting.md`, `CHANGELOG.md`, `VERSION`, `package.json`, `mossferry-mind/map/zones/{repo-session,install-config,tests}.md`, `README.md` (one line under features).

- [ ] Add the six `FERRY_*` keys to `config.example` (commented, with defaults) and to `docs/configuration.md`.
- [ ] `docs/command-reference.md`: `--snapshot`, `--snapshot-install [--remove]`, `--restore [--dry-run]`, and the ♻ row.
- [ ] `docs/troubleshooting.md`: an "After a reboot" section — run `ferry <host>`, press ♻; or `ssh <host> repo-session --restore`; `restore.d` hooks for product-specific revival; logs at `~/.local/state/mossferry/restore.log`.
- [ ] Bump `VERSION` and `package.json` to 2.9.0; add a CHANGELOG entry.
- [ ] Update the zone cards' claims; commit; `atlas stamp repo-session install-config tests`; `atlas build`; amend.
- [ ] Docs soft-nudge: `node ../docs-kit/bin/docs-kit.mjs health docs/` if docs-kit exists locally, else record `NOT RUN (docs-kit absent)`.
- [ ] Commit — `docs: snapshot + restore, 2.9.0`.

---

### Task 7: dogfood on the real host (not committed)

- [ ] Install from the branch without pushing: `npm pack` in the repo, then `npm i -g ./mossferry-2.9.0.tgz`. Verify `find ~/.local/bin -xtype l` is empty.
- [ ] `repo-session --snapshot-install`; `systemctl --user list-timers mossferry-snapshot.timer`; after 70 s, check the newest file under `~/.local/state/mossferry/snapshots/` lists every live syndcast session with `claude` and the right ids.
- [ ] Fake a pre-boot: copy the newest snapshot to a new epoch file with `# boot fake-old` and a session renamed to `zz-restore-test` (one shell window, cwd `$HOME`). `repo-session --picker-rows` shows `♻ restore 1 session…`. `repo-session --restore --dry-run` shows it. `repo-session --restore` creates `zz-restore-test`. Kill it, delete the fake file and its marker.
- [ ] Record PASS/FAIL with evidence.
