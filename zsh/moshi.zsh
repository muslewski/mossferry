# mosh wrapper: `-r <repo>` jumps straight into ~/Repositories/<repo> in its own tmux session
mosh() {
  local repo="" args=()
  while (( $# )); do
    case "$1" in
      -r) repo="$2"; shift 2 ;;
      *)  args+=("$1"); shift ;;
    esac
  done
  if [[ -n "$repo" ]]; then
    command mosh "${args[@]}" -- /home/kento/.local/bin/repo-session "$repo"
  else
    command mosh "${args[@]}"
  fi
}

# moshi <host> [<repo>] [flags]  — open a repo's tmux session over mosh on <host>.
# `moshi --help` (or -h) prints usage + examples locally; all flags forward to
# repo-session on the remote (see the help text for the full list).
moshi() {
  if [[ $# -eq 0 || "$1" == -h || "$1" == --help ]]; then moshi_help; return; fi
  local host="$1"; shift
  # --help anywhere → print usage locally instead of opening a connection.
  # --list/-l just prints and exits; mosh's full-screen takeover discards that
  # output, so route listing through ssh. Everything else stays interactive on mosh.
  for a in "$@"; do
    case "$a" in
      -h|--help) moshi_help; return ;;
      --list|-l) command ssh "$host" /home/kento/.local/bin/repo-session "$@"; return ;;
    esac
  done
  command mosh "$host" -- /home/kento/.local/bin/repo-session "$@"
}

# Usage for `moshi` — documents the repo-session flags it forwards. Printed
# locally (no connection) by `moshi --help`.
moshi_help() {
  cat <<'EOF'
moshi <host> [<repo>] [flags]   open a repo's tmux session over mosh on <host>

Flags (forwarded to repo-session on the remote):
  (none)             attach the repo's primary session, creating it if missing
  --new              force a fresh session  (repo, repo-2, repo-3, ...)
  --claude, -c       run `claude` in newly-created sessions  (default: neofetch)
  --list, -l         list sessions and exit  (with <repo>: just that repo;
                     without <repo>: every tmux session on the host)
  --resume [N|name]  no arg -> tmux session-tree picker; N -> the Nth session;
                     name -> attach that exact session (e.g. --resume syndcast-2)
  --resume-closed    reattach one EXISTING session per caller, distinct (atomic).
                     Fired across a ghostty-grid each pane gets a different one;
                     panes past the session count stay BLANK.
  --resume-or-new    like --resume-closed, but fill leftover panes with fresh
                     sessions — so an N-pane grid always ends up full.
  -- cmd...          custom startup command for newly-created sessions

Grid workflows (with ghostty-grid):
  ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-or-new --claude
        everyday driver: 8 panes, reattach existing syndcast sessions, fill the
        rest with new ones running claude
  ghostty-grid -8 -- moshi manjaro-remote syndcast --resume-closed
        reattach existing sessions only; leftover panes stay blank

Single session:
  moshi manjaro-remote syndcast               attach/create the primary session
  moshi manjaro-remote syndcast --new -c      fresh session running claude
  moshi manjaro-remote syndcast --list        list syndcast's sessions
  moshi manjaro-remote --resume               pick any session from the tmux tree
EOF
}
