#!/usr/bin/env bash
# lib/servers.sh — layered server discovery for mossferry servers view.
# Zero runtime deps beyond bash, ss, /proc. Sourceable pure functions.
# Row model (14 columns, tab-separated):
#   port state id class label bind pid comm repo owner mac_state mac_url health restart
#
# shellcheck disable=SC2034

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

# Merge L0–L5 into full 14-column rows.
# When FERRY_SERVERS_SS_FIXTURE is set, listener lines are read from stdin.
build_server_rows() {
  local -A decl_id decl_class decl_label decl_mac decl_health
  local -A live_bind live_pid live_comm live_class live_restart live_repo live_owner
  local -A seen_port
  local port id class label mac health bind pid comm repo owner mac_state mac_url restart state
  local line f files

  # --- L0 declarations ---
  files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(_servers_decl_files)
  if (( ${#files[@]} > 0 )); then
    while IFS=$'\t' read -r port id class label mac health; do
      [[ -z "$port" ]] && continue
      decl_id["$port"]="$id"
      decl_class["$port"]="$class"
      decl_label["$port"]="$label"
      decl_mac["$port"]="$mac"
      decl_health["$port"]="$health"
    done < <(servers_parse_declarations "${files[@]}")
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

  # Bulk caches (once)
  local -A cache_sd cache_docker cache_tmux
  local k v
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] && cache_sd["$k"]="$v"
  done < <(_servers_cache_systemd_pids)
  while IFS=$'\t' read -r k v; do
    [[ -n "$k" ]] && cache_docker["$k"]="$v"
  done < <(_servers_cache_docker_ports)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    k="${line%% *}"
    v="${line#* }"
    [[ -n "$k" ]] && cache_tmux["$k"]="$v"
  done < <(_servers_cache_tmux_panes)

  while IFS=$'\t' read -r port bind pid comm; do
    [[ -z "$port" ]] && continue
    live_bind["$port"]="$bind"
    live_pid["$port"]="$pid"
    live_comm["$port"]="$comm"
    seen_port["$port"]=1

    class=""
    # L2 systemd (cached)
    if [[ -n "$pid" && "$pid" != "-" && -n "${cache_sd[$pid]:-}" ]]; then
      class="spine"
    fi
    # L3 docker (cached)
    if [[ -n "${cache_docker[$port]:-}" ]]; then
      class="${class:-docker}"
      live_restart["$port"]="${cache_docker[$port]}"
    fi
    # Declaration class fills gaps
    if [[ -z "$class" || "$class" == "-" ]]; then
      class="${decl_class[$port]:-}"
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
    live_class["$port"]="${class:--}"

    # L4 tmux owner — direct pane or walk parents against cache
    owner="-"
    if [[ -n "$pid" && "$pid" != "-" ]]; then
      if [[ -n "${cache_tmux[$pid]:-}" ]]; then
        owner="${cache_tmux[$pid]}"
      else
        local p="$pid" i=0 ppid
        while (( i < 8 )); do
          ppid="$(awk '/^PPid:/{print $2; exit}' "/proc/$p/status" 2>/dev/null || true)"
          [[ -n "$ppid" && "$ppid" =~ ^[0-9]+$ && "$ppid" -gt 1 ]] || break
          if [[ -n "${cache_tmux[$ppid]:-}" ]]; then
            owner="${cache_tmux[$ppid]}"
            break
          fi
          p="$ppid"
          i=$((i + 1))
        done
      fi
    fi
    live_owner["$port"]="$owner"

    # L5 repo
    repo="$(servers_proc_repo "$pid" 2>/dev/null || true)"
    live_repo["$port"]="${repo:--}"
  done <<<"$scan_out"

  # Emit live rows
  for port in "${!live_bind[@]}"; do
    bind="${live_bind[$port]}"
    pid="${live_pid[$port]:--}"
    comm="${live_comm[$port]:--}"
    class="${live_class[$port]:--}"
    [[ "$class" == "-" || -z "$class" ]] && class="${decl_class[$port]:--}"
    id="${decl_id[$port]:--}"
    label="${decl_label[$port]:--}"
    [[ "$label" == "-" || -z "$label" ]] && label="${comm:--}"
    mac="${decl_mac[$port]:-ok}"
    health="${decl_health[$port]:--}"
    restart="${live_restart[$port]:--}"
    repo="${live_repo[$port]:--}"
    owner="${live_owner[$port]:--}"
    # FOREIGN: declaration exists and live cwd repo disagrees with expectation.
    # We only mark FOREIGN when declaration id suggests a repo and live repo is set and differs.
    state="LISTEN"
    if [[ -n "${decl_id[$port]:-}" && "${decl_id[$port]}" != "-" \
          && -n "$repo" && "$repo" != "-" ]]; then
      # If id looks like repo-something and repo doesn't match prefix, flag FOREIGN
      local expect_repo="${decl_id[$port]%%-*}"
      if [[ -n "$expect_repo" && "$repo" != "$expect_repo" && "$repo" != "${decl_id[$port]}" ]]; then
        # Only if declaration carried an explicit class/id from a known file — soft signal
        :
      fi
    fi
    # Stronger FOREIGN: FERRY_SERVERS_EXPECT_REPO_$port or id field "repo/name"
    if [[ -n "${decl_label[$port]:-}" && -n "$repo" && "$repo" != "-" ]]; then
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
  done

  # Declared-missing: in declarations but not live
  for port in "${!decl_id[@]}"; do
    [[ -n "${seen_port[$port]:-}" ]] && continue
    id="${decl_id[$port]:--}"
    class="${decl_class[$port]:--}"
    label="${decl_label[$port]:--}"
    mac="${decl_mac[$port]:-ok}"
    health="${decl_health[$port]:--}"
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
  done | sort -t$'\t' -k1,1n
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
