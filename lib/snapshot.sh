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

# Epoch → "Thu 18:48". bash ≥4.2 formats it itself; older bash is macOS's 3.2,
# where BSD `date -r <epoch>` works (GNU date -r would read a file instead).
snap_fmt_time() {
  if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) )); then
    printf '%(%a %H:%M)T\n' "$1"
  else
    date -r "$1" '+%a %H:%M' 2>/dev/null || printf '%s\n' "$1"
  fi
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

snap_log_file() { printf '%s/restore.log\n' "$(snap_state_dir)"; }
snap_log() {
  mkdir -p "$(snap_state_dir)" 2>/dev/null
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$(snap_log_file)" >&2
}

# Hidden windows (FERRY_HIDDEN_WINDOW_GLOB, default _*) are skipped: other tools
# (status-herald's _curtain) recreate them per session, so replaying them would
# duplicate. A session's first window is always kept, hidden or not.
snap_plan() {
  local f="$1" name s widx wname cwd kind id cname cmd glob first; shift
  glob="${FERRY_HIDDEN_WINDOW_GLOB:-_*}"
  for name in "$@"; do
    first=1
    while IFS=$'\t' read -r s widx wname cwd kind id cname; do
      [[ "$s" == "$name" ]] || continue
      # shellcheck disable=SC2053  # glob match is intended
      if (( ! first )) && [[ "$wname" == $glob ]]; then continue; fi
      first=0
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
