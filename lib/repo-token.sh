# Shared repo-token shape gate for mossferry client + repo-session host.
# Sourced by both binaries; do not execute directly.
# Rejects path-shaped tokens before they can be joined with FERRY_REPO_BASE
# or sent over the wire. Charset: A–Z a–z 0–9 . _ - only.

# Return 0 when $1 is a safe basename token; 1 otherwise.
_ferry_repo_token_ok() {
  local r=${1-}
  [[ -n "$r" ]] || return 1
  # No slashes, no absolute paths, no .. traversal fragments.
  case "$r" in
    /*|*/*|*\\*|*..*) return 1 ;;
  esac
  [[ "$r" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  return 0
}

# Print the stable invalid-name line (byte-compatible with host validate_repo)
# and return 1. Callers: if ! _ferry_repo_token_reject "$repo"; then return 1; fi
# or simply: _ferry_repo_token_reject "$repo" && return 1 is wrong — use:
#   _ferry_repo_token_ok "$r" || { _ferry_repo_token_reject_msg "$r"; return 1; }
_ferry_repo_token_reject_msg() {
  local r=${1-}
  # Strip single quotes so the message cannot break out of its quoting.
  printf "repo-session: invalid repo name '%s'\n" "${r//\'/}" >&2
}
