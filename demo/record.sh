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
# server), then drop the harness placeholder "demo" session. Clean prompts
# so pane previews never leak the real hostname.
_stage_sessions() {
  local name
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
  # Drop placeholder from demo_tmux start (server stays up: we have 3 sessions).
  tmux -L greenui-demo -f /dev/null kill-session -t "=demo" 2>/dev/null || true
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

mkdir -p ../assets build

for tape in scenes/*.tape; do
  demo_record "$tape"
done
