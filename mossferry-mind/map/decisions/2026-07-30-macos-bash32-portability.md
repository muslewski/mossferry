---
type: decision
summary: "Support macOS stock bash 3.2 as a first-class client: resolve tmux from PATH, drop mapfile/associative arrays, guard empty-array expansions, shim flock, and fence all of it statically."
status: active
date: 2026-07-30
tags: [macos, bash32, portability, client, repo-session, tests, dogfood]
related:
  - "[[client]]"
  - "[[repo-session]]"
  - "[[tests]]"
  - "[[green-ui]]"
  - "[[install-config]]"
---

# macOS stock bash 3.2 is a supported client platform

## Context

The human drives mossferry from a MacBook against a Manjaro host. On the Mac the
tool failed outright with the error they reported:

```
zsh: no such file or directory: /usr/bin/tmux
```

The Linux suite was green the whole time. Verified on the real machine over ssh
(Darwin 25.5.0 arm64, MacBook Air):

| Fact | Value |
|---|---|
| `/bin/bash` | **3.2.57 — the only bash installed**, no Homebrew bash |
| absent | `tmux`, `fzf`, `flock`, `ss`, `/proc`, `timeout`, `gtimeout` |
| present | `mosh` 1.4.0, `node`, `npm`, `brew` under `/opt/homebrew` |
| `/tmp` | symlink to `private/tmp` |

Three of the seven test modules were failing or **not even parsing** on that Mac
while the same suite passed on Linux. `tests/test-repo-session.sh` — 54
assertions, the largest module — died at parse time and had therefore *never* run
on macOS.

## Decision

Treat macOS stock bash 3.2 + BSD userland as a **supported client platform**,
enforced by a static fence rather than by hoping.

1. **Resolve platform-moving tools from PATH, never absolutely.**
   `TMUXBIN` was `${REPO_SESSION_TMUXBIN:-/usr/bin/tmux}`; tmux is never at that
   path on macOS. Resolve via `command -v` with the absolute path only as a last
   resort, and preflight with an actionable message naming
   `REPO_SESSION_TMUXBIN` and `brew install tmux`.

2. **The preflight must not fire for verbs that do not need tmux.** Requiring it
   for everything except `--help`/`--servers` broke `--picker-face-header`, a bare
   `printf`. The servers face and face header are exempt; the two face-dependent
   verbs require tmux only on their sessions branch. A laptop with no tmux can now
   browse the servers face while attach still refuses correctly.

3. **No bash-4-only syntax in shipped shell.** `mapfile` became `while IFS= read`
   loops; `local -A` in `lib/servers.sh` became parallel indexed arrays with
   deterministic ordering.

4. **Guard every array expansion.** In bash 3.2, `"${arr[@]}"` on an *empty* array
   under `set -u` is an unbound-variable error; bash 4.4+ allows it. The portable
   form is `${arr[@]+"${arr[@]}"}` — the inner quotes must stay, or elements with
   spaces word-split. This is what actually killed the picker after (3) landed:

   ```
   line 789: names[@]: unbound variable
   line 1523: rows[@]: unbound variable
   ```

   Note bash reports the **function declaration** line, not the expansion line.

5. **Shim `flock`.** It is Linux util-linux only. Previously `exec 9>…; flock 9`
   printed "command not found" on macOS and, with `set -u` and no `set -e`, the
   script **continued unlocked** — a silent race in the claim/create path. Now:
   `flock` when present, otherwise an atomic `mkdir` mutex with PID-liveness stale
   recovery and a bounded 30 s wait, releasing on signal. Never proceed unlocked.

6. **Capability checks, not `uname`.** The servers view needs `ss` + `/proc`, so
   it degrades with one explicit stderr notice instead of returning an empty list
   that reads as "no servers running". PID liveness, by contrast, does *not* need
   `/proc` — `servers_scan_agents` now uses signal 0 (`process.kill(pid, 0)`,
   EPERM counts as alive) and works everywhere.

7. **A static fence, `tests/test-macos-compat.sh`.** 32 assertions over
   `bin/*`, `lib/*.sh`, `install.sh`: no bash-4 constructs, no unconditional
   absolute tool paths, no unguarded `flock`, no unguarded GNU-only flag forms, no
   unguarded `${arr[@]}`, and every `source` target inside `bin/*` present in
   `package.json` `files`. It needs no Mac, no network, and no tmux. Deliberate
   exceptions carry a trailing `# portable-ok: <reason>`; the patterns are never
   loosened. The fence is quote- and comment-aware, so a tool name mentioned in a
   comment or inside a message string is not read as a call.

## Consequences

- Real macOS, with the user's normal PATH: `tests/run.sh` **exit 0**, all 7
  modules exit 0, `test-servers` 30 passed / 0 failed. Linux stays exit 0.
- `test-repo-session.sh` runs on macOS for the first time: **54/54**, including
  the `t7`/`t12` cases that the empty-array bug had been failing.
- Two test-harness portability bugs were fixed as part of this, both pre-existing:
  a heredoc inside `$( )` (a bash 3.2 parse error — use
  `IFS= read -r -d '' var <<'EOF'` and strip the trailing newline), and
  `readlink -f` compared against a logical `ROOT`, which fails on macOS because
  `/tmp` is a symlink. Resolve both sides with `pwd -P`.
- The fence scans shipped shell only, **not `tests/`** — which is exactly why a
  `timeout 8` call inside `test-ui-ops.sh` survived and failed with rc=127 on every
  Mac. Extending the fence over `tests/` is open tech-debt.
- `lib/green-ui.sh` still self-describes as "bash >= 4" in its header even though
  its expansions are now guarded; the UI degrades rather than dying.

## Why not `uname`-based branching

Capability checks describe what the code actually needs and keep the fixture-driven
tests meaningful (`FERRY_SERVERS_SS_FIXTURE` is itself a capability). A `uname`
branch would guess, and would have to be re-guessed for every new platform.

## Evidence

Verified by copying the tree to `/tmp` on the real MacBook over ssh and running
the suite under `/bin/bash` 3.2.57, comparing every failure against the pre-lane
baseline commit to separate regressions from pre-existing breakage. One regression
was found that way — the tmux preflight over-firing — and fixed before merge.
One caveat worth remembering: `node` is absent from a non-interactive ssh PATH on
that Mac (it lives at `/opt/homebrew/bin`, added by `.zshrc`), so a suite run over
plain ssh reports one spurious `servers_scan_agents` failure. Export the real PATH
before judging the result.
