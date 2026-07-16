#!/usr/bin/env bash
# Vendored from GREEN-UI-KIT 0.1.0 (https://github.com / local: ~/Repositories/green-ui-kit).
# Source: green-ui.sh @ version 0.1.0 — pin; do not edit by hand; re-vendor to upgrade.
# The green ferry of the fleet UI kit.
#
# GREEN-UI-KIT — the shared green thread of the fleet.
# Source-able bash ≥4 UI library. No deps beyond coreutils/tput/awk; fzf optional.
#
# Law: stdout = data/records; stderr = chrome.
# Exceptions: choose (selection), sparkline, table → stdout.
# shellcheck shell=bash disable=SC2034

# Double-source guard
[[ -n ${GREEN_UI_LOADED-} ]] && return 0
GREEN_UI_LOADED=1

# ---------------------------------------------------------------------------
# detect_color [fd] → none|16|256|true  (default fd 2)
# ---------------------------------------------------------------------------
detect_color() {
  local fd=${1:-2}
  # 1) forced mode wins over everything (including NO_COLOR)
  if [[ -n ${GREEN_UI_FORCE_MODE-} ]]; then
    printf '%s\n' "$GREEN_UI_FORCE_MODE"
    return 0
  fi
  # 2) explicit mono / dumb / non-TTY fd
  if [[ -n ${NO_COLOR-} || ${TERM-} == dumb ]]; then
    printf 'none\n'
    return 0
  fi
  if [[ ! -t $fd ]]; then
    printf 'none\n'
    return 0
  fi
  # 3) truecolor
  case ${COLORTERM-} in
    truecolor|24bit)
      printf 'true\n'
      return 0
      ;;
  esac
  # 4) tput palette depth
  local n=0
  n=$(tput colors 2>/dev/null) || n=0
  if (( n >= 256 )); then
    printf '256\n'
    return 0
  fi
  if (( n >= 8 )); then
    printf '16\n'
    return 0
  fi
  # no useful color capability — still report 16 when TTY (basic ANSI assumed),
  # else none. Spec: else → 16 for TTY path that reached here.
  printf '16\n'
}

# ---------------------------------------------------------------------------
# ui_tty → 0 if stderr is a TTY (or FORCE_TTY=1), 1 otherwise (FORCE_TTY=0)
# ---------------------------------------------------------------------------
ui_tty() {
  case ${GREEN_UI_FORCE_TTY-} in
    1) return 0 ;;
    0) return 1 ;;
  esac
  [[ -t 2 ]]
}

# ---------------------------------------------------------------------------
# Internal: should we use ASCII glyphs?
# ---------------------------------------------------------------------------
_green_ui_want_ascii() {
  [[ ${GREEN_UI_ASCII-} == 1 ]] && return 0
  # locale lacks UTF-8
  local loc
  loc="${LC_ALL:-${LC_CTYPE:-${LANG-}}}"
  [[ "$loc" != *UTF-8* && "$loc" != *utf8* && "$loc" != *UTF8* ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# ui_init — idempotent; sets mode, colors, accent, glyphs
# ---------------------------------------------------------------------------
ui_init() {
  # Idempotent: re-running refreshes from current env (FORCE_MODE etc.)
  GREEN_UI_MODE=$(detect_color 2)

  # Color SGR sequences (empty when none)
  UI_R= UI_G= UI_Y= UI_B= UI_C= UI_M= UI_D= UI_BOLD= UI_Z= UI_A=

  local mode=$GREEN_UI_MODE
  if [[ $mode != none ]]; then
    UI_D=$'\e[2m'
    UI_BOLD=$'\e[1m'
    UI_Z=$'\e[0m'
    case $mode in
      true)
        UI_R=$'\e[38;2;248;113;113m'
        UI_G=$'\e[38;2;74;222;128m'
        UI_Y=$'\e[38;2;250;204;21m'
        UI_B=$'\e[38;2;88;166;255m'
        UI_C=$'\e[38;2;34;211;238m'
        UI_M=$'\e[38;2;192;132;252m'
        ;;
      256)
        UI_R=$'\e[38;5;210m'
        UI_G=$'\e[38;5;114m'
        UI_Y=$'\e[38;5;220m'
        UI_B=$'\e[38;5;75m'
        UI_C=$'\e[38;5;80m'
        UI_M=$'\e[38;5;212m'
        ;;
      16)
        UI_R=$'\e[31m'
        UI_G=$'\e[32m'
        UI_Y=$'\e[33m'
        UI_B=$'\e[34m'
        UI_C=$'\e[36m'
        UI_M=$'\e[35m'
        ;;
    esac

    # Accent UI_A from GREEN_UI_ACCENT: 256 index or R;G;B; default 108 (moss green)
    local acc=${GREEN_UI_ACCENT-108}
    if [[ "$acc" == *";"* ]]; then
      # R;G;B truecolor-style
      if [[ $mode == true ]]; then
        UI_A=$(printf '\033[38;2;%sm' "$acc")
      else
        UI_A=$(printf '\033[38;5;108m')
      fi
    else
      case $mode in
        true)
          if [[ $acc == 108 ]]; then
            UI_A=$(printf '\033[38;2;135;175;95m')
          else
            UI_A=$(printf '\033[38;5;%sm' "$acc")
          fi
          ;;
        *)
          UI_A=$(printf '\033[38;5;%sm' "$acc")
          ;;
      esac
    fi
  fi

  # Glyphs
  if _green_ui_want_ascii; then
    UI_OK='OK'
    UI_ERR='XX'
    UI_WARN='!!'
    UI_PEND='..'
    UI_RUN='>>'
    UI_SPIN=('|' '/' '-' '\')
  else
    UI_OK='✓'
    UI_ERR='✗'
    UI_WARN='●'
    UI_PEND='○'
    UI_RUN='▸'
    UI_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  fi

  return 0
}

# ---------------------------------------------------------------------------
# banner <title> [subtitle] → stderr
# ---------------------------------------------------------------------------
banner() {
  local title=${1-} subtitle=${2-}
  local a=${UI_A-} b=${UI_BOLD-} z=${UI_Z-} d=${UI_D-}
  local w pad i line

  if _green_ui_want_ascii; then
    # +-- title --+
    # | subtitle  |
    # +-----------+
    local inner_top="+-- ${title} --+"
    w=${#inner_top}
    printf '%s%s%s%s\n' "$a" "$b" "$inner_top" "$z" >&2
    if [[ -n $subtitle ]]; then
      # pad subtitle to inner width (w-2 for side bars)
      local content=" ${subtitle}"
      pad=$(( w - 2 - ${#content} ))
      if (( pad < 0 )); then pad=0; fi
      printf '%s|%s%s%*s%s|\n' "$a" "$z$d" "$content" "$pad" '' "$z$a" >&2
    fi
    # bottom
    printf '%s+' "$a" >&2
    for (( i = 0; i < w - 2; i++ )); do printf '-' >&2; done
    printf '+%s\n' "$z" >&2
  else
    # ╭─ title ─╮
    # │ subtitle │
    # ╰─────────╯
    local top_core="─ ${title} ─"
    # corners add 2 chars
    w=$(( ${#top_core} + 2 ))
    printf '%s%s╭%s╮%s\n' "$a" "$b" "$top_core" "$z" >&2
    if [[ -n $subtitle ]]; then
      local content=" ${subtitle}"
      pad=$(( w - 2 - ${#content} ))
      if (( pad < 0 )); then pad=0; fi
      printf '%s│%s%s%*s%s│%s\n' "$a" "$z$d" "$content" "$pad" '' "$a" "$z" >&2
    fi
    printf '%s╰' "$a" >&2
    for (( i = 0; i < w - 2; i++ )); do printf '─' >&2; done
    printf '╯%s\n' "$z" >&2
  fi
}

# ---------------------------------------------------------------------------
# ok / warn / die → stderr
# ---------------------------------------------------------------------------
ok() {
  printf '%s%s%s %s\n' "${UI_G-}" "${UI_OK-OK}" "${UI_Z-}" "$*" >&2
}

warn() {
  printf '%s%s%s %s\n' "${UI_Y-}" "${UI_WARN-!!}" "${UI_Z-}" "$*" >&2
}

die() {
  local msg=${1-error}
  local code=${2-1}
  printf '%s%s%s %s\n' "${UI_R-}" "${UI_ERR-XX}" "${UI_Z-}" "$msg" >&2
  exit "$code"
}

# ---------------------------------------------------------------------------
# spin_run <label> <cmd> [args…]
# ---------------------------------------------------------------------------
spin_run() {
  local label=$1
  shift
  local ec

  if ! ui_tty; then
    # non-TTY: no spinner bytes at all; still run cmd + settle line
    "$@"
    ec=$?
    if (( ec == 0 )); then
      printf '%s%s%s %s\n' "${UI_G-}" "${UI_OK-OK}" "${UI_Z-}" "$label" >&2
    else
      printf '%s%s%s %s\n' "${UI_R-}" "${UI_ERR-XX}" "${UI_Z-}" "$label" >&2
    fi
    return "$ec"
  fi

  # TTY: braille/ASCII spinner @80ms
  local i=0 pid
  "$@" &
  pid=$!
  printf '\e[?25l' >&2
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\e[K%s%s%s %s…' "${UI_C-}" "${UI_SPIN[i++ % ${#UI_SPIN[@]}]}" "${UI_Z-}" "$label" >&2
    sleep 0.08
  done
  wait "$pid"
  ec=$?
  printf '\r\e[K\e[?25h' >&2
  if (( ec == 0 )); then
    printf '%s%s%s %s\n' "${UI_G-}" "${UI_OK-OK}" "${UI_Z-}" "$label" >&2
  else
    printf '%s%s%s %s\n' "${UI_R-}" "${UI_ERR-XX}" "${UI_Z-}" "$label" >&2
  fi
  return "$ec"
}

# ---------------------------------------------------------------------------
# check_set <state-file> <id> <state>
# checklist <state-file> <id:label>…
# ---------------------------------------------------------------------------
check_set() {
  local sf=$1 id=$2 state=$3
  # append; last wins when reading
  printf '%s %s\n' "$id" "$state" >>"$sf"
}

_green_ui_state_of() {
  # _green_ui_state_of <state-file> <id> → state (default pending)
  local sf=$1 id=$2
  local line last=pending
  if [[ -f $sf ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      [[ -z $line ]] && continue
      local sid sst
      sid=${line%% *}
      sst=${line#* }
      [[ $sid == "$id" ]] && last=$sst
    done <"$sf"
  fi
  printf '%s\n' "$last"
}

checklist() {
  local sf=$1
  shift
  local items=("$@")
  local id label st g line n=0

  # TTY repaint: if we have a previous line count, cursor-up first
  if ui_tty && [[ -n ${_GREEN_UI_CHECK_N-} && ${_GREEN_UI_CHECK_N} -gt 0 ]]; then
    printf '\e[%dA' "$_GREEN_UI_CHECK_N" >&2
  fi

  n=0
  for item in "${items[@]}"; do
    id=${item%%:*}
    label=${item#*:}
    st=$(_green_ui_state_of "$sf" "$id")
    case $st in
      pending) g="${UI_D-}${UI_PEND-..}${UI_Z-}" ;;
      running) g="${UI_Y-}${UI_RUN->>}${UI_Z-}" ;;
      done)    g="${UI_G-}${UI_OK-OK}${UI_Z-}" ;;
      failed)  g="${UI_R-}${UI_ERR-XX}${UI_Z-}" ;;
      skipped) g="${UI_D-}–${UI_Z-}" ;;
      *)       g="${UI_D-}${UI_PEND-..}${UI_Z-}" ;;
    esac
    if ui_tty; then
      printf '\e[2K%s %s\n' "$g" "$label" >&2
    else
      # append-only: no cursor control
      printf '%s %s\n' "$g" "$label" >&2
    fi
    n=$((n + 1))
  done

  if ui_tty; then
    _GREEN_UI_CHECK_N=$n
  else
    _GREEN_UI_CHECK_N=0
  fi
}

# ---------------------------------------------------------------------------
# progress <pct> [width=24] → stderr
# ---------------------------------------------------------------------------
progress() {
  local pct=${1-0} width=${2-24}
  local filled empty i
  # clamp
  if (( pct < 0 )); then pct=0; fi
  if (( pct > 100 )); then pct=100; fi
  filled=$(( width * pct / 100 ))
  empty=$(( width - filled ))

  local fill_ch rail_ch
  if _green_ui_want_ascii; then
    fill_ch='#'
    rail_ch='-'
  else
    fill_ch='█'
    rail_ch='░'
  fi

  printf '%s[' "${UI_Z-}" >&2
  printf '%s' "${UI_G-}" >&2
  for (( i = 0; i < filled; i++ )); do printf '%s' "$fill_ch" >&2; done
  printf '%s' "${UI_D-}" >&2
  for (( i = 0; i < empty; i++ )); do printf '%s' "$rail_ch" >&2; done
  printf '%s] %s%%\n' "${UI_Z-}" "$pct" >&2
}

# ---------------------------------------------------------------------------
# sparkline <n>… → stdout (data-ish)
# ---------------------------------------------------------------------------
sparkline() {
  local -a ticks nums
  local n min max i sc idx

  if _green_ui_want_ascii; then
    ticks=('.' ':' '-' '=' '+' '*' '#' '%')
  else
    ticks=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
  fi

  min=999999999
  max=-999999999
  nums=()
  for n in "$@"; do
    n=${n%.*}
    # integer only
    nums+=("$n")
    if (( n < min )); then min=$n; fi
    if (( n > max )); then max=$n; fi
  done

  if (( ${#nums[@]} == 0 )); then
    printf '\n'
    return 0
  fi

  if (( min == max )); then
    for n in "${nums[@]}"; do
      printf '%s' "${ticks[4]}"
    done
    printf '\n'
    return 0
  fi

  # scale to 0..7
  for n in "${nums[@]}"; do
    # idx = round((n-min) / (max-min) * 7)
    idx=$(( (n - min) * 7 / (max - min) ))
    if (( idx < 0 )); then idx=0; fi
    if (( idx > 7 )); then idx=7; fi
    printf '%s' "${ticks[idx]}"
  done
  printf '\n'
}

# ---------------------------------------------------------------------------
# panel <title> — boxes stdin body → stderr
# ---------------------------------------------------------------------------
panel() {
  local title=${1-}
  local a=${UI_A-} z=${UI_Z-} d=${UI_D-}
  local -a lines=()
  local line maxw=0 w i pad content

  while IFS= read -r line || [[ -n $line ]]; do
    lines+=("$line")
    if (( ${#line} > maxw )); then maxw=${#line}; fi
  done

  # width: at least title + padding
  w=$maxw
  if (( ${#title} + 2 > w )); then w=$(( ${#title} + 2 )); fi
  if (( w < 8 )); then w=8; fi

  if _green_ui_want_ascii; then
    printf '%s+-- %s ' "$a" "$title" >&2
    pad=$(( w - ${#title} - 1 ))
    if (( pad < 0 )); then pad=0; fi
    for (( i = 0; i < pad; i++ )); do printf '-' >&2; done
    printf '+%s\n' "$z" >&2
    for line in "${lines[@]}"; do
      pad=$(( w - ${#line} ))
      if (( pad < 0 )); then pad=0; fi
      printf '%s|%s %s%*s %s|%s\n' "$a" "$z" "$line" "$pad" '' "$a" "$z" >&2
    done
    printf '%s+' "$a" >&2
    for (( i = 0; i < w + 2; i++ )); do printf '-' >&2; done
    printf '+%s\n' "$z" >&2
  else
    printf '%s╭─ %s ' "$a" "$title" >&2
    pad=$(( w - ${#title} - 1 ))
    if (( pad < 0 )); then pad=0; fi
    for (( i = 0; i < pad; i++ )); do printf '─' >&2; done
    printf '╮%s\n' "$z" >&2
    for line in "${lines[@]}"; do
      pad=$(( w - ${#line} ))
      if (( pad < 0 )); then pad=0; fi
      printf '%s│%s %s%*s %s│%s\n' "$a" "$z" "$line" "$pad" '' "$a" "$z" >&2
    done
    printf '%s╰' "$a" >&2
    for (( i = 0; i < w + 2; i++ )); do printf '─' >&2; done
    printf '╯%s\n' "$z" >&2
  fi
}

# ---------------------------------------------------------------------------
# table — TSV stdin → aligned columns via awk → stdout (data)
# bold first row when TTY
# ---------------------------------------------------------------------------
table() {
  local bold=0
  if ui_tty && [[ ${GREEN_UI_MODE-none} != none ]]; then
    bold=1
  fi
  local b=${UI_BOLD-} z=${UI_Z-}
  awk -v BOLD="$bold" -v B="$b" -v Z="$z" '
    BEGIN { FS = "\t"; maxc = 0 }
    {
      rows[NR] = $0
      if (NF > maxc) maxc = NF
      for (i = 1; i <= NF; i++) {
        cell[NR, i] = $i
        l = length($i)
        if (l > wid[i]) wid[i] = l
      }
      nrows = NR
    }
    END {
      for (r = 1; r <= nrows; r++) {
        line = ""
        for (c = 1; c <= maxc; c++) {
          s = cell[r, c]
          pad = wid[c] - length(s)
          if (pad < 0) pad = 0
          if (c > 1) line = line "  "
          line = line s
          for (p = 0; p < pad; p++) line = line " "
        }
        # trim trailing spaces
        sub(/[ ]+$/, "", line)
        if (BOLD && r == 1) printf "%s%s%s\n", B, line, Z
        else print line
      }
    }
  '
}

# ---------------------------------------------------------------------------
# choose <prompt> <opt>… → selection on stdout; menu chrome on stderr
# exit 130 on cancel
# ---------------------------------------------------------------------------
choose() {
  local prompt=$1
  shift
  local -a opts=("$@")
  local i n sel

  if (( ${#opts[@]} == 0 )); then
    return 1
  fi

  if ui_tty && command -v fzf >/dev/null 2>&1; then
    local fopts
    fopts=$(green_fzf_opts)
    # shellcheck disable=SC2086
    sel=$(printf '%s\n' "${opts[@]}" | fzf --prompt="${prompt} " --height=40% --reverse $fopts) || {
      local ec=$?
      if (( ec == 130 || ec == 1 )); then exit 130; fi
      exit "$ec"
    }
    printf '%s\n' "$sel"
    return 0
  fi

  # numbered menu on stderr; read from /dev/tty
  printf '%s›%s %s\n' "${UI_C-}" "${UI_Z-}" "$prompt" >&2
  for i in "${!opts[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${opts[i]}" >&2
  done
  printf 'Choice [1]: ' >&2
  if ! read -r n </dev/tty; then
    exit 130
  fi
  # cancel / empty → default 1; bare empty is default not cancel
  # Ctrl-D already handled. Empty → 1.
  if [[ -z ${n-} ]]; then
    n=1
  fi
  # cancel keywords
  if [[ $n == q || $n == Q || $n == cancel ]]; then
    exit 130
  fi
  if ! [[ $n =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#opts[@]} )); then
    exit 130
  fi
  printf '%s\n' "${opts[n - 1]}"
}

# ---------------------------------------------------------------------------
# green_fzf_opts → theme string (stdout)
# ---------------------------------------------------------------------------
green_fzf_opts() {
  if [[ ${GREEN_UI_MODE-none} == none ]] || [[ -n ${NO_COLOR-} ]]; then
    printf '%s\n' '--no-color --no-bold'
    return 0
  fi
  # accent-based fzf 0.72 theme; moss green default accent
  local acc=${GREEN_UI_ACCENT-108}
  local border pointer
  if [[ "$acc" == *";"* ]]; then
    border="#87af5f"
    pointer="#87af5f"
  else
    # use 256 index form for fzf
    border="$acc"
    pointer="$acc"
  fi
  # Prefer hex moss when default
  if [[ $acc == 108 ]]; then
    border="#87af5f"
    pointer="#87af5f"
  fi
  printf '%s\n' "--pointer='▶' --marker='✓' --prompt='❯ ' --color=pointer:${pointer},marker:114,prompt:75,border:${border},hl:75,hl+:80,fg+:15,bg+:236"
}

# ---------------------------------------------------------------------------
# ui_cleanup — restore cursor + SGR on stderr; idempotent
# ---------------------------------------------------------------------------
ui_cleanup() {
  printf '\e[?25h\e[0m' >&2 2>/dev/null || true
  return 0
}
