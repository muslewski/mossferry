#!/usr/bin/env bash
# tests/test-ui-ops.sh — Phase 2 ops-surface polish (f1–f7)
# Additive only; does not modify m1–m16 / t1–t35 / install assertions.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FERRY="${ROOT}/bin/mossferry"
RS="${ROOT}/bin/repo-session"
INSTALL="${ROOT}/install.sh"
FAKE_BIN="${ROOT}/tests/fake-bin"
FAKE_TMUX="${ROOT}/tests/fake-tmux"
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
fail=0

ok()   { printf 'ok %s\n' "$1"; }
FAIL() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

strip_ansi() {
  sed $'s/\033\\[[0-9;]*m//g'
}

# ---------------------------------------------------------------------------
# f1: doctor — non-TTY tokens byte-compatible; forced-TTY glyph + summary
# ---------------------------------------------------------------------------
{
  name=f1
  home="$(mktemp -d)"
  logf="$(mktemp)"
  outf="$(mktemp)"
  errf="$(mktemp)"
  export HOME="$home" FAKE_NET_LOG="$logf" PATH="${FAKE_BIN}:${PATH}"
  : >"$logf"

  # non-TTY (default under capture)
  set +e
  "$FERRY" doctor h >"$outf" 2>"$errf"
  rc=$?
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
  combined="$out$err"

  has_token=0 zero_ansi=0
  [[ "$out" == *"ok versions match: ${VERSION}"* ]] && has_token=1
  if ! printf '%s' "$combined" | grep -q $'\033'; then
    zero_ansi=1
  fi
  # doctor should exit 0 with fake ssh (all ok)
  if [[ $has_token -eq 1 && $zero_ansi -eq 1 ]]; then
    ok "${name}-nontty-tokens"
  else
    FAIL "${name}-nontty-tokens (token=$has_token ansi_free=$zero_ansi out=$(printf %q "$out"))"
  fi

  # forced-TTY: glyph checklist + summary (stderr chrome and/or enhanced lines)
  set +e
  GREEN_UI_FORCE_TTY=1 GREEN_UI_FORCE_MODE=16 GREEN_UI_ASCII=1 \
    "$FERRY" doctor h >"$outf" 2>"$errf"
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
  both="$(printf '%s\n%s\n' "$out" "$err")"
  stripped=$(printf '%s' "$both" | strip_ansi)
  # ASCII glyphs under GREEN_UI_ASCII=1: OK / XX; or unicode ✓/✗; summary words
  has_glyph=0 has_summary=0
  if printf '%s\n' "$stripped" | grep -qE '(^| )(OK|XX|✓|✗) '; then
    has_glyph=1
  fi
  if printf '%s\n' "$stripped" | grep -qiE 'check|failed|summary|pass'; then
    has_summary=1
  fi
  # banner or ferry doctor label
  has_banner=0
  if printf '%s\n' "$stripped" | grep -qiE 'doctor|ferry|mossferry'; then
    has_banner=1
  fi
  if [[ $has_glyph -eq 1 && ( $has_summary -eq 1 || $has_banner -eq 1 ) ]]; then
    ok "${name}-forced-tty-chrome"
  else
    FAIL "${name}-forced-tty-chrome (glyph=$has_glyph summary=$has_summary banner=$has_banner)"
    printf '  stripped=%s\n' "$stripped" >&2
  fi

  # version mismatch → fix hint on FAIL path (forced TTY)
  # make remote version differ via FAKE: temporarily patch by using a fake VERSION path is hard;
  # instead: inject via env by running doctor after renaming — use ssh stub override:
  # When versions mismatch, doctor prints FAIL versions + hint ferry update
  # Simulate: write a different local VERSION in a copy is heavy; call with
  # REPO root still same. Skip if we cannot force mismatch without editing VERSION.
  # Soft check: doctor code path for fix-hint is covered when FAIL exists.
  # Create isolated copy of binary root is overkill — assert that when we
  # force remote cat to print other version via FAKE_SSH custom is not available.
  # Acceptable: if FAIL versions appears in a mismatch fixture using
  # a wrapper. We'll use a subshell with a temp VERSION if doctor re-reads.
  # own_version reads REPO_ROOT/VERSION which is fixed. Use fake-bin ssh already
  # prints repo VERSION. Override by FAKE_NET and a custom PATH ssh:
  mishome="$(mktemp -d)"
  mkdir -p "$mishome/bin"
  cat >"$mishome/bin/ssh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "${FAKE_NET_LOG:?}"
joined="$*"
if [[ "$joined" == *cat* && "$joined" == *VERSION* ]]; then
  printf '0.0.0-mismatch\n'
  exit 0
fi
if [[ "$joined" == *"--validate"* ]]; then exit 0; fi
if [[ "$joined" == *" git -C "*remote ]]; then exit 0; fi
if [[ "$joined" == *"rev-parse"* ]]; then exit 0; fi
if [[ "$joined" == *"pgrep"* ]]; then printf '0\n'; exit 0; fi
if [[ "$joined" == *"command -v fzf"* ]] || [[ "$joined" == *"command -v"* ]]; then exit 0; fi
if [[ "$joined" == *"test -x"* ]]; then exit 0; fi
if [[ "$1" == "-G" ]]; then printf 'hostname 10.0.0.1\n'; exit 0; fi
if [[ "$*" == *BatchMode* ]] || [[ "$*" == *true* ]]; then exit 0; fi
exit 0
EOS
  chmod +x "$mishome/bin/ssh"
  # also need mosh in path
  ln -sf "${FAKE_BIN}/mosh" "$mishome/bin/mosh" 2>/dev/null || cp "${FAKE_BIN}/mosh" "$mishome/bin/mosh"
  : >"$logf"
  set +e
  HOME="$home" FAKE_NET_LOG="$logf" PATH="${mishome}/bin:${PATH}" \
    GREEN_UI_FORCE_TTY=1 GREEN_UI_FORCE_MODE=16 GREEN_UI_ASCII=1 \
    "$FERRY" doctor h >"$outf" 2>"$errf"
  drc=$?
  set -e
  both="$(cat "$outf"; echo; cat "$errf")"
  stripped=$(printf '%s' "$both" | strip_ansi)
  if [[ $drc -ne 0 ]] \
    && printf '%s\n' "$stripped" | grep -q 'FAIL versions' \
    && printf '%s\n' "$stripped" | grep -qiE 'ferry update|update'; then
    ok "${name}-fail-hint"
  else
    FAIL "${name}-fail-hint (exit=$drc)"
    printf '  stripped=%s\n' "$stripped" >&2
  fi

  rm -rf "$home" "$mishome" "$outf" "$errf" "$logf"
}

# ---------------------------------------------------------------------------
# f2: update — non-TTY ends local/remote; forced-TTY steps + wave strip
# ---------------------------------------------------------------------------
{
  name=f2
  home="$(mktemp -d)"
  logf="$(mktemp)"
  outf="$(mktemp)"
  errf="$(mktemp)"
  export HOME="$home" FAKE_NET_LOG="$logf" PATH="${FAKE_BIN}:${PATH}"
  : >"$logf"

  set +e
  "$FERRY" update h >"$outf" 2>"$errf"
  rc=$?
  set -e
  out="$(cat "$outf")"
  if [[ $rc -eq 0 && "$out" == *"local ${VERSION} / remote ${VERSION}"* ]]; then
    ok "${name}-nontty-versions"
  else
    FAIL "${name}-nontty-versions (exit=$rc out=$(printf %q "$out"))"
  fi

  set +e
  GREEN_UI_FORCE_TTY=1 GREEN_UI_FORCE_MODE=16 GREEN_UI_ASCII=1 \
    "$FERRY" update h >"$outf" 2>"$errf"
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
  both="$(printf '%s\n%s\n' "$out" "$err")"
  stripped=$(printf '%s' "$both" | strip_ansi)
  has_step=0 has_wave=0
  if printf '%s\n' "$stripped" | grep -qiE 'local pull|remote pull'; then
    has_step=1
  fi
  # wave strip must contain the crossing waves token
  if printf '%s\n' "$stripped" | grep -qF '~~~'; then
    has_wave=1
  fi
  if [[ $has_step -eq 1 && $has_wave -eq 1 ]]; then
    ok "${name}-forced-tty-crossing"
  else
    FAIL "${name}-forced-tty-crossing (step=$has_step wave=$has_wave)"
    printf '  stripped=%s\n' "$stripped" >&2
  fi

  rm -rf "$home" "$outf" "$errf" "$logf"
}

# ---------------------------------------------------------------------------
# f3: --help sectioned; launcher keys; cycle; version footer
# ---------------------------------------------------------------------------
{
  name=f3
  home="$(mktemp -d)"
  logf="$(mktemp)"
  outf="$(mktemp)"
  errf="$(mktemp)"
  export HOME="$home" FAKE_NET_LOG="$logf" PATH="${FAKE_BIN}:${PATH}"
  : >"$logf"

  set +e
  "$FERRY" --help >"$outf" 2>"$errf"
  mrc=$?
  set -e
  out="$(cat "$outf"; cat "$errf")"
  stripped=$(printf '%s' "$out" | strip_ansi)

  miss=()
  for needle in "start menu" "FERRY_START_MENU" "--cycle" "Usage" "Picker" "Flags" "Config" "Examples" \
    "mossferry ${VERSION}" "green ferry"; do
    if [[ "$stripped" != *"$needle"* ]]; then
      # allow case-insensitive section headers for single words
      case "$needle" in
        Usage|Picker|Flags|Config|Examples)
          if printf '%s\n' "$stripped" | grep -qiF "$needle"; then
            continue
          fi
          ;;
      esac
      miss+=("$needle")
    fi
  done
  if [[ $mrc -eq 0 && ${#miss[@]} -eq 0 ]]; then
    ok "${name}-mossferry-help"
  else
    FAIL "${name}-mossferry-help (exit=$mrc missing=${miss[*]-})"
  fi

  set +e
  REPO_SESSION_TMUXBIN="$FAKE_TMUX" FAKE_TMUX_SESSIONS="" \
    "$RS" --help >"$outf" 2>"$errf"
  rrc=$?
  set -e
  out="$(cat "$outf"; cat "$errf")"
  stripped=$(printf '%s' "$out" | strip_ansi)
  miss=()
  for needle in "start menu" "FERRY_START_MENU" "Flags" "mossferry ${VERSION}"; do
    if [[ "$stripped" != *"$needle"* ]]; then
      miss+=("$needle")
    fi
  done
  if [[ $rrc -eq 0 && ${#miss[@]} -eq 0 ]]; then
    ok "${name}-repo-session-help"
  else
    FAIL "${name}-repo-session-help (exit=$rrc missing=${miss[*]-})"
  fi

  rm -rf "$home" "$outf" "$errf" "$logf"
}

# ---------------------------------------------------------------------------
# f4: validate error exact message + exit 1; forced-TTY did-you-mean
# ---------------------------------------------------------------------------
{
  name=f4
  base="$(mktemp -d)"
  mkdir -p "$base/syndcast" "$base/other-repo"
  home="$(mktemp -d)"
  outf="$(mktemp)"
  errf="$(mktemp)"
  export HOME="$home" FERRY_REPO_BASE="$base" REPO_SESSION_TMUXBIN="$FAKE_TMUX"
  export FAKE_TMUX_SESSIONS=""

  # exact non-TTY message
  set +e
  "$RS" --validate syndcas >"$outf" 2>"$errf"
  rc=$?
  set -e
  err="$(cat "$errf")"
  expected="repo-session: no repo 'syndcas' under ${base} — pick one below, or run 'ferry <host>' to browse all sessions"
  first_line="$(printf '%s\n' "$err" | head -n1)"
  if [[ $rc -eq 1 && "$first_line" == "$expected" ]]; then
    ok "${name}-exact-message"
  else
    FAIL "${name}-exact-message (exit=$rc first=$(printf %q "$first_line"))"
  fi

  # forced-TTY did-you-mean for 1-char typo
  set +e
  GREEN_UI_FORCE_TTY=1 GREEN_UI_FORCE_MODE=16 GREEN_UI_ASCII=1 \
    "$RS" --validate syndcas >"$outf" 2>"$errf"
  rc=$?
  set -e
  err="$(cat "$errf")"
  stripped=$(printf '%s' "$err" | strip_ansi)
  first_line="$(printf '%s\n' "$stripped" | head -n1)"
  if [[ $rc -eq 1 \
    && "$first_line" == "$expected" \
    && "$stripped" == *"did you mean"* \
    && "$stripped" == *"syndcast"* ]]; then
    ok "${name}-did-you-mean"
  else
    FAIL "${name}-did-you-mean (exit=$rc)"
    printf '  err=%s\n' "$stripped" >&2
  fi

  rm -rf "$base" "$home" "$outf" "$errf"
}

# ---------------------------------------------------------------------------
# f5: install.sh ready card in sandbox HOME; symlinks still correct
# ---------------------------------------------------------------------------
{
  name=f5
  home="$(mktemp -d)"
  outf="$(mktemp)"
  errf="$(mktemp)"

  set +e
  HOME="$home" GREEN_UI_FORCE_TTY=1 GREEN_UI_FORCE_MODE=16 GREEN_UI_ASCII=1 \
    bash "$INSTALL" >"$outf" 2>"$errf"
  rc=$?
  set -e
  out="$(cat "$outf")"
  err="$(cat "$errf")"
  both="$(printf '%s\n%s\n' "$out" "$err")"
  stripped=$(printf '%s' "$both" | strip_ansi)

  has_ready=0
  if printf '%s\n' "$stripped" | grep -qiE 'ready|next|ferry --help|PATH'; then
    has_ready=1
  fi
  link_ok=1
  for l in mossferry ferry repo-session; do
    if [[ ! -L "$home/.local/bin/$l" ]]; then
      link_ok=0
    fi
  done
  if [[ $rc -eq 0 && $has_ready -eq 1 && $link_ok -eq 1 ]]; then
    ok "${name}-ready-card"
  else
    FAIL "${name}-ready-card (exit=$rc ready=$has_ready links=$link_ok)"
    printf '  stripped=%s\n' "$stripped" >&2
  fi

  rm -rf "$home" "$outf" "$errf"
}

# ---------------------------------------------------------------------------
# f6: kit-absent → commands still work, plain output
# ---------------------------------------------------------------------------
{
  name=f6
  # work in a temp copy of the tree with lib removed
  copy="$(mktemp -d)"
  # minimal copy: bin, VERSION, lib removed, install, config.example
  mkdir -p "$copy/bin" "$copy/tests/fake-bin"
  cp "$ROOT/bin/mossferry" "$ROOT/bin/repo-session" "$copy/bin/"
  cp "$ROOT/VERSION" "$copy/"
  cp "$ROOT/install.sh" "$copy/" 2>/dev/null || true
  cp "$ROOT/config.example" "$copy/" 2>/dev/null || true
  cp -a "$ROOT/tests/fake-bin/." "$copy/tests/fake-bin/"
  # deliberately NO lib/
  home="$(mktemp -d)"
  logf="$(mktemp)"
  outf="$(mktemp)"
  errf="$(mktemp)"
  export HOME="$home" FAKE_NET_LOG="$logf" PATH="${copy}/tests/fake-bin:${PATH}"
  : >"$logf"

  set +e
  bash "$copy/bin/mossferry" --help >"$outf" 2>"$errf"
  hrc=$?
  bash "$copy/bin/mossferry" doctor h >"$outf" 2>"$errf"
  drc=$?
  out="$(cat "$outf")"
  bash "$copy/bin/mossferry" update h >"$outf" 2>"$errf"
  urc=$?
  uout="$(cat "$outf")"
  set -e

  if [[ $hrc -eq 0 && $drc -eq 0 && $urc -eq 0 \
    && "$out" == *"ok versions match:"* \
    && "$uout" == *"local ${VERSION} / remote ${VERSION}"* ]]; then
    ok "${name}-kit-absent"
  else
    FAIL "${name}-kit-absent (help=$hrc doctor=$drc update=$urc)"
    printf '  doctor out=%s\n' "$out" >&2
    printf '  update out=%s\n' "$uout" >&2
  fi

  rm -rf "$copy" "$home" "$outf" "$errf" "$logf"
}

# ---------------------------------------------------------------------------
# f7: bash -n both bins + kit; VERSION matches package.json
# ---------------------------------------------------------------------------
{
  name=f7
  bn=0
  bash -n "$FERRY" || bn=1
  bash -n "$RS" || bn=1
  bash -n "$INSTALL" || bn=1
  if [[ -f "$ROOT/lib/green-ui.sh" ]]; then
    bash -n "$ROOT/lib/green-ui.sh" || bn=1
  fi
  if [[ $bn -eq 0 ]]; then
    ok "${name}-bash-n"
  else
    FAIL "${name}-bash-n"
  fi
  pkg_ver=$(node -pe "require('$ROOT/package.json').version" 2>/dev/null || true)
  if [[ -n "$pkg_ver" && "$VERSION" == "$pkg_ver" ]]; then
    ok "${name}-version"
  else
    FAIL "${name}-version (got=$VERSION want=$pkg_ver)"
  fi
}

if [[ $fail -ne 0 ]]; then
  printf 'tests/test-ui-ops.sh: %s failure(s)\n' "$fail"
  exit 1
fi
printf 'tests/test-ui-ops.sh: all ok\n'
exit 0
