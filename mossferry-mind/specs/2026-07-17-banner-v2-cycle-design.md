# responsive banner v2 + cyclic picker — design spec

**Date:** 2026-07-17 · **Status:** approved · **Version target:** 2.4.0
**Supersedes:** the §The art and width/height rules of `2026-07-17-picker-banner-design.md`. Everything else there still binds.

## Problem
Two picker refinements: (1) list navigation should wrap — pressing down on the last row lands on the first and vice versa ("infinite scroll"); (2) the banner should be more polished and **width-responsive**: a horizontal boat-plus-wordmark lockup when the pane is wide, the boat alone at medium width, the one-liner when cramped.

## Cyclic scroll
Add `--cycle` to ALL THREE fzf invocations in `bin/repo-session` (main session picker and both new-session sub-picker calls). No other flag changes.

## The art (canonical — byte-exact when ANSI codes are stripped)

WIDE lockup (6 lines, 51 cols):

```
           |>
         __|__               __
      __|_o_o_|__           / _|___ _ _ _ _ _  _
    _|___________|_        |  _/ -_) '_| '_| || |
   \   o   o   o   /       |_| \___|_| |_|  \_, |
 ~~~\_____________/~~~~~~~~~~~~~~~~~~~~~~~~ |__/ ~~
```

MEDIUM liner (6 lines, 22 cols):

```
           |>
         __|__
      __|_o_o_|__
    _|___________|_
   \   mossferry   /
 ~~~\_____________/~~~
```

SMALL (1 line): `⛴ mossferry`

Colors (ANSI, reset `\033[0m` properly): flag `|>` bright green `\033[1;32m`; boat structure (mast, cabin, deck, hull) regular green `\033[32m`; the name `mossferry` (medium) and the figlet lettering (wide) bright green `\033[1;32m`; portholes `o` and waves dim green `\033[2;32m`.

## Behavior

**`ferry_banner [width]`** (both copies: `bin/repo-session` LIB-exported, `bin/mossferry` keep-in-sync duplicate) — optional arg = available display columns; default `${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}`. Rows detection unchanged: `rows=${LINES:-$(tput lines 2>/dev/null || echo 24)}`. Tier selection:
1. `FERRY_BANNER` = `off`/`0` → nothing, exit 0.
2. rows < 18 → SMALL.
3. width ≥ 52 → WIDE.
4. width ≥ 24 → MEDIUM.
5. else → SMALL.

**Callers** — the MAIN picker passes `width = 40% of terminal cols` (its header lives left of the `right:60%` preview). The sub-picker, no-fzf fallback menu, and both `--help`s pass no arg (full width). No caller changes beyond that.

## Acceptance
- t26 (updated): `LINES=30 ferry_banner 40` → 6 lines; ANSI-stripped equals MEDIUM byte-for-byte.
- t33: `LINES=30 ferry_banner 100` → 6 lines; ANSI-stripped equals WIDE byte-for-byte (figlet lettering present).
- t34: `LINES=30 ferry_banner 20` → exactly 1 line containing `⛴ mossferry` (narrow width wins even when tall).
- t27/t28 (existing semantics): short rows → SMALL; `FERRY_BANNER=off`/`0` → empty, exit 0.
- t35: `grep -c -- '--cycle' bin/repo-session` = 3 (all fzf calls wrap).
- m16 (updated): `mossferry --help` contains the new MEDIUM hull line after ANSI strip.
- ONLY t26, t27, t28, m16 may be updated (the art contract changed); all other existing assertions (t1–t25, t29–t32, m1–m15, install) unmodified and green.
- README: art block updated to the WIDE lockup.
- Manual checklist (user): wide pane shows the lockup, grid pane shows liner or ⛴ line, picker arrows wrap last↔first.
