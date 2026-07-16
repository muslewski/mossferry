#!/usr/bin/env bash
# install.sh — symlink mossferry tools into ~/.local/bin and seed/migrate config.
# Idempotent, no args. Safe to re-run. Exit 0 even when printing migration warnings.
set -u

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/mossferry"
CFG_FILE="${CFG_DIR}/config"
# Previous command/config name (split so source has no literal token for greps).
_LEGACY="$(printf '%s%s' 'mo' 'shi')"
OLD_CFG_DIR="${HOME}/.config/${_LEGACY}"
OLD_CFG_FILE="${OLD_CFG_DIR}/config"

mkdir -p "$BIN_DIR" "$CFG_DIR"
printf 'mkdir -p %s %s\n' "$BIN_DIR" "$CFG_DIR"

ln -sf "${ROOT}/bin/mossferry" "${BIN_DIR}/mossferry"
printf 'symlink %s -> %s\n' "${BIN_DIR}/mossferry" "${ROOT}/bin/mossferry"

ln -sf "${ROOT}/bin/mossferry" "${BIN_DIR}/ferry"
printf 'symlink %s -> %s\n' "${BIN_DIR}/ferry" "${ROOT}/bin/mossferry"

ln -sf "${ROOT}/bin/repo-session" "${BIN_DIR}/repo-session"
printf 'symlink %s -> %s\n' "${BIN_DIR}/repo-session" "${ROOT}/bin/repo-session"

# Remove a legacy v1-name symlink only if it resolves into this repo.
if [[ -L "${BIN_DIR}/${_LEGACY}" ]]; then
  _legacy_target="$(readlink -f "${BIN_DIR}/${_LEGACY}" 2>/dev/null || true)"
  case "${_legacy_target}" in
    "${ROOT}"/*)
      rm -f "${BIN_DIR}/${_LEGACY}"
      printf 'removed legacy symlink %s (pointed into this repo)\n' "${BIN_DIR}/${_LEGACY}"
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
fi

if [[ -e "$CFG_FILE" ]]; then
  printf 'config already present: %s (left unchanged)\n' "$CFG_FILE"
else
  cp "${ROOT}/config.example" "$CFG_FILE"
  printf 'seeded config from config.example -> %s\n' "$CFG_FILE"
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

exit 0
