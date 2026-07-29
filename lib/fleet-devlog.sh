# fleet-devlog v1 — bash emitter (hand-rolled JSON; no jq).
# Fail-open always. Zero network. Allow-list fields only.
# Contract: work-kb/contracts/fleet-devlog-v1.md
#
# Public surface:
#   devlog_emit <cmd> <exit> <ms> [key=value…]
# Values are numbers or enum tokens only. Escape \ and " in every string field.
#
# Enable: env FLEET_DEVLOG / --no-devlog via DEVLOG_ARGV / machine config.
# Root:   ${XDG_STATE_HOME:-$HOME/.local/state}/fleet-devlog/
# Caller may set DEVLOG_ARGV as a bash array (for --no-devlog detection).

# shellcheck shell=bash

_DEVLOG_MAX=$((8 * 1024 * 1024))

_devlog_root() {
  printf '%s\n' "${XDG_STATE_HOME:-${HOME}/.local/state}/fleet-devlog"
}

_devlog_json_escape() {
  # Escape \ and " for JSON string values. Input via $1.
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  s=${s//$'\r'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}

_devlog_is_num() {
  [[ ${1-} =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

_devlog_machine_enabled() {
  # return 0 = enabled true, 1 = enabled false, 2 = absent/unreadable/no key
  local f conf
  f="${XDG_CONFIG_HOME:-${HOME}/.config}/fleet-devlog/config.json"
  [[ -r "$f" ]] || return 2
  conf=$(cat "$f" 2>/dev/null) || return 2
  if printf '%s' "$conf" | grep -qE '"enabled"[[:space:]]*:[[:space:]]*true\b'; then
    return 0
  fi
  if printf '%s' "$conf" | grep -qE '"enabled"[[:space:]]*:[[:space:]]*false\b'; then
    return 1
  fi
  return 2
}

devlog_enabled() {
  # First match wins. Never consults repo config.
  local v a
  v=$(printf '%s' "${FLEET_DEVLOG-}" | tr '[:upper:]' '[:lower:]')
  case "$v" in
    0|false|off|no) return 1 ;;
  esac
  if declare -p DEVLOG_ARGV &>/dev/null; then
    # shellcheck disable=SC2128
    for a in ${DEVLOG_ARGV[@]+"${DEVLOG_ARGV[@]}"}; do
      [[ "$a" == "--no-devlog" ]] && return 1
    done
  fi
  case "$v" in
    1|true|on|yes) return 0 ;;
  esac
  _devlog_machine_enabled
  case $? in
    0) return 0 ;;
    1) return 1 ;;
    *) return 1 ;;
  esac
}

_devlog_ensure_dir() {
  # Non-recursive climb (avoid hanging on /proc). Fail-open → return 1.
  local dir=$1 parent p
  local -a missing=()
  [[ -d "$dir" ]] && return 0
  p=$dir
  while [[ ! -d "$p" ]]; do
    missing=("$p" "${missing[@]+"${missing[@]}"}")
    parent=$(dirname "$p")
    [[ "$parent" == "$p" ]] && return 1
    p=$parent
  done
  [[ -w "$p" ]] || return 1
  local m
  for m in "${missing[@]+"${missing[@]}"}"; do
    mkdir "$m" 2>/dev/null || return 1
  done
  return 0
}

_devlog_mint_id() {
  local id=""
  if command -v openssl >/dev/null 2>&1; then
    id=$(openssl rand -hex 16 2>/dev/null || true)
  fi
  if [[ -z "$id" || ${#id} -lt 16 ]]; then
    if [[ -r /dev/urandom ]]; then
      id=$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n' || true)
    fi
  fi
  if [[ -n "$id" && "$id" =~ ^[0-9a-fA-F]{16,}$ ]]; then
    printf '%s' "$id" | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  return 1
}

devlog_install_id() {
  # Read existing shared install-id; mint only if absent. 'unknown' on failure.
  local root p id again
  root=$(_devlog_root)
  p="${root}/install-id"
  if [[ -r "$p" ]]; then
    id=$(tr -d '[:space:]' <"$p" 2>/dev/null || true)
    if [[ "$id" =~ ^[0-9a-fA-F]{16,}$ ]]; then
      printf '%s\n' "$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
      return 0
    fi
  fi
  _devlog_ensure_dir "$root" || { printf 'unknown\n'; return 0; }
  id=$(_devlog_mint_id) || { printf 'unknown\n'; return 0; }
  # Exclusive create (noclobber). If raced, re-read the winner.
  if (set -C; printf '%s\n' "$id" >"$p") 2>/dev/null; then
    printf '%s\n' "$id"
    return 0
  fi
  if [[ -r "$p" ]]; then
    again=$(tr -d '[:space:]' <"$p" 2>/dev/null || true)
    if [[ "$again" =~ ^[0-9a-fA-F]{16,}$ ]]; then
      printf '%s\n' "$(printf '%s' "$again" | tr '[:upper:]' '[:lower:]')"
      return 0
    fi
  fi
  printf 'unknown\n'
}

_devlog_ts() {
  local t2
  t2=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null) || t2=""
  if [[ -n "$t2" && "$t2" != *%3N* ]]; then
    printf '%s\n' "$t2"
    return 0
  fi
  date -u +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || printf '%s\n' "1970-01-01T00:00:00.000Z"
}

# First 8 hex of sha256 over the UTF-8 path string. Prefer sha256sum (host
# default); openssl dgst as soft fallback. Fail → return 1 (caller omits field).
_devlog_sha256_8() {
  local s=${1-} out
  if command -v sha256sum >/dev/null 2>&1; then
    out=$(printf '%s' "$s" | sha256sum 2>/dev/null) || return 1
    out=${out%% *}
  elif command -v openssl >/dev/null 2>&1; then
    out=$(printf '%s' "$s" | openssl dgst -sha256 2>/dev/null) || return 1
    out=${out##* }
  else
    return 1
  fi
  out=$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')
  [[ "$out" =~ ^[0-9a-f]{8,} ]] || return 1
  printf '%s' "${out:0:8}"
}

# <basename>-<sha256-8> of the MAIN repo root (worktrees fold via
# --git-common-dir). Matches agentic-sage/lib/repo-id.mjs byte-for-byte.
# Empty stdout when not in a git repo or on any failure (omit field).
_devlog_resolve_repo_id() {
  local cwd=${1:-${PWD}} common root base hash
  command -v git >/dev/null 2>&1 || return 0
  common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [[ -n "$common" ]] || return 0
  root=$(dirname -- "$common")
  if command -v realpath >/dev/null 2>&1; then
    root=$(realpath -- "$root" 2>/dev/null) || return 0
  else
    root=$(cd -- "$root" 2>/dev/null && pwd -P) || return 0
  fi
  [[ -n "$root" ]] || return 0
  base=$(basename -- "$root")
  [[ -n "$base" && "$base" != / && "$base" != . ]] || return 0
  hash=$(_devlog_sha256_8 "$root") || return 0
  printf '%s\n' "${base}-${hash}"
}

_devlog_rotate_if_needed() {
  local file=$1 root size
  [[ -f "$file" ]] || return 0
  size=$(wc -c <"$file" 2>/dev/null | tr -d '[:space:]' || echo 0)
  [[ "${size:-0}" =~ ^[0-9]+$ ]] || return 0
  if (( size > _DEVLOG_MAX )); then
    root=$(dirname "$file")
    mv -f "$file" "${root}/events.jsonl.1" 2>/dev/null || true
  fi
}

# devlog_emit <cmd> <exit> <ms> [key=value…]
# Optional keys (allow-list): tool_version, result_class, repo_id, corr,
#   counts.<name>=<number>, argv_shape=<comma-flags> (flags only, no values)
# When repo_id is not passed, auto-resolve via _devlog_resolve_repo_id (omit if none).
devlog_emit() {
  # Fail-open wrapper: swallow everything, always return 0 from this function.
  _devlog_emit_inner "$@" 2>/dev/null || true
  return 0
}

_devlog_emit_inner() {
  local cmd=${1-} exit_code=${2-} ms=${3-}
  if [[ $# -ge 3 ]]; then
    shift 3
  else
    set --
  fi

  devlog_enabled || return 0

  local tool=mossferry
  local root file install_id ts
  local tool_version="" result_class="" repo_id="" corr=""
  local counts_json="" argv_json=""
  local kv k v ck first part flag
  local repo_id_explicit=0

  for kv in "$@"; do
    [[ "$kv" == *=* ]] || continue
    k=${kv%%=*}
    v=${kv#*=}
    case "$k" in
      tool_version) tool_version=$v ;;
      result_class)
        case "$v" in
          ok|failed|timeout|auth|ratelimit|killed|missing_output) result_class=$v ;;
        esac
        ;;
      repo_id)
        repo_id=$v
        repo_id_explicit=1
        ;;
      corr) corr=$v ;;
      argv_shape)
        first=1
        argv_json="["
        local IFS=','
        # shellcheck disable=SC2086
        for part in $v; do
          [[ "$part" == --* ]] || continue
          if [[ $first -eq 1 ]]; then first=0; else argv_json+=","; fi
          argv_json+="\"$(_devlog_json_escape "$part")\""
        done
        argv_json+="]"
        ;;
      counts.*)
        ck=${k#counts.}
        if [[ "$ck" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && _devlog_is_num "$v"; then
          if [[ -z "$counts_json" ]]; then
            counts_json="\"$(_devlog_json_escape "$ck")\":${v}"
          else
            counts_json+=",\"$(_devlog_json_escape "$ck")\":${v}"
          fi
        fi
        ;;
    esac
  done

  # cmd is subcommand name only
  cmd=${cmd%% *}
  [[ -n "$cmd" ]] || return 0
  [[ "$cmd" =~ ^[A-Za-z0-9_.+-]+$ ]] || return 0

  if ! _devlog_is_num "$exit_code"; then exit_code=0; fi
  exit_code=${exit_code%%.*}
  if ! _devlog_is_num "$ms"; then ms=0; fi
  ms=${ms%%.*}

  # Auto-resolve unless the caller set repo_id= (including empty → omit).
  if [[ $repo_id_explicit -eq 0 ]]; then
    repo_id=$(_devlog_resolve_repo_id 2>/dev/null || true)
  fi

  root=$(_devlog_root)
  _devlog_ensure_dir "$root" || return 0
  install_id=$(devlog_install_id)
  ts=$(_devlog_ts)
  file="${root}/events.jsonl"
  _devlog_rotate_if_needed "$file"

  local json
  json="{"
  json+="\"v\":1"
  json+=",\"ts\":\"$(_devlog_json_escape "$ts")\""
  json+=",\"install_id\":\"$(_devlog_json_escape "$install_id")\""
  json+=",\"tool\":\"$(_devlog_json_escape "$tool")\""
  [[ -n "$tool_version" ]] && json+=",\"tool_version\":\"$(_devlog_json_escape "$tool_version")\""
  json+=",\"cmd\":\"$(_devlog_json_escape "$cmd")\""
  json+=",\"exit\":${exit_code}"
  json+=",\"ms\":${ms}"
  [[ -n "$repo_id" ]] && json+=",\"repo_id\":\"$(_devlog_json_escape "$repo_id")\""
  [[ -n "$corr" ]] && json+=",\"corr\":\"$(_devlog_json_escape "$corr")\""
  [[ -n "$result_class" ]] && json+=",\"result_class\":\"$(_devlog_json_escape "$result_class")\""
  [[ -n "$argv_json" && "$argv_json" != "[]" ]] && json+=",\"argv_shape\":${argv_json}"
  [[ -n "$counts_json" ]] && json+=",\"counts\":{${counts_json}}"
  json+="}"

  printf '%s\n' "$json" >>"$file" 2>/dev/null || true
}
