---
title: "Troubleshooting, doctor, and the test harness"
description: "Symptom fixes with literal messages, full ferry doctor behaviour, and contributor rules for the Bash test suite."
section: guide
order: 50
---

# Troubleshooting, doctor, and the test harness

**mossferry** hops you into a remote repo’s tmux session. When something fails, the messages below are the ones the binaries actually print. Every line was reproduced with `./bin/mossferry` / `./bin/repo-session` (or the suite under `tests/`).

## Happy path when something is wrong

```sh
ferry doctor workstation          # read-only; exit 1 if any FAIL
# fix every FAIL line, then:
ferry workstation                 # hop + picker
ferry workstation my-app -p       # attach/create primary for my-app
bash tests/run.sh                 # contributors: local suite (no hosted CI)
```

Non-TTY doctor lines use stable tokens: `ok …`, `FAIL …`, `info …`. Exit **1** if any check is `FAIL`, or if no host can be resolved.

---

## By symptom

### No host configured

```text
mossferry: doctor: no host (pass one, or set FERRY_HOST_CANDIDATES / FERRY_DEFAULT_HOST)
```

Bare `ferry` with no default prints **usage on stderr** and exits **1**.

**Fix:** pass a host (`ferry doctor workstation`) or set `FERRY_DEFAULT_HOST` / `FERRY_HOST_CANDIDATES` in `~/.config/mossferry/config`. Host names are ssh config aliases, not hard-coded IPs.

### ssh cannot connect (passwordless)

Doctor:

```text
FAIL ssh BatchMode connect to workstation
```

After a connect FAIL, doctor prints a skip line and still emits the remote FAIL/info tokens **without** opening further ssh sessions (so it always terminates):

```text
info remote checks skipped — ssh BatchMode connect failed
FAIL remote .local/bin/repo-session not executable
FAIL versions: local 2.7.4 / remote unknown
```

Observed exit: **1**. Every remote-connecting probe uses `BatchMode=yes` and `ConnectTimeout=5`.

**Fix:** make `ssh -o BatchMode=yes -o ConnectTimeout=5 workstation true` work without a password prompt (keys + `~/.ssh/config`).

### Local mosh missing

Doctor (PATH with no `mosh` binary):

```text
FAIL local mosh binary missing
```

This is always checked, **even when** `FERRY_TRANSPORT=ssh`.

**Fix:**

- Install `mosh` on the laptop if you want the default transport, **or**
- Set `FERRY_TRANSPORT=ssh` for interactive hops (clipboard-friendly), and still install mosh if you want doctor fully green — today doctor will keep FAILing without a local mosh.

Interactive hop with default transport and a broken mosh client surfaces the real mosh process error (example observed here: `Died at …/mosh line …`) and a nonzero exit. There is no separate mossferry framing message around that failure yet.

### Prefer ssh instead of mosh (no mosh roam)

```sh
# ~/.config/mossferry/config  or one-shot env
FERRY_TRANSPORT=ssh
ferry workstation
```

Doctor then reports:

```text
info FERRY_TRANSPORT=ssh (interactive; better OSC 52 with wrap, no mosh roam)
```

Invalid value (observed with `FERRY_TRANSPORT=pigeon`):

```text
FAIL FERRY_TRANSPORT=pigeon (want mosh|ssh)
```

Hop:

```text
mossferry: unknown FERRY_TRANSPORT='pigeon' (want mosh|ssh)
```

Exit **1**.

### `…/tmux: No such file or directory` (exit 127) — host **or** laptop

`repo-session` resolves tmux as `REPO_SESSION_TMUXBIN` if set, otherwise a platform path (historically a bare `/usr/bin/tmux` default). The same shell message appears in two places:

| Where you see it | Meaning | Fix |
|------------------|---------|-----|
| **Host** (normal `ferry` hop → remote `repo-session`) | Host has no tmux (or wrong path) | Install tmux on the **host**; or set `REPO_SESSION_TMUXBIN` to the real binary on that machine |
| **Laptop** (you ran `repo-session` / a symlink **locally**, e.g. Mac without Homebrew tmux) | Local tmux path did not resolve | Install tmux on the laptop **or** export `REPO_SESSION_TMUXBIN=$(command -v tmux)` after `brew install tmux`. Ordinary laptop-only `ferry` hops do **not** need local tmux — only the host does |

| Action | Observed when the binary is missing |
|--------|-------------------------------------|
| `--list` | `no tmux sessions running` on stdout, exit **0** (list-sessions fails quietly) — misleading “empty”, not a hard error |
| `my-app -p` / attach | Shell errors like `…/tmux: No such file or directory` or `zsh: no such file or directory: /usr/bin/tmux`, exit **127** |

**Doctor:** remote tmux presence is part of the intended doctor surface (so a host cannot “pass doctor” and then fail only at attach). If your installed client is older than that check, treat a green doctor as **not** proof of remote tmux until you upgrade both sides — see [macOS client](#macos-client) and [versions](#client-and-remote-versions-differ).

### Dropped link and reattach

| Transport | Dropped network | What you do |
|-----------|-----------------|-------------|
| **mosh** (default) | Client may reconnect without a new login until `FERRY_SERVER_TIMEOUT` clientless seconds (default `86400`) | Wait; if the hop is gone, re-run `ferry …` |
| **ssh** | Client ends immediately | Re-run `ferry …` |

In both cases the **remote tmux session keeps running**. Detach deliberately with tmux (stock: `Ctrl-b` then `d`). Reattach with the same command you used before (`ferry workstation`, `ferry workstation my-app -p`, or pick the session in the picker). Ferry does not redefine tmux keys.

Reattach is ordinary `tmux attach`. Multiple clients can attach to the same session (tmux multi-attach). `--primary` on an existing session **attaches only** — it does **not** re-send the start command.

### Repository name rejected

Shape gate (`_ferry_repo_token_ok`): letters, digits, `.`, `_`, `-` only; no `/`, `\`, `..`, spaces, empty.

```text
repo-session: invalid repo name '../escape'
repo-session: invalid repo name 'foo/bar'
repo-session: invalid repo name 'with space'
```

The **laptop client** prints the same line and exits **1** with no ssh when the token fails the shape gate (observed: `ferry workstation 'has space'` → `invalid repo name 'has space'`, empty transport log). The **host** `repo-session --validate` uses the same rule.

Missing basename under `FERRY_REPO_BASE` (default `~/Repositories`) still needs a live host (ssh pre-validate):

```text
repo-session: no repo 'missing-app' under /path/to/Repositories — pick one below, or run 'ferry <host>' to browse all sessions
  good-app
```

Exit **1**. On a TTY, a capped list and optional `did you mean …?` may follow. Non-TTY lists basenames with two-space indent.

Details: [Quoting and containment](./quoting-and-containment.md).

### Session already exists (`--primary` / picker)

`repo-session my-app -p` when `my-app` is already a live session:

1. `has-session` succeeds  
2. **attach only** (no `new-session`, no `send-keys`)

Observed argv against the test stub: `has-session -t demo-app` then `attach -t demo-app`. The pane’s existing process is left alone. Start flags (`--claude`, `-- cmd`) apply only when a session is **created**.

Picker enter on an existing row is the same: `tmux attach -t =name`.

### Stale or closed session / wrong name

Direct resume of a name that is not live:

```text
no session named already-here. available:
  demo-app
```

Bad index:

```text
no session #999. available:
  1) …
```

Exit **1**. List what is live with `ferry workstation --list` or `repo-session --list`, then attach a real name or use `--primary` to create.

Grid claim with nothing left (`--resume-closed`):

```text
no demo sessions left to resume — blank shell
```

then `exec` of a login shell. `--resume-or-new` creates the next free `repo` / `repo-N` instead of a blank shell when nothing is claimable.

### Client and remote versions differ

Every hop prepends `--client-version <local VERSION>`. Mismatch (warn only — hop continues):

```text
mossferry: client 2.7.4 / remote 2.7.5 — run 'ferry update'
```

Picker header can show the same idea as a nudge line (`↑ update  client … · remote …  →  ferry update`).

Doctor on mismatch (exit **1**):

```text
FAIL versions: local 2.7.4 / remote 9.9.9
```

On a TTY, a fix hint may appear: `run: ferry update <host>`.

**What `ferry update` actually does** (from `cmd_update` in `bin/mossferry`):

1. Resolve a host (CLI arg, else `FERRY_HOST_CANDIDATES` / `FERRY_DEFAULT_HOST`).
2. `git pull --ff-only` in the **local** mossferry clone (`REPO_ROOT` next to the running binary).
3. Over ssh: `git -C $FERRY_REMOTE_REPO pull --ff-only` when the remote checkout has an upstream; if the remote is a **canonical** checkout with no remotes/upstream, pull is **skipped** (message on stdout) and versions are still printed.
4. Print `local <v> / remote <v>` from each side’s `VERSION` file.

It does **not** run `npm install`. If either side was installed only with `npm install -g mossferry` and there is no git checkout at `REPO_ROOT` / `FERRY_REMOTE_REPO`, use npm on that side:

```sh
# laptop (npm-global)
npm install -g mossferry@latest
# host (ssh), same idea — or maintain a git clone at FERRY_REMOTE_REPO and use ferry update
```

For clone + `./install.sh` deploys (symlinks into the repo), `ferry update workstation` is the intended both-ends pull. Re-run `ferry doctor workstation` until versions match.

**BOM / whitespace tolerance (important):**

| Path | What it strips before compare |
|------|-------------------------------|
| `ferry doctor` / `ferry update` remote `VERSION` | Leading UTF-8 BOM (`EF BB BF`), CR/LF, and whitespace |
| Runtime `--client-version` handshake in `repo-session` | Only whitespace via `tr -d '[:space:]'` — **not** a BOM |

Observed: remote `VERSION` file `﻿2.7.4` (BOM + `2.7.4`) made doctor report `ok versions match: 2.7.4`, while the same bytes on hop printed:

```text
mossferry: client 2.7.4 / remote ﻿2.7.4 — run 'ferry update'
```

So matching package versions can still look different at hop time if a BOM survived into the remote `VERSION` file. Re-write `VERSION` without a BOM, or run `ferry update` after both checkouts agree.

### Remote `repo-session` missing or not executable

```text
FAIL remote .local/bin/repo-session not executable
```

**Fix:** install mossferry on the host (`npm install -g mossferry` or clone + `./install.sh`) so `~/.local/bin/repo-session` (or your `FERRY_REMOTE_BIN`) is executable.

### Remote fzf missing

```text
info remote fzf missing — numbered menu fallback available
```

Info only — does not fail doctor. Host falls back to a numbered menu.

### grok wrap

| Situation | Line |
|-----------|------|
| `FERRY_WRAP=auto` and `grok wrap` works | `ok local grok wrap available (FERRY_WRAP=auto)` |
| auto and no grok | `info grok not on PATH — interactive ferry will not use grok wrap (install Grok CLI on this machine)` |
| wrap forced on and no grok | `FAIL FERRY_WRAP=on but grok not on PATH (…)` |

Wrap applies only to interactive mosh/ssh hops, never to `--list` / doctor / update.

---

## `ferry doctor` (full)

```sh
ferry doctor [host]
```

Read-only health. Resolves host like bare `ferry`: CLI host → first reachable `FERRY_HOST_CANDIDATES` → `FERRY_DEFAULT_HOST`.

There is **no** `doctor --help` and **no** `doctor --json`. Extra tokens are treated as the **host name** (so `ferry doctor --json` tries to diagnose a host literally named `--json`).

### Checks (in order)

| # | Kind | Message shape (non-TTY) | Fails exit? |
|---|------|-------------------------|-------------|
| 1 | ok / info | `ok config readable: ~/.config/mossferry/config` or `info config absent — defaults in use` | no |
| 2 | ok / FAIL | `ok ssh config resolves host <h>` / `FAIL ssh config does not resolve host <h>` | FAIL → yes |
| 3 | ok / FAIL | `ok ssh BatchMode connect to <h>` / `FAIL ssh BatchMode connect to <h>` (`ConnectTimeout=5`) | FAIL → yes |
| 4 | ok / FAIL | `ok local mosh binary` / `FAIL local mosh binary missing` | FAIL → yes |
| 4b | ok / info / FAIL | grok wrap vs `FERRY_WRAP` (see table above) | FAIL only if wrap forced on and missing |
| 4c | info / FAIL | transport preference (`mosh` default or `ssh`) / bad value | FAIL → yes |
| 5 | ok / FAIL | `ok remote <FERRY_REMOTE_BIN> executable` / `FAIL remote … not executable` | FAIL → yes |
| 6 | ok / FAIL | `ok versions match: <v>` / `FAIL versions: local <v> / remote <v\|unknown>` | FAIL → yes |
| 7 | ok / info | remote fzf present / numbered menu fallback | no |
| 8 | info | `info remote mosh-server count: <n>` | no |
| 9 | info | MagicDNS / HostName note | no |
| 10 | info | Mac-reachable host (`preview-host` if on PATH), reserved ports, servers summary | no |

Servers summary example:

```text
info servers: 0 LISTEN · 0 declared-missing · 0 foreign
```

Discovery errors never flip doctor to FAIL by themselves (`servers: (unavailable — …)` is still info).

### Exit behaviour

| Condition | Exit |
|-----------|------|
| No host resolved | **1** + `mossferry: doctor: no host …` |
| Any check emitted `FAIL` | **1** |
| No `FAIL` lines | **0** |

`info` never changes the exit code. On a TTY, doctor may print a one-line banner, glyphs, a summary (`N checks · all ok` / `N checks · some failed`), and version fix hints.

### What doctor does **not** do

These gaps are real behaviour, not future promises:

| Expectation (fleet / plan shape) | Actual today |
|----------------------------------|--------------|
| **Broken / suboptimal tiers** | Only `ok` / `FAIL` / `info`. Soft issues (no fzf, mosh-server count) are info; many connectivity issues are hard FAIL. |
| **Nonzero only on hard failure** | Exit **1** on **any** `FAIL`, including local mosh missing under `FERRY_TRANSPORT=ssh` and version skew (hop would still work with a warning). |
| **`--json` machine output** | **Not implemented.** `ferry doctor --json` is not JSON — `--json` becomes the host token. |
| **Remote probes after connect fail** | **Skipped** (no further ssh). Emits `info remote checks skipped — …` plus the usual remote FAIL/info lines; exit stays **1**. |
| **Remote tmux present** | **Intended check** on current main: doctor should surface missing remote tmux so attach is not the first failure. Older published clients may still omit this line — upgrade both ends if doctor never mentions tmux. |
| **BOM-safe version on hop** | Doctor strips BOM for VERSION compare; the live `--client-version` handshake does not (see [versions](#client-and-remote-versions-differ)). |
| **Ship policy / “safe to ship”** | Not a doctor surface. See [Quoting and containment](./quoting-and-containment.md) honest-status gaps. |

Related: [Getting started](./getting-started.md), [Command reference](./command-reference.md), [Configuration](./configuration.md).

---

## macOS client

Mac laptops are a first-class **client** (type `ferry` → mosh/ssh → host). The long-running work still lives on the **host**. Measured ground truth on stock Darwin: `/bin/bash` is **3.2.x**, Homebrew tools land under `/opt/homebrew`, and Linux-only utilities (`flock`, `ss`, `/proc`) are absent.

### Install (laptop)

```sh
brew install mosh
npm install -g mossferry
# or: clone + ./install.sh  (symlinks into the clone; ferry update can git-pull)
ferry --help
ferry doctor <host>
```

| Tool | Laptop? | Why |
|------|---------|-----|
| `mosh` | **Yes** (default transport) | `bin/mossferry` launches `mosh`; doctor FAILs on missing local mosh even if you later set `FERRY_TRANSPORT=ssh` |
| `ssh` | Yes | Always used for `--list`, pre-validate, doctor remote probes, and `FERRY_TRANSPORT=ssh` |
| `fzf` | **No** (for normal hops) | Picker runs **on the host** inside `repo-session` |
| `tmux` | **No** (for normal hops) | All `tmux` calls are remote; brew-install tmux only if you run `repo-session` on the Mac |
| `flock` | No | Linux util-linux; claim locks are a host concern |

### Known limitations

- **Stock bash 3.2.** `lib/green-ui.sh` self-describes as a bash **≥4** UI library. The client loads it with a **fallback** when sourcing fails or the kit is missing (`_ferry_ui_fallbacks` in `bin/mossferry` / `bin/repo-session`) — chrome may degrade to plain ASCII tokens; hops still work.
- **No `flock` on macOS.** Session claim locking lives in host-side `repo-session`. A Mac used only as a laptop client is fine; a Mac used as the **host** needs a portable lock path (or Linux).
- **Servers view is host-only.** `lib/servers.sh` discovers listeners with Linux **`ss`** and **`/proc`**. Run `ferry <host> --list-servers` or open the picker servers face **on the host**; do not expect full discovery from a bare Mac userland without those interfaces.
- **Version skew.** A laptop on an older npm release (e.g. 2.7.3) against a host on 2.8.0 will doctor-FAIL and warn on hop. Sync with the real [update procedure](#client-and-remote-versions-differ) — `ferry update` for clone deploys, `npm install -g mossferry@latest` when you installed via npm.

Contributor regression fence: `tests/test-macos-compat.sh` (static; no Mac required).

---

## Test harness (contributors)

There is **no hosted CI** for this project. Verification is local.

### How to run

```sh
bash tests/run.sh
# same modules, second time with a minimal PATH — see below
PATH=/usr/bin:/bin:/usr/local/bin bash tests/run.sh
```

`tests/run.sh` runs every `tests/test-*.sh` and exits **1** if any module fails. There is no bats/shellcheck dependency; the suite is plain Bash.

| Module | Covers |
|--------|--------|
| `test-mossferry.sh` | Client launch, quoting of remote argv, doctor/update contracts with fakes |
| `test-repo-session.sh` | Validate, list, claim, picker helpers, token rules |
| `test-install.sh` | `install.sh` layout and config seed |
| `test-ui-ops.sh` | Non-TTY tokens vs TTY chrome for doctor/update/help/validate |
| `test-fleet-devlog.sh` | Opt-in fleet-devlog emitter, `repo_id`, hermetic XDG |
| `test-servers.sh` | Servers-view pure functions + fixtures (no live listeners required) |
| `test-macos-compat.sh` | Static portable-shell fence (bash 3.2 / BSD / no bare `/usr/bin/tmux`) — no Mac required |
| `test-servers.sh` | `lib/servers.sh` fixtures, fix plans, hermetic `--servers` |

### Fakes

| Path | Role |
|------|------|
| `tests/fake-bin/ssh` | Logs argv to `FAKE_NET_LOG`; answers BatchMode `true`, `--validate`, `cat …/VERSION`, git pull probes |
| `tests/fake-bin/mosh` | Logs argv; does not open a real mosh session |
| `tests/fake-bin/grok` | Satisfies wrap probes |
| `tests/fake-tmux` | Stub `tmux` driven by `FAKE_TMUX_SESSIONS` / `FAKE_TMUX_META` / `FAKE_TMUX_LOG` |

Tests put `tests/fake-bin` **first** on `PATH` and set `REPO_SESSION_TMUXBIN` to `tests/fake-tmux` where needed so the verdict does not depend on the developer’s real ssh/mosh/tmux.

### Rule 1 — a skip must never read as a pass

If a case cannot run because an optional dependency is missing, it must print a **visible** skip with a reason, and the module summary must show skips separately from passes.

Pattern (from `tests/test-fleet-devlog.sh`):

```bash
ok()   { printf 'ok %s\n' "$1"; }
FAIL() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
SKIP() { printf 'SKIP %s\n' "$1"; skip=$((skip + 1)); }
HARNESS_FAIL() { FAIL "harness: $1"; }   # tooling/env, not product
```

End of module:

```text
tests/test-fleet-devlog.sh: all ok (1 skip(s))
```

Observed skip line when the optional JS dual-source is unset:

```text
SKIP repo-id-matches-js-tool (FLEET_REPO_ID_JS unset; set to a resolveRepoId module to enable)
```

`tests/test-servers.sh` uses a similar visible skip for live-only integration:

```text
  SKIP --picker-servers-rows (no listeners / empty host — integration)
```

**Do not** write:

```bash
# wrong — silent pass when dependency missing
command -v node >/dev/null && assert_js || true
# wrong — missing tool becomes a fake green product assertion
node -e '…' 2>/dev/null || echo parse-fail   # then compare as product output
```

Harness problems use `FAIL harness: …` / `HARNESS_FAIL` so they never look like a product assertion.

### Rule 2 — the verdict must not depend on the developer’s PATH

A test that is green only because a tool is **missing** (or only because a desk-specific shim is present) is a **vacuous pass**. This repo already hit that class of bug: hermetic `HOME` broke the desk `node` shim (`error: no nvm Node >= 24`, exit 127), and `2>/dev/null || echo parse-fail` turned a harness failure into a product-looking value.

Practices in force:

1. Prefer fakes under `tests/fake-bin` and pure shell/`awk` helpers (no `jq`, no `yq`, no assumed global node).
2. Optional dual-source checks **SKIP** with a reason when the dependency is absent; they never count as `ok`.
3. After a green full PATH run, run again with a minimal PATH and require the **same** module verdicts:

```sh
bash tests/run.sh
PATH=/usr/bin:/bin:/usr/local/bin bash tests/run.sh
```

If the second run fails tests the first run passed, the suite is still coupled to the developer environment — fix the test (stub the binary, skip visibly, or parse without the tool). If a test **passes** only on the second run because a dependency disappeared, that is the vacuous-pass bug: make the dependency explicit (fake or SKIP).

### Adding a test

1. Put it in the matching `tests/test-*.sh` (or a new `tests/test-foo.sh` picked up by `run.sh`).
2. Isolate with `mktemp` HOME / XDG when you touch config or state.
3. Prefix `PATH` with `tests/fake-bin` when exercising the client network surface; set `FAKE_NET_LOG`.
4. For tmux behaviour, set `REPO_SESSION_TMUXBIN` to `tests/fake-tmux` and seed `FAKE_TMUX_*`.
5. Assert **byte-stable** non-TTY tokens (`ok`/`FAIL`/`info`, `repo-session: …`) rather than colour glyphs.
6. If the case needs an optional external (Node module path, live listeners), `SKIP` with a reason — never silent pass.
7. Run both PATH modes above before you call the suite green.

### Related

- [CONTRIBUTING.md](../CONTRIBUTING.md) — short contributor checklist  
- [Command reference](./command-reference.md) — flags and exit codes  
- [Quoting and containment](./quoting-and-containment.md) — name rules and status gaps
