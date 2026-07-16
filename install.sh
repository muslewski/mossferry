#!/usr/bin/env bash
# install.sh — symlink moshi tools into ~/.local/bin and seed config if absent.
# Idempotent, no args. Safe to re-run. Exit 0 even when printing migration warnings.
set -u

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/moshi"
CFG_FILE="${CFG_DIR}/config"

mkdir -p "$BIN_DIR" "$CFG_DIR"
printf 'mkdir -p %s %s\n' "$BIN_DIR" "$CFG_DIR"

ln -sf "${ROOT}/bin/moshi" "${BIN_DIR}/moshi"
printf 'symlink %s -> %s\n' "${BIN_DIR}/moshi" "${ROOT}/bin/moshi"

ln -sf "${ROOT}/bin/repo-session" "${BIN_DIR}/repo-session"
printf 'symlink %s -> %s\n' "${BIN_DIR}/repo-session" "${ROOT}/bin/repo-session"

if [[ -e "$CFG_FILE" ]]; then
  printf 'config already present: %s (left unchanged)\n' "$CFG_FILE"
else
  cp "${ROOT}/config.example" "$CFG_FILE"
  printf 'seeded config from config.example -> %s\n' "$CFG_FILE"
fi

# Migration warnings (stderr). Exit stays 0.
warn_migration=0

if [[ -r "${HOME}/.zshrc" ]]; then
  if grep -qE 'moshi[[:space:]]*\(|mosh[[:space:]]*\(' "${HOME}/.zshrc" 2>/dev/null; then
    printf 'warning: %s still defines moshi() or a mosh() wrapper — remove those blocks and use ~/.local/bin/moshi instead. See README.md (Migration).\n' \
      "${HOME}/.zshrc" >&2
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
