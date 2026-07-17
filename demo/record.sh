#!/usr/bin/env bash
# Regenerate every mossferry README demo GIF from staged fixtures.
# Dev-only. Never touches the user's live tmux server.
set -euo pipefail
cd "$(dirname "$0")"

# Vendor path (pinned copy) — do not require ~/.local/lib install.
GREEN_DEMO="${GREEN_DEMO:-$PWD/green-demo.sh}"
[ -r "$GREEN_DEMO" ] || {
  echo "green-demo.sh not found at $GREEN_DEMO — re-vendor from green-ui-kit" >&2
  exit 1
}
# shellcheck source=green-demo.sh
. "$GREEN_DEMO"

# Repo root (parent of demo/) for PATH + VERSION wiring.
FERRY_DEMO_ROOT="$(cd .. && pwd)"
export FERRY_DEMO_ROOT

demo_sandbox "$PWD" # HOME + XDG + fixtures overlay + gen.sh

demo_tmux start
trap 'demo_tmux stop' EXIT

# --- Stage picker targets on the isolated greenui-demo server only ----------
# Create atlas / beacon / home first (killing the last session kills the
# server), then drop every other session on this socket (placeholder "demo",
# and any leftovers from parallel fleet children that share -L greenui-demo).
# Clean prompts so pane previews never leak the real hostname.
_stage_sessions() {
  local name s
  for name in atlas beacon home; do
    if tmux -L greenui-demo -f /dev/null has-session -t "=$name" 2>/dev/null; then
      tmux -L greenui-demo -f /dev/null kill-session -t "=$name" 2>/dev/null || true
    fi
    # Detached session running a quiet shell with a fixed prompt (privacy).
    tmux -L greenui-demo -f /dev/null new-session -d -s "$name" -c "$HOME" \
      -- env PS1="${name}> " PROMPT_COMMAND= bash --noprofile --norc
    # Paint a short status line so previews look inhabited.
    tmux -L greenui-demo -f /dev/null send-keys -t "$name" \
      "printf '%s · ready\\n' '${name}'" Enter
    # Rename window for a nicer picker label.
    tmux -L greenui-demo -f /dev/null rename-window -t "$name" main
  done
  # Drop foreign sessions; keep only atlas/beacon/home.
  while IFS= read -r s; do
    case "$s" in
      atlas|beacon|home) continue ;;
      "") continue ;;
      *)
        tmux -L greenui-demo -f /dev/null kill-session -t "=$s" 2>/dev/null || true
        ;;
    esac
  done < <(tmux -L greenui-demo -f /dev/null list-sessions -F '#{session_name}' 2>/dev/null || true)
}
_stage_sessions

# Demo PATH: shims first (ssh/mosh/ferry), then real tools (fzf, etc.).
export PATH="$PWD/fixtures/path:${PATH}"
export REPO_SESSION_TMUXBIN="$PWD/fixtures/path/tmux-greenui"
export FERRY_DEMO_VERSION
FERRY_DEMO_VERSION="$(tr -d '[:space:]' <"$FERRY_DEMO_ROOT/VERSION")"
export FERRY_DEMO_VERSION_FILE="$FERRY_DEMO_ROOT/VERSION"

# Config/env: point ferry at sandbox host; never real ~/.ssh.
export FERRY_DEFAULT_HOST="${FERRY_DEFAULT_HOST:-workstation}"
export FERRY_BANNER=on
# Quiet shell chrome inside vhs (also covered by fixtures/home/.bashrc).
export PS1='$ '
unset PROMPT_COMMAND || true
# VHS provides a TTY, but force chrome so doctor/help glyphs always render
# (some vhs/ttyd paths leave stderr non-TTY for [[ -t 2 ]]).
export GREEN_UI_FORCE_TTY=1
export GREEN_UI_FORCE_MODE="${GREEN_UI_FORCE_MODE:-true}"
# Wide enough that picker header (40% of cols) still hits the boat+figlet tier.
export COLUMNS="${COLUMNS:-160}"
export LINES="${LINES:-40}"

mkdir -p ../assets build

for tape in scenes/*.tape; do
  # Restage right before picker: other fleet children share -L greenui-demo
  # and may kill-server; doctor/help do not need live sessions.
  case "$(basename "$tape")" in
    picker.tape)
      demo_tmux start
      _stage_sessions
      # Sanity: three staged targets must exist.
      n=$(tmux -L greenui-demo -f /dev/null list-sessions 2>/dev/null | wc -l | tr -d ' ')
      if [ "${n:-0}" -lt 3 ]; then
        printf 'record.sh: expected ≥3 greenui-demo sessions before picker, got %s\n' "$n" >&2
        exit 1
      fi
      ;;
  esac
  demo_record "$tape"
done
