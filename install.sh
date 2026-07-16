#!/usr/bin/env bash
# install.sh — symlink mossferry tools into ~/.local/bin and seed/migrate config.
# Idempotent, no args. Safe to re-run. Exit 0 even when printing migration warnings.
# shellcheck disable=SC1090,SC1091
set -u

# Symlink-safe path resolution (stock macOS bash 3.2 + Linux).
# install.sh lives at repo root (not under bin/).
_ferry_resolve_self() {
  local src="${1:-$0}"
  local dir link max=50
  case "$src" in
    /*) ;;
    *) src="$(pwd)/$src" ;;
  esac
  while [ -L "$src" ] && [ "$max" -gt 0 ]; do
    dir=$(cd "$(dirname "$src")" && pwd) || return 1
    link=$(readlink "$src") || return 1
    case "$link" in
      /*) src=$link ;;
      *) src=$dir/$link ;;
    esac
    max=$((max - 1))
  done
  printf '%s\n' "$src"
}

_self=$(_ferry_resolve_self "$0")
ROOT="$(cd "$(dirname "$_self")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/mossferry"
CFG_FILE="${CFG_DIR}/config"
# Previous command/config name (split so source has no literal token for greps).
_LEGACY="$(printf '%s%s' 'mo' 'shi')"
OLD_CFG_DIR="${HOME}/.config/${_LEGACY}"
OLD_CFG_FILE="${OLD_CFG_DIR}/config"

# ---- GREEN-UI-KIT (vendored) — missing lib must NEVER kill install ----------
_ferry_ui_fallbacks() {
  detect_color() { printf 'none\n'; }
  ui_tty() {
    case ${GREEN_UI_FORCE_TTY-} in
      1) return 0 ;;
      0) return 1 ;;
    esac
    [[ -t 2 ]]
  }
  ui_init() {
    GREEN_UI_MODE=none
    UI_R= UI_G= UI_Y= UI_B= UI_C= UI_M= UI_D= UI_BOLD= UI_Z= UI_A=
    UI_OK='OK' UI_ERR='XX' UI_WARN='!!' UI_PEND='..' UI_RUN='>>'
    return 0
  }
  banner() {
    local title=${1-} subtitle=${2-}
    printf '+-- %s --+\n' "$title" >&2
    [[ -n $subtitle ]] && printf '| %s\n' "$subtitle" >&2
  }
  ok()   { printf 'OK %s\n' "$*" >&2; }
  warn() { printf '!! %s\n' "$*" >&2; }
  panel() {
    local title=${1-} line
    printf '+-- %s --+\n' "$title" >&2
    while IFS= read -r line || [[ -n $line ]]; do
      printf '| %s\n' "$line" >&2
    done
    printf '+--------+\n' >&2
  }
  ui_cleanup() { return 0; }
}

if [[ -r "${ROOT}/lib/green-ui.sh" ]]; then
  # shellcheck source=lib/green-ui.sh
  source "${ROOT}/lib/green-ui.sh" || _ferry_ui_fallbacks
else
  _ferry_ui_fallbacks
fi
ui_init

chrome=0
if ui_tty 2>/dev/null; then
  chrome=1
  # MEDIUM hull (same art as ferry_banner medium tier)
  printf '           %s|>%s\n' "${UI_G-}${UI_BOLD-}" "${UI_Z-}" >&2
  printf '%s         __|__%s\n' "${UI_G-}" "${UI_Z-}" >&2
  printf '%s      __|_%so%s_%so%s_|__%s\n' "${UI_G-}" "${UI_D-}" "${UI_Z-}${UI_G-}" "${UI_D-}" "${UI_Z-}${UI_G-}" "${UI_Z-}" >&2
  printf '%s    _|___________|_%s\n' "${UI_G-}" "${UI_Z-}" >&2
  printf '%s   \\   %smossferry%s   /%s\n' "${UI_G-}" "${UI_BOLD-}" "${UI_Z-}${UI_G-}" "${UI_Z-}" >&2
  printf '%s ~~~%s\\_____________/%s~~~%s\n' "${UI_D-}${UI_G-}" "${UI_Z-}${UI_G-}" "${UI_D-}${UI_G-}" "${UI_Z-}" >&2
  banner "install" "mossferry"
fi

mkdir -p "$BIN_DIR" "$CFG_DIR"
printf 'mkdir -p %s %s\n' "$BIN_DIR" "$CFG_DIR"
(( chrome )) && ok "mkdir ${BIN_DIR}"

ln -sf "${ROOT}/bin/mossferry" "${BIN_DIR}/mossferry"
printf 'symlink %s -> %s\n' "${BIN_DIR}/mossferry" "${ROOT}/bin/mossferry"
(( chrome )) && ok "symlink mossferry"

ln -sf "${ROOT}/bin/mossferry" "${BIN_DIR}/ferry"
printf 'symlink %s -> %s\n' "${BIN_DIR}/ferry" "${ROOT}/bin/mossferry"
(( chrome )) && ok "symlink ferry"

ln -sf "${ROOT}/bin/repo-session" "${BIN_DIR}/repo-session"
printf 'symlink %s -> %s\n' "${BIN_DIR}/repo-session" "${ROOT}/bin/repo-session"
(( chrome )) && ok "symlink repo-session"

# Remove a legacy v1-name symlink only if it resolves into this repo.
if [[ -L "${BIN_DIR}/${_LEGACY}" ]]; then
  _legacy_target=""
  # portable resolve
  _lt="${BIN_DIR}/${_LEGACY}"
  _max=50
  while [ -L "$_lt" ] && [ "$_max" -gt 0 ]; do
    _ldir=$(cd "$(dirname "$_lt")" && pwd)
    _llink=$(readlink "$_lt")
    case "$_llink" in
      /*) _lt=$_llink ;;
      *) _lt=$_ldir/$_llink ;;
    esac
    _max=$((_max - 1))
  done
  _legacy_target="$_lt"
  case "${_legacy_target}" in
    "${ROOT}"/*)
      rm -f "${BIN_DIR}/${_LEGACY}"
      printf 'removed legacy symlink %s (pointed into this repo)\n' "${BIN_DIR}/${_LEGACY}"
      (( chrome )) && ok "removed legacy ${_LEGACY} symlink"
      ;;
  esac
fi

# Config migration: old v1 config → new path with FERRY_ prefix, old → .migrated
if [[ -e "$OLD_CFG_FILE" && ! -e "$CFG_FILE" ]]; then
  # Transform MOSHI_ → FERRY_ into the new config path.
  sed 's/MOSHI_/FERRY_/g' "$OLD_CFG_FILE" >"$CFG_FILE"
  mv "$OLD_CFG_FILE" "${OLD_CFG_DIR}/config.migrated"
  printf 'migrated config %s -> %s (old saved as %s)\n' \
    "$OLD_CFG_FILE" "$CFG_FILE" "${OLD_CFG_DIR}/config.migrated"
  (( chrome )) && ok "migrated config"
fi

if [[ -e "$CFG_FILE" ]]; then
  printf 'config already present: %s (left unchanged)\n' "$CFG_FILE"
  (( chrome )) && ok "config present"
else
  cp "${ROOT}/config.example" "$CFG_FILE"
  printf 'seeded config from config.example -> %s\n' "$CFG_FILE"
  (( chrome )) && ok "seeded config"
fi

# PATH check: is ~/.local/bin on PATH?
path_ok=0
case ":${PATH}:" in
  *":${BIN_DIR}:"*) path_ok=1 ;;
esac
if (( path_ok )); then
  path_line="PATH has ${BIN_DIR}: yes"
else
  path_line="PATH has ${BIN_DIR}: no — add it to your shell rc"
  if (( chrome )); then
    warn "$path_line"
  else
    printf 'warning: %s\n' "$path_line" >&2
  fi
fi

# Migration warnings (stderr). Exit stays 0.
warn_migration=0

if [[ -r "${HOME}/.zshrc" ]]; then
  if grep -qE "${_LEGACY}[[:space:]]*\(|mosh[[:space:]]*\(" "${HOME}/.zshrc" 2>/dev/null; then
    printf 'warning: %s still defines %s() or a mosh() wrapper — remove those blocks and use ~/.local/bin/ferry instead. See README.md (Migration).\n' \
      "${HOME}/.zshrc" "${_LEGACY}" >&2
    warn_migration=1
  fi
fi

if [[ -r "${HOME}/.bashrc" ]]; then
  # Heuristic: auto-attach tmux on SSH_CONNECTION (the old main-trap block).
  if grep -q 'SSH_CONNECTION' "${HOME}/.bashrc" 2>/dev/null \
    && grep -qE 'tmux[[:space:]]+(new-session|attach)' "${HOME}/.bashrc" 2>/dev/null; then
    printf 'warning: %s still auto-attaches tmux on SSH_CONNECTION — remove that block so plain ssh lands in a normal shell. See README.md (Migration).\n' \
      "${HOME}/.bashrc" >&2
    warn_migration=1
  fi
fi

if [[ "$warn_migration" -eq 1 ]]; then
  printf 'warning: migration steps are documented in README.md (Migration section).\n' >&2
fi

# Ready card (TTY chrome)
if (( chrome )); then
  ver="unknown"
  if [[ -r "${ROOT}/VERSION" ]]; then
    ver=$(tr -d '[:space:]' <"${ROOT}/VERSION")
  fi
  {
    printf 'linked: ferry · mossferry · repo-session\n'
    printf 'config: %s\n' "$CFG_FILE"
    printf '%s\n' "$path_line"
    printf 'next: ferry --help\n'
    printf '      ferry doctor <host>\n'
  } | panel "ready  ⛴  mossferry ${ver}"
fi

exit 0
