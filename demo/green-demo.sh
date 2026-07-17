#!/usr/bin/env bash
# GREEN-UI-KIT demo harness — dev-only recording helpers.
# Never sourced by green-ui.sh runtime. Zero runtime deps.
# macOS bash 3.2 clean (vendored by mossferry).
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# Resolve this file's real path (THE SYMLINK LESSON: no readlink -f).
# ---------------------------------------------------------------------------
_demo_resolve_self() {
  local target="${BASH_SOURCE[0]}"
  # Walk symlink chain; relative links are resolved against the link's dirname.
  while [ -L "$target" ]; do
    local link dir
    link=$(readlink "$target") || return 1
    case "$link" in
      /*) target=$link ;;
      *)
        dir=$(dirname "$target")
        target="$dir/$link"
        ;;
    esac
  done
  # Canonicalize directory of the final target.
  local dir
  dir=$(cd "$(dirname "$target")" && pwd) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$target")"
}

# ---------------------------------------------------------------------------
# demo_banned_strings — default personal-identifier list, one per line.
# Repo names are NOT banned. Repos may extend via demo/banned.txt.
# ---------------------------------------------------------------------------
demo_banned_strings() {
  printf '%s\n' \
    kento \
    muslewski \
    manjaro-remote \
    "$(hostname 2>/dev/null || true)" \
    /home/kento \
    /Users/muslewski
}

# ---------------------------------------------------------------------------
# demo_sandbox <repo_demo_dir>
# Creates mktemp root; exports HOME + four XDG_* vars inside it; overlays
# fixtures/home when present; exports DEMO_ANCHOR_EPOCH; runs fixtures/gen.sh
# if present. Prints sandbox root on stdout.
# ---------------------------------------------------------------------------
demo_sandbox() {
  local repo_demo_dir=${1:?demo_sandbox: repo_demo_dir required}
  local root
  root=$(mktemp -d "${TMPDIR:-/tmp}/green-demo.XXXXXX") || return 1

  export HOME="$root/home"
  mkdir -p "$HOME"

  export XDG_CONFIG_HOME="$root/xdg/config"
  export XDG_DATA_HOME="$root/xdg/data"
  export XDG_STATE_HOME="$root/xdg/state"
  export XDG_CACHE_HOME="$root/xdg/cache"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

  if [ -d "$repo_demo_dir/fixtures/home" ]; then
    # Overlay fixture tree onto sandbox HOME (mirrors real HOME layout).
    cp -a "$repo_demo_dir/fixtures/home/." "$HOME/"
  fi

  # Capture anchor once for deterministic generators.
  DEMO_ANCHOR_EPOCH=$(date +%s)
  export DEMO_ANCHOR_EPOCH

  if [ -f "$repo_demo_dir/fixtures/gen.sh" ]; then
    # shellcheck disable=SC1090
    bash "$repo_demo_dir/fixtures/gen.sh"
  fi

  printf '%s\n' "$root"
}

# ---------------------------------------------------------------------------
# demo_tmux start|stop — isolated server on socket -L greenui-demo only.
# stop kills ONLY that socket's server. Never touch the user's live tmux.
# ---------------------------------------------------------------------------
demo_tmux() {
  local action=${1:?demo_tmux: start|stop required}
  case "$action" in
    start)
      # -f /dev/null: no user config; isolated socket name.
      tmux -L greenui-demo -f /dev/null start-server
      # Detached session so the server stays alive for attachments.
      tmux -L greenui-demo -f /dev/null has-session -t demo 2>/dev/null \
        || tmux -L greenui-demo -f /dev/null new-session -d -s demo
      ;;
    stop)
      # Kill only this socket's server; ignore if already gone.
      tmux -L greenui-demo kill-server 2>/dev/null || true
      ;;
    *)
      printf 'demo_tmux: unknown action %s (want start|stop)\n' "$action" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# demo_record <scene.tape>
# Concat house.tape + scene → build/<scene>.tape; preflight trio; run vhs from
# caller demo/; size-gate GIFs (≤2MB); privacy-gate build/<scene>.txt.
# ---------------------------------------------------------------------------
demo_record() {
  local scene=${1:?demo_record: scene.tape required}
  local self_path house_tape scene_base build_tape
  local tool

  self_path=$(_demo_resolve_self) || {
    printf 'demo_record: cannot resolve self path\n' >&2
    return 1
  }
  house_tape="$(dirname "$self_path")/house.tape"
  if [ ! -r "$house_tape" ]; then
    printf 'demo_record: house.tape missing beside harness: %s\n' "$house_tape" >&2
    return 1
  fi
  if [ ! -r "$scene" ]; then
    printf 'demo_record: scene tape not readable: %s\n' "$scene" >&2
    return 1
  fi

  # Preflight: vhs, ttyd, ffmpeg must be on PATH.
  for tool in vhs ttyd ffmpeg; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      printf 'demo_record: missing required tool: %s\n' "$tool" >&2
      printf '  install on Manjaro: sudo pacman -S vhs ttyd ffmpeg\n' >&2
      printf '  (vhs may be in AUR: yay -S vhs)\n' >&2
      return 1
    fi
  done

  scene_base=$(basename "$scene" .tape)
  mkdir -p build
  build_tape="build/${scene_base}.tape"
  cat "$house_tape" "$scene" >"$build_tape"

  # Run vhs from the calling repo's demo/ directory (caller cwd).
  vhs "$build_tape" || {
    printf 'demo_record: vhs failed for %s\n' "$build_tape" >&2
    return 1
  }

  # Size gate: every declared Output *.gif exists and is ≤ 2 MiB.
  local max_bytes=$((2 * 1024 * 1024))
  local out_line out_path size
  while IFS= read -r out_line || [ -n "$out_line" ]; do
    # Match Output lines that declare a .gif
    case "$out_line" in
      *[Oo]utput*.gif|*[Oo]utput*.GIF) ;;
      *) continue ;;
    esac
    out_path=${out_line##* }
    out_path=${out_path//$'\r'/}
    case "$out_path" in
      *.gif|*.GIF) ;;
      *) continue ;;
    esac
    if [ ! -f "$out_path" ]; then
      printf 'demo_record: missing GIF output: %s\n' "$out_path" >&2
      return 1
    fi
    size=$(wc -c <"$out_path" | tr -d ' ')
    if [ "$size" -gt "$max_bytes" ]; then
      printf 'demo_record: GIF exceeds 2 MB (%s bytes): %s\n' "$size" "$out_path" >&2
      return 1
    fi
  done <"$scene"

  # Privacy gate: rendered .txt must not contain banned strings.
  local txt="build/${scene_base}.txt"
  while IFS= read -r out_line || [ -n "$out_line" ]; do
    case "$out_line" in
      *[Oo]utput*.txt|*[Oo]utput*.TXT) ;;
      *) continue ;;
    esac
    out_path=${out_line##* }
    out_path=${out_path//$'\r'/}
    case "$out_path" in
      *.txt|*.TXT)
        if [ -f "$out_path" ]; then
          txt=$out_path
        fi
        ;;
    esac
  done <"$scene"

  if [ ! -f "$txt" ]; then
    printf 'demo_record: missing rendered txt for privacy gate: %s\n' "$txt" >&2
    return 1
  fi

  local banned_list banned
  banned_list=$(demo_banned_strings)
  if [ -f banned.txt ]; then
    banned_list=$(printf '%s\n%s\n' "$banned_list" "$(cat banned.txt)")
  fi

  while IFS= read -r banned || [ -n "$banned" ]; do
    [ -z "$banned" ] && continue
    if grep -Fq -- "$banned" "$txt"; then
      printf 'demo_record: privacy gate hit banned string %s in %s\n' "$banned" "$txt" >&2
      return 1
    fi
  done <<EOF
$banned_list
EOF

  return 0
}
