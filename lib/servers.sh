#!/usr/bin/env bash
# lib/servers.sh — layered server discovery for mossferry servers view.
# Full servers view needs bash + ss + /proc (Linux host). Sourceable pure
# functions. On hosts lacking ss or /proc, build_server_rows degrades with
# one stderr notice (non-fatal) unless FERRY_SERVERS_SS_FIXTURE is set.
# Row model (14 columns, tab-separated):
#   port state id class label bind pid comm repo owner mac_state mac_url health restart
#
# shellcheck disable=SC2034

# Once-per-shell capability warning (empty servers view without ss//proc).
_FERRY_SERVERS_CAPABILITY_WARNED=0

# Reserved ports (from preview-serve denylist). Never primary Mac URL.
FERRY_SERVERS_RESERVED="${FERRY_SERVERS_RESERVED:-8791 3001 5432 6379 27017 8080 5173 3000}"

_servers_dash() {
  local v="${1:-}"
  if [[ -z "$v" || "$v" == "-" ]]; then
    printf '%s' "-"
  else
    printf '%s' "$v"
  fi
}

# True if port is in the reserved denylist.
_servers_port_reserved() {
  local port="$1" r
  for r in $FERRY_SERVERS_RESERVED; do
    [[ "$r" == "$port" ]] && return 0
  done
  return 1
}

# True if bind address is loopback-only.
_servers_bind_loopback() {
  local bind="$1"
  case "$bind" in
    127.0.0.1|127.*|::1|localhost|'[::1]') return 0 ;;
    *) return 1 ;;
  esac
}

# True if bind is all-interfaces (Mac-reachable when not reserved).
_servers_bind_all() {
  local bind="$1"
  case "$bind" in
    0.0.0.0|::|'*'|'[::]'|\[::\]) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve Mac-reachability: reachable | loopback-only | reserved | unknown
# Order: mac=never → reserved; loopback bind → loopback-only; reserved port → reserved;
# all-interfaces → reachable; else unknown.
servers_mac_state() {
  local bind="${1:-}" port="${2:-}" mac_policy="${3:-ok}"
  if [[ "$mac_policy" == "never" ]]; then
    printf 'reserved\n'
    return 0
  fi
  if _servers_bind_loopback "$bind"; then
    printf 'loopback-only\n'
    return 0
  fi
  if _servers_port_reserved "$port"; then
    printf 'reserved\n'
    return 0
  fi
  if _servers_bind_all "$bind"; then
    printf 'reachable\n'
    return 0
  fi
  # Bound to a specific non-loopback address (e.g. Tailscale IP) — treat as reachable.
  if [[ -n "$bind" && "$bind" != "-" ]]; then
    printf 'reachable\n'
    return 0
  fi
  printf 'unknown\n'
}

# Compute mac_url for a reachable listener. Never emit 127.0.0.1 as primary.
# Uses preview-url when on PATH; else Tailscale IP → MagicDNS → LAN fallback.
servers_mac_url() {
  local bind="$1" port="$2" mac_state="$3"
  if [[ "$mac_state" != "reachable" ]]; then
    printf '%s\n' '-'
    return 0
  fi
  if _servers_port_reserved "$port"; then
    printf '%s\n' '-'
    return 0
  fi
  local url host
  if command -v preview-url >/dev/null 2>&1; then
    url="$(preview-url "$port" / 2>/dev/null | head -1 | tr -d '\r')" || url=""
    # Refuse bare loopback as primary.
    if [[ -n "$url" && "$url" != *'127.0.0.1'* && "$url" != *'localhost'* ]]; then
      printf '%s\n' "$url"
      return 0
    fi
  fi
  host=""
  if command -v preview-host >/dev/null 2>&1; then
    host="$(preview-host 2>/dev/null | head -1 | tr -d '\r')" || host=""
  fi
  if [[ -z "$host" ]] && command -v tailscale >/dev/null 2>&1; then
    host="$(tailscale ip -4 2>/dev/null | head -1 | tr -d '\r')" || host=""
  fi
  if [[ -z "$host" || "$host" == "127.0.0.1" || "$host" == "localhost" ]]; then
    printf '%s\n' '-'
    return 0
  fi
  printf 'http://%s:%s/\n' "$host" "$port"
}

# Parse one or more TSV declaration files → port id class label mac health
# Skips blanks and # comments. Later files override earlier per port (caller merges).
servers_parse_declarations() {
  local f line port id class label mac health rest
  for f in "$@"; do
    [[ -n "$f" && -r "$f" ]] || continue
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
      # strip CR
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      [[ "$line" == \#* ]] && continue
      # Skip pure whitespace
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      IFS=$'\t' read -r port id class label mac health rest <<<"$line" || true
      [[ -z "${port:-}" || "$port" == "port" ]] && continue
      # Skip if port is not numeric
      [[ "$port" =~ ^[0-9]+$ ]] || continue
      id="${id:--}"
      class="${class:--}"
      label="${label:--}"
      mac="${mac:-ok}"
      [[ -z "$mac" || "$mac" == "-" ]] && mac="ok"
      health="${health:--}"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$port" "$id" "$class" "$label" "$mac" "$health"
    done <"$f"
  done
}

# L1: parse ss -ltnp (or stdin when FERRY_SERVERS_SS_FIXTURE is set)
# Emits: port \t bind \t pid \t comm
servers_scan_listeners() {
  local line rest local_addr peer users addr bind port pid comm
  local input
  if [[ -n "${FERRY_SERVERS_SS_FIXTURE:-}" ]]; then
    input=$(cat)
  else
    input="$(ss -ltnp 2>/dev/null || true)"
  fi
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "$line" ]] && continue
    # Skip header
    [[ "$line" == State* || "$line" == Netid* ]] && continue
    # Must look like a LISTEN line
    [[ "$line" == LISTEN* || "$line" == *LISTEN* ]] || continue

    # Extract users=(...) block if present
    users=""
    if [[ "$line" == *'users:('* ]]; then
      users="$(printf '%s\n' "$line" | sed -n 's/.*users:(\(.*\))$/\1/p')"
    fi

    # Local address is typically field 4 in `ss -ltnp` output.
    # Fields: State Recv-Q Send-Q Local Address:Port Peer Address:Port
    # Use awk-free field split carefully (IPv6 has colons).
    set -- $line
    # Find the first token that looks like addr:port or [addr]:port
    local_addr=""
    local tok
    for tok in "$@"; do
      case "$tok" in
        LISTEN|UNCONN|ESTAB) continue ;;
      esac
      # Pure numeric Recv-Q / Send-Q — skip. Addresses like 0.0.0.0:3000 must not match.
      if [[ "$tok" =~ ^[0-9]+$ ]]; then
        continue
      fi
      # First token that looks like addr:port (IPv4, IPv6, or *)
      if [[ "$tok" == *:* ]]; then
        local_addr="$tok"
        break
      fi
    done
    [[ -z "$local_addr" ]] && continue

    # Split bind / port from the right.
    if [[ "$local_addr" == \[*\]:* ]]; then
      # [ipv6]:port
      port="${local_addr##*]:}"
      bind="${local_addr%]:*}"
      bind="${bind#\[}"
    else
      port="${local_addr##*:}"
      bind="${local_addr%:*}"
    fi
    # Strip interface suffix (127.0.0.53%lo)
    bind="${bind%%\%*}"
    [[ "$port" =~ ^[0-9]+$ ]] || continue
    [[ -z "$bind" ]] && bind="-"

    pid="-"
    comm="-"
    if [[ -n "$users" ]]; then
      # users:(("name",pid=1111,fd=20)) — sed extract (bash ERE is fragile here)
      pid="$(printf '%s\n' "$users" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -1)"
      [[ -z "$pid" ]] && pid="-"
      # users may be ("name",pid=…) after outer strip
      comm="$(printf '%s\n' "$users" | sed -n 's/.*(\"\([^"]*\)\".*/\1/p' | head -1)"
      if [[ -z "$comm" ]]; then
        comm="$(printf '%s\n' "$users" | sed -n 's/.*((\{0,1\}\([^,)"]*\).*/\1/p' | head -1)"
        comm="${comm//\"/}"
      fi
      [[ -z "$comm" ]] && comm="-"
    fi
    printf '%s\t%s\t%s\t%s\n' "$port" "$bind" "$pid" "$comm"
  done <<<"$input"
}

# L2: spine when pid is a systemctl --user MainPID
servers_class_systemd() {
  local pid="${1:-}"
  [[ -n "$pid" && "$pid" != "-" && "$pid" =~ ^[0-9]+$ ]] || { printf ''; return 0; }
  command -v systemctl >/dev/null 2>&1 || { printf ''; return 0; }
  local unit main
  # List user units' MainPID — degrade silently
  while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    main="$(systemctl --user show -p MainPID --value "$unit" 2>/dev/null || true)"
    if [[ "$main" == "$pid" ]]; then
      printf 'spine'
      return 0
    fi
  done < <(systemctl --user list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print $1}' || true)
  printf ''
}

# L3: docker class + restart policy for a published host port
servers_class_docker() {
  local port="${1:-}"
  [[ -n "$port" && "$port" =~ ^[0-9]+$ ]] || { printf ''; return 0; }
  command -v docker >/dev/null 2>&1 || { printf ''; return 0; }
  local cid restart
  # Match host port in docker ps Ports column (e.g. 0.0.0.0:8791->…)
  cid="$(docker ps --format '{{.ID}} {{.Ports}}' 2>/dev/null | awk -v p=":$port->" 'index($0,p){print $1; exit}' || true)"
  [[ -n "$cid" ]] || { printf ''; return 0; }
  restart="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$cid" 2>/dev/null || true)"
  restart="${restart:-}"
  if [[ -n "$restart" && "$restart" != "no" ]]; then
    printf 'docker\t%s' "$restart"
  else
    printf 'docker\t-'
  fi
}

# L4: tmux session owning this pid (walk pane_pid tree)
servers_tmux_owner() {
  local pid="${1:-}"
  [[ -n "$pid" && "$pid" != "-" && "$pid" =~ ^[0-9]+$ ]] || { printf ''; return 0; }
  command -v tmux >/dev/null 2>&1 || { printf ''; return 0; }
  local line ppid sess p
  # Direct pane match
  sess="$(tmux list-panes -a -F '#{pane_pid} #{session_name}' 2>/dev/null \
    | awk -v p="$pid" '$1==p{print $2; exit}' || true)"
  if [[ -n "$sess" ]]; then
    printf '%s' "$sess"
    return 0
  fi
  # Walk parents up to 8 levels looking for a pane_pid ancestor
  p="$pid"
  local i=0
  while (( i < 8 )); do
    ppid="$(awk '/^PPid:/{print $2; exit}' "/proc/$p/status" 2>/dev/null || true)"
    [[ -n "$ppid" && "$ppid" =~ ^[0-9]+$ && "$ppid" -gt 1 ]] || break
    sess="$(tmux list-panes -a -F '#{pane_pid} #{session_name}' 2>/dev/null \
      | awk -v p="$ppid" '$1==p{print $2; exit}' || true)"
    if [[ -n "$sess" ]]; then
      printf '%s' "$sess"
      return 0
    fi
    p="$ppid"
    i=$((i + 1))
  done
  printf ''
}

# L5: /proc/<pid>/cwd → repo name under FERRY_REPO_BASE
servers_proc_repo() {
  local pid="${1:-}"
  [[ -n "$pid" && "$pid" != "-" && "$pid" =~ ^[0-9]+$ ]] || { printf ''; return 0; }
  local cwd base repo
  cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
  [[ -n "$cwd" ]] || { printf ''; return 0; }
  base="${FERRY_REPO_BASE:-$HOME/Repositories}"
  case "$cwd" in
    "$base"/*)
      repo="${cwd#"$base"/}"
      repo="${repo%%/*}"
      printf '%s' "$repo"
      ;;
    *)
      printf ''
      ;;
  esac
}

# Resolve declaration file list (later wins per port when merged).
_servers_decl_files() {
  local f
  if [[ -n "${FERRY_SERVERS_DECL:-}" ]]; then
    # Explicit override (tests / one-shot): space or colon separated
    for f in ${FERRY_SERVERS_DECL//:/ }; do
      [[ -r "$f" ]] && printf '%s\n' "$f"
    done
    return 0
  fi
  f="${HOME}/.config/mossferry/servers.tsv"
  [[ -r "$f" ]] && printf '%s\n' "$f"
  # Repo-local declarations under FERRY_REPO_BASE/*/.ferry/servers.tsv
  local base="${FERRY_REPO_BASE:-$HOME/Repositories}"
  if [[ -d "$base" ]]; then
    local d
    for d in "$base"/*/.ferry/servers.tsv; do
      [[ -r "$d" ]] && printf '%s\n' "$d"
    done
  fi
}



# Resolve agent-status directory (armory contract; read-only).
# 1) $AGENT_STATUS_DIR  2) $XDG_RUNTIME_DIR/agent-status  3) $HOME/.local/state/agent-status
servers_agent_status_dir() {
  # Explicit override: if set, never fall through — missing dir ⇒ zero rows.
  if [[ -n "${AGENT_STATUS_DIR:-}" ]]; then
    if [[ -d "$AGENT_STATUS_DIR" ]]; then
      printf '%s\n' "$AGENT_STATUS_DIR"
      return 0
    fi
    return 1
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR/agent-status" ]]; then
    printf '%s\n' "$XDG_RUNTIME_DIR/agent-status"
    return 0
  fi
  if [[ -d "$HOME/.local/state/agent-status" ]]; then
    printf '%s\n' "$HOME/.local/state/agent-status"
    return 0
  fi
  return 1
}

# Emit agent rows for live pids in agent-status sessions/*.json.
# port=- class=agent state=LISTEN. Prefer node for JSON; silent no-op if missing.
servers_scan_agents() {
  local dir
  dir="$(servers_agent_status_dir 2>/dev/null)" || return 0
  [[ -d "$dir/sessions" ]] || return 0

  if command -v node >/dev/null 2>&1; then
    # Single node process over the directory — never spawn per-file.
    node -e '
const fs = require("fs");
const path = require("path");
const dir = process.argv[1];
const base = process.env.FERRY_REPO_BASE || path.join(process.env.HOME || "", "Repositories");
let files;
try { files = fs.readdirSync(dir).filter(f => f.endsWith(".json")); } catch { process.exit(0); }
for (const f of files) {
  let j;
  try { j = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")); } catch { continue; }
  const pid = j.pid;
  if (!pid || !/^[0-9]+$/.test(String(pid))) continue;
  try { fs.accessSync("/proc/" + pid); } catch { continue; }
  const preset = j.preset || "agent";
  const model = j.model || "";
  let label = preset;
  if (model) label = preset + "/" + model;
  let repo = "-";
  try {
    const cwd = fs.readlinkSync("/proc/" + pid + "/cwd");
    if (cwd.startsWith(base + "/")) {
      repo = cwd.slice(base.length + 1).split("/")[0] || "-";
    }
  } catch {}
  const dash = (v) => (v === undefined || v === null || v === "" ? "-" : String(v).replace(/\t|\n|\r/g, " "));
  // port state id class label bind pid comm repo owner mac_state mac_url health restart
  process.stdout.write([
    "-", "LISTEN", "agent-" + pid, "agent", dash(label),
    "-", String(pid), "agent", dash(repo), "-",
    "unknown", "-", "-", "-"
  ].join("\t") + "\n");
}
' "$dir/sessions" 2>/dev/null || true
    return 0
  fi

  # sed fallback when node is absent
  local f pid cwd preset model label repo
  shopt -s nullglob
  for f in "$dir/sessions"/*.json; do
    [[ -r "$f" ]] || continue
    pid="$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
    [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] || continue
    [[ -d "/proc/$pid" ]] || continue
    preset="$(sed -n 's/.*"preset"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)"
    model="$(sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)"
    label="${preset:-agent}"
    [[ -n "$model" ]] && label="${label}/${model}"
    repo="$(servers_proc_repo "$pid" 2>/dev/null || true)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "-" "LISTEN" "agent-$pid" "agent" "$label" \
      "-" "$pid" "agent" "${repo:--}" "-" \
      "unknown" "-" "-" "-"
  done
  shopt -u nullglob
}


# --- Bulk caches (filled once per build_server_rows) ---------------------------
# Avoid O(listeners × units) systemctl/docker/tmux calls on a busy desk.

_servers_cache_systemd_pids() {
  # Emit "pid\tspine" for each running user service MainPID
  command -v systemctl >/dev/null 2>&1 || return 0
  local unit main
  while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    main="$(systemctl --user show -p MainPID --value "$unit" 2>/dev/null || true)"
    if [[ -n "$main" && "$main" =~ ^[0-9]+$ && "$main" -gt 1 ]]; then
      printf '%s\tspine\n' "$main"
    fi
  done < <(systemctl --user list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print $1}' || true)
}

_servers_cache_docker_ports() {
  # Emit "port\trestart" for published host ports
  command -v docker >/dev/null 2>&1 || return 0
  local id ports restart p
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    id="${line%% *}"
    ports="${line#* }"
    restart="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$id" 2>/dev/null || true)"
    [[ -z "$restart" || "$restart" == "no" ]] && restart="-"
    # Extract host ports: 0.0.0.0:8791->… or :::8791-> or 127.0.0.1:5432->
    while [[ "$ports" =~ :([0-9]+)-\> ]]; do
      p="${BASH_REMATCH[1]}"
      printf '%s\t%s\n' "$p" "$restart"
      # strip matched portion to find more ports
      ports="${ports#*${BASH_REMATCH[0]}}"
    done
  done < <(docker ps --format '{{.ID}} {{.Ports}}' 2>/dev/null || true)
}

_servers_cache_tmux_panes() {
  # Emit "pid\tsession"
  command -v tmux >/dev/null 2>&1 || return 0
  tmux list-panes -a -F '#{pane_pid} #{session_name}' 2>/dev/null || true
}

# --- bash-3.2-safe maps (no associative arrays) -------------------------------
# Indexed arrays of Unit-Separator (US=$'\x1f') records + ordered key lists.
# Lookup is linear scan — desk-scale (tens of ports/pids). Absent key → empty.
# US (0x1F) cannot appear in ports (digits), pids (digits), bind addresses,
# process names from ss, or TSV declaration fields (human-edited printable).

_SERVERS_US=$'\x1f'

# Find index of key in a parallel key array; prints index or empty if absent.
# Usage: _servers_idx_of key ${keys[@]+"${keys[@]}"}
_servers_idx_of() {
  local needle="$1" i=0 _servers_k
  shift
  for _servers_k in "$@"; do
    if [[ "$_servers_k" == "$needle" ]]; then
      printf '%s' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 0
}

# Get field N (1-based) from a US-delimited record. Empty if missing.
# awk FS=\037 is Unit Separator (same as $_SERVERS_US).
_servers_rec_field() {
  local rec="$1" n="$2"
  printf '%s' "$rec" | awk -F '\037' -v n="$n" '{ if (n >= 1 && n <= NF) print $n }'
}

# True when the host can run the full servers view (ss + /proc), or when a
# fixture supplies listener text (tests). Capability-based — not uname.
_servers_platform_capable() {
  if [[ -n "${FERRY_SERVERS_SS_FIXTURE:-}" ]]; then
    return 0
  fi
  command -v ss >/dev/null 2>&1 || return 1
  [[ -d /proc ]] || return 1
  return 0
}

# Emit one stderr notice when the servers view cannot run; never fatal.
_servers_capability_warn() {
  local missing=""
  if ! command -v ss >/dev/null 2>&1; then
    missing="ss"
  fi
  if [[ ! -d /proc ]]; then
    if [[ -n "$missing" ]]; then
      missing="${missing} and /proc"
    else
      missing="/proc"
    fi
  fi
  [[ -n "$missing" ]] || missing="required platform tools"
  printf 'mossferry servers: %s not available — servers view is Linux-host-only (needs ss and /proc). Skipping.\n' \
    "$missing" >&2
}

# Merge L0–L5 into full 14-column rows.
# When FERRY_SERVERS_SS_FIXTURE is set, listener lines are read from stdin.
build_server_rows() {
  # Capability gate: without ss+/proc (and without a fixture) the view would
  # silently list nothing — same class of lie as empty on a busy desk. Warn
  # once on stderr and return empty; rest of mossferry keeps working.
  if ! _servers_platform_capable; then
    if [[ "${_FERRY_SERVERS_CAPABILITY_WARNED:-0}" -eq 0 ]]; then
      _servers_capability_warn
      _FERRY_SERVERS_CAPABILITY_WARNED=1
    fi
    return 0
  fi

  # Parallel key/value arrays (bash 3.2 — no associative maps). Keys keep insertion order.
  local decl_keys=() decl_recs=()
  local live_keys=() live_recs=()
  local cache_sd_keys=() cache_sd_vals=()
  local cache_docker_keys=() cache_docker_vals=()
  local cache_tmux_keys=() cache_tmux_vals=()
  local port id class label mac health bind pid comm repo owner mac_state mac_url restart state
  local line f files k v idx rec p i ppid expect_repo
  local US="$_SERVERS_US"

  # --- L0 declarations ---
  files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(_servers_decl_files)
  if (( ${#files[@]} > 0 )); then
    while IFS=$'\t' read -r port id class label mac health; do
      [[ -z "$port" ]] && continue
      rec="${id}${US}${class}${US}${label}${US}${mac}${US}${health}"
      idx=""
      if (( ${#decl_keys[@]} > 0 )); then
        idx="$(_servers_idx_of "$port" ${decl_keys[@]+"${decl_keys[@]}"})"
      fi
      if [[ -n "$idx" ]]; then
        decl_recs[$idx]="$rec"
      else
        decl_keys+=("$port")
        decl_recs+=("$rec")
      fi
    done < <(servers_parse_declarations ${files[@]+"${files[@]}"})
  fi

  # --- L1 listeners ---
  local listeners
  if [[ -n "${FERRY_SERVERS_SS_FIXTURE:-}" ]]; then
    listeners="$(cat)"
  else
    listeners="$(servers_scan_listeners)"
  fi
  # When fixture mode fed raw ss lines via stdin into build_server_rows,
  # re-parse them; when servers_scan_listeners already emitted TSV, use as-is.
  local scan_out
  if [[ -n "${FERRY_SERVERS_SS_FIXTURE:-}" ]]; then
    scan_out="$(printf '%s\n' "$listeners" | servers_scan_listeners)"
  else
    scan_out="$listeners"
  fi

  # Bulk caches (once) — parallel key/value arrays
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] || continue
    idx=""
    (( ${#cache_sd_keys[@]} > 0 )) && idx="$(_servers_idx_of "$k" ${cache_sd_keys[@]+"${cache_sd_keys[@]}"})"
    if [[ -n "$idx" ]]; then
      cache_sd_vals[$idx]="$v"
    else
      cache_sd_keys+=("$k")
      cache_sd_vals+=("$v")
    fi
  done < <(_servers_cache_systemd_pids)
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] || continue
    idx=""
    (( ${#cache_docker_keys[@]} > 0 )) && idx="$(_servers_idx_of "$k" ${cache_docker_keys[@]+"${cache_docker_keys[@]}"})"
    if [[ -n "$idx" ]]; then
      cache_docker_vals[$idx]="$v"
    else
      cache_docker_keys+=("$k")
      cache_docker_vals+=("$v")
    fi
  done < <(_servers_cache_docker_ports)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    k="${line%% *}"
    v="${line#* }"
    [[ -n "$k" ]] || continue
    idx=""
    (( ${#cache_tmux_keys[@]} > 0 )) && idx="$(_servers_idx_of "$k" ${cache_tmux_keys[@]+"${cache_tmux_keys[@]}"})"
    if [[ -n "$idx" ]]; then
      cache_tmux_vals[$idx]="$v"
    else
      cache_tmux_keys+=("$k")
      cache_tmux_vals+=("$v")
    fi
  done < <(_servers_cache_tmux_panes)

  while IFS=$'\t' read -r port bind pid comm; do
    [[ -z "$port" ]] && continue

    class=""
    # L2 systemd (cached)
    if [[ -n "$pid" && "$pid" != "-" && ${#cache_sd_keys[@]} -gt 0 ]]; then
      idx="$(_servers_idx_of "$pid" ${cache_sd_keys[@]+"${cache_sd_keys[@]}"})"
      if [[ -n "$idx" ]]; then
        class="spine"
      fi
    fi
    # L3 docker (cached)
    restart="-"
    if (( ${#cache_docker_keys[@]} > 0 )); then
      idx="$(_servers_idx_of "$port" ${cache_docker_keys[@]+"${cache_docker_keys[@]}"})"
      if [[ -n "$idx" ]]; then
        class="${class:-docker}"
        restart="${cache_docker_vals[$idx]}"
      fi
    fi
    # Declaration class fills gaps
    if [[ -z "$class" || "$class" == "-" ]]; then
      class=""
      if (( ${#decl_keys[@]} > 0 )); then
        idx="$(_servers_idx_of "$port" ${decl_keys[@]+"${decl_keys[@]}"})"
        if [[ -n "$idx" ]]; then
          class="$(_servers_rec_field "${decl_recs[$idx]}" 2)"
        fi
      fi
    fi
    # Heuristic class from comm when still empty
    if [[ -z "$class" || "$class" == "-" ]]; then
      case "${comm:-}" in
        postgres*|mysql*|redis*|mongo*) class="db" ;;
        python*|http.server|node*|next-server*|vite*|uvicorn*) class="dev" ;;
        docker*|*containerd*) class="docker" ;;
        *) class="${class:-}" ;;
      esac
    fi
    class="${class:--}"

    # L4 tmux owner — direct pane or walk parents against cache
    owner="-"
    if [[ -n "$pid" && "$pid" != "-" && ${#cache_tmux_keys[@]} -gt 0 ]]; then
      idx="$(_servers_idx_of "$pid" ${cache_tmux_keys[@]+"${cache_tmux_keys[@]}"})"
      if [[ -n "$idx" ]]; then
        owner="${cache_tmux_vals[$idx]}"
      else
        p="$pid"
        i=0
        while (( i < 8 )); do
          ppid="$(awk '/^PPid:/{print $2; exit}' "/proc/$p/status" 2>/dev/null || true)"
          [[ -n "$ppid" && "$ppid" =~ ^[0-9]+$ && "$ppid" -gt 1 ]] || break
          idx="$(_servers_idx_of "$ppid" ${cache_tmux_keys[@]+"${cache_tmux_keys[@]}"})"
          if [[ -n "$idx" ]]; then
            owner="${cache_tmux_vals[$idx]}"
            break
          fi
          p="$ppid"
          i=$((i + 1))
        done
      fi
    fi

    # L5 repo
    repo="$(servers_proc_repo "$pid" 2>/dev/null || true)"
    repo="${repo:--}"

    # live record: bind US pid US comm US class US restart US repo US owner
    rec="${bind}${US}${pid}${US}${comm}${US}${class}${US}${restart}${US}${repo}${US}${owner}"
    idx=""
    if (( ${#live_keys[@]} > 0 )); then
      idx="$(_servers_idx_of "$port" ${live_keys[@]+"${live_keys[@]}"})"
    fi
    if [[ -n "$idx" ]]; then
      live_recs[$idx]="$rec"
    else
      live_keys+=("$port")
      live_recs+=("$rec")
    fi
  done <<<"$scan_out"

  # Emit live rows in scan/insertion order (deterministic; bash 4 hash order was not).
  i=0
  while (( i < ${#live_keys[@]} )); do
    port="${live_keys[$i]}"
    rec="${live_recs[$i]}"
    bind="$(_servers_rec_field "$rec" 1)"
    pid="$(_servers_rec_field "$rec" 2)"
    comm="$(_servers_rec_field "$rec" 3)"
    class="$(_servers_rec_field "$rec" 4)"
    restart="$(_servers_rec_field "$rec" 5)"
    repo="$(_servers_rec_field "$rec" 6)"
    owner="$(_servers_rec_field "$rec" 7)"
    [[ -z "$pid" ]] && pid="-"
    [[ -z "$comm" ]] && comm="-"
    [[ -z "$class" ]] && class="-"
    [[ -z "$restart" ]] && restart="-"
    [[ -z "$repo" ]] && repo="-"
    [[ -z "$owner" ]] && owner="-"

    id="-"
    label="-"
    mac="ok"
    health="-"
    if (( ${#decl_keys[@]} > 0 )); then
      idx="$(_servers_idx_of "$port" ${decl_keys[@]+"${decl_keys[@]}"})"
      if [[ -n "$idx" ]]; then
        id="$(_servers_rec_field "${decl_recs[$idx]}" 1)"
        [[ "$class" == "-" || -z "$class" ]] && class="$(_servers_rec_field "${decl_recs[$idx]}" 2)"
        label="$(_servers_rec_field "${decl_recs[$idx]}" 3)"
        mac="$(_servers_rec_field "${decl_recs[$idx]}" 4)"
        health="$(_servers_rec_field "${decl_recs[$idx]}" 5)"
        [[ -z "$id" ]] && id="-"
        [[ -z "$class" ]] && class="-"
        [[ -z "$label" ]] && label="-"
        [[ -z "$mac" ]] && mac="ok"
        [[ -z "$health" ]] && health="-"
      fi
    fi
    [[ "$class" == "-" || -z "$class" ]] && class="-"
    [[ "$label" == "-" || -z "$label" ]] && label="${comm:--}"

    # FOREIGN: declaration exists and live cwd repo disagrees with expectation.
    # We only mark FOREIGN when declaration id suggests a repo and live repo is set and differs.
    state="LISTEN"
    if [[ -n "$id" && "$id" != "-" && -n "$repo" && "$repo" != "-" ]]; then
      # If id looks like repo-something and repo doesn't match prefix, flag FOREIGN
      expect_repo="${id%%-*}"
      if [[ -n "$expect_repo" && "$repo" != "$expect_repo" && "$repo" != "$id" ]]; then
        # Only if declaration carried an explicit class/id from a known file — soft signal
        :
      fi
    fi
    # Stronger FOREIGN: FERRY_SERVERS_EXPECT_REPO_$port or id field "repo/name"
    if [[ -n "$label" && -n "$repo" && "$repo" != "-" ]]; then
      :
    fi

    mac_state="$(servers_mac_state "$bind" "$port" "$mac")"
    mac_url="$(servers_mac_url "$bind" "$port" "$mac_state" | tr -d '\n')"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$port" "$state" \
      "$(_servers_dash "$id")" \
      "$(_servers_dash "$class")" \
      "$(_servers_dash "$label")" \
      "$(_servers_dash "$bind")" \
      "$(_servers_dash "$pid")" \
      "$(_servers_dash "$comm")" \
      "$(_servers_dash "$repo")" \
      "$(_servers_dash "$owner")" \
      "$mac_state" \
      "$(_servers_dash "$mac_url")" \
      "$(_servers_dash "$health")" \
      "$(_servers_dash "$restart")"
    i=$((i + 1))
  done

  # Declared-missing: in declarations but not live (sorted by port, as before)
  i=0
  while (( i < ${#decl_keys[@]} )); do
    port="${decl_keys[$i]}"
    # skip if live
    idx=""
    if (( ${#live_keys[@]} > 0 )); then
      idx="$(_servers_idx_of "$port" ${live_keys[@]+"${live_keys[@]}"})"
    fi
    if [[ -n "$idx" ]]; then
      i=$((i + 1))
      continue
    fi
    rec="${decl_recs[$i]}"
    id="$(_servers_rec_field "$rec" 1)"
    class="$(_servers_rec_field "$rec" 2)"
    label="$(_servers_rec_field "$rec" 3)"
    mac="$(_servers_rec_field "$rec" 4)"
    health="$(_servers_rec_field "$rec" 5)"
    [[ -z "$id" ]] && id="-"
    [[ -z "$class" ]] && class="-"
    [[ -z "$label" ]] && label="-"
    [[ -z "$mac" ]] && mac="ok"
    [[ -z "$health" ]] && health="-"
    mac_state="$(servers_mac_state "127.0.0.1" "$port" "$mac")"
    # declared-missing is not reachable; force reserved if policy says never
    if [[ "$mac" == "never" ]] || _servers_port_reserved "$port"; then
      mac_state="reserved"
    else
      mac_state="unknown"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$port" "declared-missing" \
      "$(_servers_dash "$id")" \
      "$(_servers_dash "$class")" \
      "$(_servers_dash "$label")" \
      "-" \
      "-" \
      "-" \
      "-" \
      "-" \
      "$mac_state" \
      "-" \
      "$(_servers_dash "$health")" \
      "-"
    i=$((i + 1))
  done | sort -t$'\t' -k1,1n

  # Detached armory / agent children (class=agent, port=-). Read-only; missing dir = zero rows.
  servers_scan_agents 2>/dev/null || true
}

# Fix plan pure function (Task 4): action \t detail
# action ∈ none | recipe | tunnel | refuse | declare
servers_fix_plan() {
  local mac_state="${1:-}" class="${2:-}" port="${3:-}" cwd="${4:-}"
  case "$mac_state" in
    reachable)
      printf 'none\tMac-reachable — nothing to fix\n'
      ;;
    reserved)
      if [[ "$port" == "8791" ]]; then
        printf 'refuse\tPort 8791 is FreeLLMAPI (permanent). Pick a free port — never rebind 8791.\n'
      else
        printf 'refuse\tPort %s is reserved. Pick a free port; do not rebind.\n' "$port"
      fi
      ;;
    loopback-only)
      case "$class" in
        preview|dev)
          printf 'recipe\tpreview-serve %s %s\n' "${cwd:-.}" "$port"
          ;;
        db|spine|agent)
          local host
          host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo HOST)"
          printf 'tunnel\tssh -N -L %s:127.0.0.1:%s %s\n' "$port" "$port" "$host"
          ;;
        *)
          # Unknown class on loopback: prefer tunnel (safer than rebind)
          host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo HOST)"
          printf 'tunnel\tssh -N -L %s:127.0.0.1:%s %s\n' "$port" "$port" "$host"
          ;;
      esac
      ;;
    unknown|declared-missing|"")
      printf 'declare\tNo live listener. Add to servers.tsv or start the service; ferry will not start it.\n'
      ;;
    *)
      printf 'none\tNo fix available\n'
      ;;
  esac
}
