#!/usr/bin/env bash
# tests/test-servers.sh — fixture-driven; needs no live listeners.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/lib/servers.sh"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n     want: %s\n     got:  %s\n' "$1" "$2" "$3"; }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

echo "== servers_mac_state =="
eq "0.0.0.0 is reachable"        "reachable"     "$(servers_mac_state '0.0.0.0' 4000 ok)"
eq ":: is reachable"             "reachable"     "$(servers_mac_state '::' 4000 ok)"
eq "127.0.0.1 is loopback-only"  "loopback-only" "$(servers_mac_state '127.0.0.1' 4000 ok)"
eq "reserved beats reachable"    "reserved"      "$(servers_mac_state '0.0.0.0' 8791 ok)"
eq "mac=never forces reserved"   "reserved"      "$(servers_mac_state '0.0.0.0' 4000 never)"
eq "3000 is reserved by default" "reserved"      "$(servers_mac_state '0.0.0.0' 3000 ok)"

echo "== servers_parse_declarations =="
decl="$(mktemp)"; printf '# comment\n\n8791\tfreellmapi\tinfra\tFreeLLMAPI\tnever\t-\n3100\trender\tdev\tRender\tok\t-\n' > "$decl"
eq "two rows parsed" "2" "$(servers_parse_declarations "$decl" | wc -l | tr -d '[:space:]')"
eq "comments skipped" "0" "$(servers_parse_declarations "$decl" | grep -c '^#' || true)"

echo "== servers_scan_listeners (fixture) =="
export FERRY_SERVERS_SS_FIXTURE=1
ss_fix='LISTEN 0 511 0.0.0.0:3000 0.0.0.0:* users:(("next-server",pid=1111,fd=20))
LISTEN 0 4096 127.0.0.1:5432 0.0.0.0:* users:(("postgres",pid=2222,fd=7))'
eq "two listeners" "2" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | wc -l | tr -d '[:space:]')"
eq "port extracted" "3000" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | head -1 | cut -f1)"
eq "bind extracted" "127.0.0.1" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | sed -n 2p | cut -f2)"
eq "pid extracted"  "2222" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | sed -n 2p | cut -f3)"

echo "== build_server_rows =="
rows="$(export FERRY_SERVERS_DECL="$decl"; printf '%s\n' "$ss_fix" | build_server_rows)"
eq "declared-but-dead port appears" "2" "$(printf '%s\n' "$rows" | grep -c 'declared-missing' | tr -d '[:space:]')"
eq "declared 8791 is the missing one" "8791" "$(printf '%s\n' "$rows" | awk -F'\t' '$2=="declared-missing" && $1==8791{print $1}')"
eq "live 3000 is LISTEN" "LISTEN" "$(printf '%s\n' "$rows" | awk -F'\t' '$1==3000{print $2}')"
eq "postgres is loopback-only" "loopback-only" "$(printf '%s\n' "$rows" | awk -F'\t' '$1==5432{print $11}')"
eq "no row is missing columns" "0" "$(printf '%s\n' "$rows" | awk -F'\t' 'NF!=14' | wc -l | tr -d '[:space:]')"



echo "== servers_scan_agents =="
_as_dir="$(mktemp -d)"
mkdir -p "$_as_dir/sessions"
printf '%s\n' '{"schema":1,"pid":'"$$"',"cwd":"/tmp","model":"m","preset":"fix"}' > "$_as_dir/sessions/live.json"
printf '%s\n' '{"schema":1,"pid":999999999,"cwd":"/tmp","model":"m","preset":"dead"}' > "$_as_dir/sessions/dead.json"
_agents="$(AGENT_STATUS_DIR="$_as_dir" servers_scan_agents | awk -F'\t' '$4=="agent"' | wc -l | tr -d '[:space:]')"
eq "one live agent row" "1" "$_agents"
_agents0="$(AGENT_STATUS_DIR="/no/such/agent-status-$$" servers_scan_agents | awk -F'\t' '$4=="agent"' | wc -l | tr -d '[:space:]')"
eq "missing dir yields zero" "0" "$_agents0"
rm -rf "$_as_dir"

echo "== servers_fix_plan =="
eq "reachable → none"          "none"   "$(servers_fix_plan reachable dev 4000 /tmp | cut -f1)"
eq "loopback dev → recipe"     "recipe" "$(servers_fix_plan loopback-only dev 4000 /tmp | cut -f1)"
eq "loopback db → tunnel"      "tunnel" "$(servers_fix_plan loopback-only db 5432 /tmp | cut -f1)"
eq "loopback spine → tunnel"   "tunnel" "$(servers_fix_plan loopback-only spine 8645 /tmp | cut -f1)"
eq "reserved → refuse"         "refuse" "$(servers_fix_plan reserved infra 8791 /tmp | cut -f1)"
eq "missing → declare"         "declare" "$(servers_fix_plan declared-missing dev 9999 /tmp | cut -f1)"
eq "db never yields a recipe"  "0"      "$(servers_fix_plan loopback-only db 5432 /tmp | grep -c 'preview-serve' || true)"

echo "== repo-session --servers =="
# Fixture flag must not leak into live discovery / subprocess.
unset FERRY_SERVERS_SS_FIXTURE FERRY_SERVERS_DECL 2>/dev/null || true
RS="$ROOT/bin/repo-session"
json_out="$(bash "$RS" --servers --json 2>/dev/null)" || json_out=""
if command -v node >/dev/null 2>&1; then
  n="$(printf '%s' "$json_out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);process.stdout.write(String(Array.isArray(j)?j.length:"ERR"))}catch(e){process.stdout.write("ERR")}})' 2>/dev/null)"
  n="${n//[^0-9]/}"
  if [[ -n "$n" ]]; then
    ok "--servers --json parses (rows=$n)"
  else
    bad "--servers --json parses" "number" "${n:-empty}"
  fi
else
  ok "--servers --json skipped (no node)"
fi
prows="$(bash "$RS" --picker-servers-rows 2>/dev/null | wc -l)"
prows="${prows// /}"
if [[ -n "$prows" && "$prows" -ge 1 ]]; then
  ok "--picker-servers-rows emits lines ($prows)"
else
  bad "--picker-servers-rows emits lines" ">=1" "$prows"
fi
ff="$(mktemp)"; printf 'servers\n' >"$ff"
hdr="$(bash "$RS" --picker-face-header "$ff" 2>/dev/null)"
rm -f "$ff"
case "$hdr" in *ctrl-s*) ok "servers header has ctrl-s" ;; *) bad "servers header has ctrl-s" "ctrl-s in header" "$hdr" ;; esac
case "$hdr" in *ctrl-f*) ok "servers header has ctrl-f" ;; *) bad "servers header has ctrl-f" "ctrl-f in header" "$hdr" ;; esac

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
