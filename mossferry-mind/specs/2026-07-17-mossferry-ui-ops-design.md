# mossferry ops-surface polish — design spec

**Date:** 2026-07-17 · **Status:** approved · **Version target:** 2.5.0 · **Phase:** 2 of the fleet UI campaign
**Inputs (binding):** the mossferry section of `~/.cache/armory-research/UPGRADE-BRIEF.md`, `~/.cache/armory-research/repos/mossferry-ui-audit.md`, `~/.cache/armory-research/PLAYBOOK.md`, GREEN-UI-KIT (`~/Repositories/green-ui-kit/README.md`).

## Problem
The picker/banner are brand-grade; the ops surfaces (`doctor`, `update`, `install.sh`, validate errors, help body) are monochrome unit-test chrome, help lags shipped features, and error prefixes drift (`mossferry:` / `repo-session:` / bare).

## Kit consumption — VENDORED (fleet precedent for cross-machine tools)
mossferry runs on BOTH machines (Mac client + Manjaro remote), so it vendors a pinned copy: commit `lib/green-ui.sh` (copied verbatim from green-ui-kit 0.1.0; header comment noting source+version). `git pull` = both machines get it.

**THE SYMLINK LESSON (an armory child broke production today missing this):** `bin/mossferry` and `bin/repo-session` are invoked via `~/.local/bin` symlinks. Any script-relative path MUST resolve symlinks first: `ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"`. On macOS `readlink -f` needs a fallback (greadlink may be absent): use a small resolver loop (`while [ -L ... ]`) — it must work on stock macOS bash 3.2 AND Linux. Source guard: `[[ -r "$ROOT/lib/green-ui.sh" ]] && source ... || <plain no-op fallbacks>` — missing lib must NEVER kill the tool.

## The parse-token law (breaks = failed task)
Machine-parsed/test-asserted tokens stay byte-identical in non-TTY output: `ok versions match: <v>`, `FAIL`, `info`, `local <v> / remote <v>`, validate error text + exit 1, `--list` row format, exit codes 0/1/130. ALL new color/chrome is TTY-gated via the kit (tests run non-TTY → existing t1–t35, m1–m16, install assertions stay green and UNMODIFIED; only additive test changes allowed).

## Features
1. **`ferry doctor`** — small banner (⛴ one-liner tier), kit checklist glyphs (✓ green / ✗ red / dim info per line), end summary line, and on any FAIL a dim fix-hint line (e.g. suggest `ferry update` on version mismatch).
2. **`ferry update`** — step-checklist chrome for the crossing (local pull → remote pull → verify), finale strip `local 2.5.0 ~~~⛴~~~ remote 2.5.0` — waves green on match, red on divergence. Raw git output dimmed, not removed.
3. **Help** — sectioned layout (Usage / Picker keys / Flags / Config / Examples) with launcher keys (ctrl-a/ctrl-g), --cycle wrap, esc documented; version footer (`mossferry <VERSION> · the green ferry between your machines`). Both `mossferry --help` and `repo-session --help`.
4. **Unified error chrome** — every error line starts `mossferry:` (client) or `repo-session:` (remote) with red ✗ when TTY; validate typo error keeps exact text/exit but adds (TTY-only) a dim capped repo list and a `did you mean <closest>?` hint (simple prefix/substring closest-match is fine).
5. **`install.sh`** — MEDIUM hull banner, ✓ per step, final ready card (panel: linked commands, config path, next steps), PATH warning check preserved.

## Acceptance
- f1: non-TTY `ferry doctor` output byte-compatible tokens (`ok versions match:`), zero ANSI; forced-TTY shows glyph checklist + summary.
- f2: non-TTY `ferry update` still ends `local <v> / remote <v>`; forced-TTY shows steps + wave strip.
- f3: `--help` contains ctrl-a, ctrl-g, --cycle, version footer; sections present.
- f4: validate error keeps exact current message + exit 1; forced-TTY adds did-you-mean for a 1-char typo fixture.
- f5: `bash install.sh` in a sandbox HOME prints ready card, symlinks correct (existing install tests green).
- f6: kit-absent (lib file removed in a copy) → all commands still work, plain output.
- f7: both bins pass `bash -n`; suite green: t1–t35, m1–m16, install + new f-tests; personal-path grep empty.
- README: ops screens section updated; VERSION 2.5.0.
