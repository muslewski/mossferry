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
hid="$(snap_dir)/600.tsv"
_snap_write "$hid" boot-A 600 "a${TAB}0${TAB}main${TAB}$T/w/a${TAB}shell${TAB}-${TAB}-
a${TAB}1${TAB}_curtain${TAB}$T/w/a${TAB}shell${TAB}-${TAB}-
b${TAB}0${TAB}_only${TAB}$T/w/a${TAB}shell${TAB}-${TAB}-"
eq "hidden window skipped" "main" "$(snap_plan "$hid" a | cut -f3 | tr '\n' ' ' | sed 's/ $//')"
eq "hidden-only session keeps its window" "_only" "$(snap_plan "$hid" b | cut -f3)"
rm -f "$hid"
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

echo "== timer install =="
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "systemctl $*" >>"%s/sysctl.log"\nexit 0\n' "$T" >"$T/bin/systemctl"; chmod +x "$T/bin/systemctl"
PATH="$T/bin:$PATH" XDG_CONFIG_HOME="$T/xdg" snap_install_timer /opt/mf/repo-session >/dev/null
eq "service ExecStart" "ExecStart=/opt/mf/repo-session --snapshot" "$(grep '^ExecStart=' "$T/xdg/systemd/user/mossferry-snapshot.service")"
eq "timer every 60s" "OnUnitActiveSec=60" "$(grep '^OnUnitActiveSec=' "$T/xdg/systemd/user/mossferry-snapshot.timer")"
eq "enabled" "1" "$(grep -c 'enable --now mossferry-snapshot.timer' "$T/sysctl.log")"
PATH="$T/bin:$PATH" XDG_CONFIG_HOME="$T/xdg" snap_install_timer /opt/mf/repo-session remove >/dev/null
eq "remove deletes units" "no" "$([ -e "$T/xdg/systemd/user/mossferry-snapshot.timer" ] && echo yes || echo no)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
