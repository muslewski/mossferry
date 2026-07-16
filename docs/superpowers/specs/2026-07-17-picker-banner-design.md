# picker banner (ASCII art) — design spec

**Date:** 2026-07-17 · **Status:** approved · **Version target:** 2.2.0

## Problem
The picker is mossferry's face, but it opens as a bare list. The brand — a green ferry — should greet the user: ASCII art in the top-left corner of the picker (and the local `--help`).

## The art (canonical — byte-exact when ANSI codes are stripped)

Full banner (4 lines):

```
        __|__
   ____|_____|____
   \  mossferry  /
 ~~~\___________/~~~
```

Small variant (1 line): `⛴ mossferry`

Colors (ANSI): the name `mossferry` bright green `\033[1;32m`, hull/cabin regular green `\033[32m`, waves dim green `\033[2;32m`, always reset `\033[0m`. Small variant: green name, reset after.

## Behavior

**`ferry_banner` function** — added to `bin/repo-session` (LIB-exported) and duplicated in `bin/mossferry` (comment on each: keep in sync with the other; deliberate — both scripts stay self-contained). Decides its output from `rows=${LINES:-$(tput lines 2>/dev/null || echo 24)}`:
- `FERRY_BANNER` is `off` or `0` → prints nothing, exit 0.
- rows ≥ 18 → full banner.
- rows < 18 → small variant (grid panes are short; never eat the list).

**Picker placement** — every picker fzf invocation in `bin/repo-session` (main session picker AND the new-session repo sub-picker) gains `--layout=reverse --header-first`, so the header sits at the very top and the list flows downward. The main picker's `--header` becomes banner-lines + the existing keybind-hints line (multi-line header string); the sub-picker's header is the banner alone. When the banner is empty (off), headers degrade to exactly today's content (hints line for the main picker, no `--header` for the sub-picker).

**No-fzf fallback menu** — banner printed above the numbered menu on each loop iteration.

**`--help`** — both `mossferry --help` and `repo-session --help` print the banner above usage.

**Config** — new key `FERRY_BANNER="on"` in `config.example` (env > file > default, like all FERRY_* keys). Any value other than `off`/`0` means on.

## Acceptance
- t26 (LIB): `LINES=30 ferry_banner` → 4 lines; stripped of ANSI escapes, equals the canonical art byte-for-byte.
- t27 (LIB): `LINES=10 ferry_banner` → exactly 1 line containing `⛴ mossferry`.
- t28 (LIB): `FERRY_BANNER=off` (and `=0`) → empty stdout, exit 0, regardless of LINES.
- m16: `mossferry --help` stdout contains the hull line (`\  mossferry  /` after ANSI strip) plus existing usage text.
- Existing t1–t25, m1–m15, install tests: green, assertions unmodified.
- README: canonical art in a code block near the top; picker section notes the banner; `FERRY_BANNER` documented.
- Manual checklist (user): banner renders green top-left in a real picker; short grid panes show the ⛴ line; `FERRY_BANNER=off` hides it; reverse layout feels right.
