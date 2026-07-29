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
eq "two rows parsed" "2" "$(servers_parse_declarations "$decl" | wc -l)"
eq "comments skipped" "0" "$(servers_parse_declarations "$decl" | grep -c '^#' || true)"

echo "== servers_scan_listeners (fixture) =="
export FERRY_SERVERS_SS_FIXTURE=1
ss_fix='LISTEN 0 511 0.0.0.0:3000 0.0.0.0:* users:(("next-server",pid=1111,fd=20))
LISTEN 0 4096 127.0.0.1:5432 0.0.0.0:* users:(("postgres",pid=2222,fd=7))'
eq "two listeners" "2" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | wc -l)"
eq "port extracted" "3000" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | head -1 | cut -f1)"
eq "bind extracted" "127.0.0.1" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | sed -n 2p | cut -f2)"
eq "pid extracted"  "2222" "$(printf '%s\n' "$ss_fix" | servers_scan_listeners | sed -n 2p | cut -f3)"

echo "== build_server_rows =="
rows="$(export FERRY_SERVERS_DECL="$decl"; printf '%s\n' "$ss_fix" | build_server_rows)"
eq "declared-but-dead port appears" "2" "$(printf '%s\n' "$rows" | grep -c 'declared-missing' | tr -d "[:space:]")"
eq "declared 8791 is the missing one" "8791" "$(printf '%s\n' "$rows" | awk -F'\t' '$2=="declared-missing" && $1==8791{print $1}')"
eq "live 3000 is LISTEN" "LISTEN" "$(printf '%s\n' "$rows" | awk -F'\t' '$1==3000{print $2}')"
eq "postgres is loopback-only" "loopback-only" "$(printf '%s\n' "$rows" | awk -F'\t' '$1==5432{print $11}')"
eq "no row is missing columns" "0" "$(printf '%s\n' "$rows" | awk -F'\t' 'NF!=14' | wc -l)"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
