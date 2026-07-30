---
title: "Quoting and containment"
description: "What repo names are safe, how remote argv is quoted, how sessions match literally, and what status does not tell you."
section: guide
order: 18
---

# Quoting and containment

mossferry treats repository names as **single path segments under `FERRY_REPO_BASE`**, shell-quotes every remote argument, and matches tmux sessions by **literal name** — so a bad name fails loudly instead of attaching to the wrong place or leaving the configured base.

This page is for the inputs that used to be unsafe. Every message and rule below was produced by running `repo-session` / `ferry` on this tree.

## Happy path (safe name)

```sh
# On the host (or after ferry lands you there)
repo-session --validate my-app
# exit 0 when $FERRY_REPO_BASE/my-app is a directory

ferry workstation my-app --primary
# laptop pre-validates over ssh, then hops mosh/ssh with a fully quoted remote command
```

Allowed characters for a **repo token** (basename only):

```text
A–Z a–z 0–9 . _ -
```

Examples that pass the shape check (then succeed or fail only on “does the directory exist?”):

| Token | Shape | Observed with `--validate` when dir missing / present |
|-------|--------|------------------------------------------------------|
| `good-repo` | ok | exit 0 when directory exists |
| `my.app` | ok | exit 0 when directory exists |
| `a_b-c.0` | ok | `no repo 'a_b-c.0' under …` if missing |
| `.hidden` | ok | shape accepted |
| `-sneaky` | ok | shape accepted |
| `foo.` | ok | shape accepted |

## What is rejected

`repo-session --validate <token>` (and create / scoped list / claim paths that call the same check) **exit 1** with:

```text
repo-session: invalid repo name '…'
```

Observed rejections:

| Token | Why |
|-------|-----|
| `../evil` | path-shaped (`/` and `..`) |
| `outer/../../PWN` | slashes + `..` |
| `mono/packages/pkg-a` | nested path (not a single segment) |
| `/etc/passwd` | absolute path |
| `name with spaces` | space outside the allow-list |
| `o'neil` | apostrophe outside the allow-list |
| `name"quote` | quote outside the allow-list |
| `foo\bar` | backslash |
| `foo..bar` / `has..dots` / `a..b` | any `..` substring |
| `foo@bar` / `foo+bar` | other punctuation |

Missing argument:

```text
repo-session: --validate requires a <repo>
```

Missing but **shape-valid** directory:

```text
repo-session: no repo 'my-app' under <FERRY_REPO_BASE> — pick one below, or run 'ferry <host>' to browse all sessions
```

On a TTY the tool may list up to 20 basenames under the base and a did-you-mean hint. The first line above is the stable token clients and tests assert.

### Display quirk (apostrophes)

Invalid-name messages strip single quotes from the token before printing (`${name//\'/}`), so a rejected `o'neil` appears as:

```text
repo-session: invalid repo name 'oneil'
```

The token is still rejected; only the printed form is altered.

### Locale caveat (non-ASCII)

The written allow-list is `^[A-Za-z0-9._-]+$`. On a UTF-8 locale, bash’s `[[ =~ ]]` may treat some non-ASCII letters as matching `A-Za-z`. Observed here: `café` was **shape-accepted** (got the “no repo” path, not “invalid repo name”); Greek and CJK samples were rejected. Prefer ASCII basenames for predictable behaviour across machines.

## Remote command quoting

OpenSSH joins multiple arguments after the host with **bare spaces** (no shell quoting). A repo name with spaces used to word-split on the remote shell; a name with an apostrophe could leave an unmatched quote.

The laptop client now builds **one** remote command string with `printf %q` on every token, then runs:

- **ssh (list / validate / non-interactive):** `ssh <host> '<quoted remote cmd>'`
- **mosh (interactive default):** `mosh … <host> -- bash -lc '<quoted remote cmd>'`

Observed remote fragments (fake transport log; same quoting as production):

```text
# spaces → backslash-escaped in the remote string
… --validate name\ with\ spaces
… bash -lc .local/bin/repo-session --client-version 2.7.4 name\ with\ spaces --primary

# apostrophe → shell-quoted
… --validate o\'neil
… bash -lc .local/bin/repo-session --client-version 2.7.4 o\'neil --primary
```

**What quoting does not do:** it does not make spaces or quotes **valid** repo names. The host still runs `--validate` with `_ferry_repo_token_ok`. Quoting only ensures the remote shell sees the same bytes the laptop sent, so rejection is clean instead of a parse error or a half-name.

Interactive hops with a repo token **pre-validate over ssh** before mosh, so a typo fails on the laptop without opening a session.

## Path containment

Rule: a repo argument must be a **single segment**. It is joined as `$FERRY_REPO_BASE/<token>` only after the shape check.

1. **Shape gate** — reject `/`, `\`, any `..` substring, empty, and characters outside `A–Z a–z 0–9 . _ -` (see above). Message: `invalid repo name`.
2. **Realpath gate** — if the joined path exists and `realpath` is available, the resolved path must stay under the resolved base. Escape (for example a symlink whose target is outside the base) is refused with the **same first line** as a missing repo:

```text
repo-session: no repo 'escape-link' under <FERRY_REPO_BASE> — pick one below, or run 'ferry <host>' to browse all sessions
```

There is no separate “path escaped base” wording today.

Claim/lock filenames never embed raw slashes from a bad token: non-safe characters become `_`, and the lock lives as a flat file under `${TMPDIR:-/tmp}` (for example `repo-session-outer_.._.._PWN.claim`). That is defence in depth; path-shaped tokens are already rejected at validate/create.

## Session matching

Scoped pickers, `--list` with a repo, `--primary`, and claim paths filter sessions with **fixed-string** rules — they do **not** interpolate the repo name into `grep -E`.

A session name matches repo `R` when, after trailing whitespace is stripped:

| Pattern | Example (`R` = `o.neil`) |
|---------|---------------------------|
| Exact name | `o.neil` |
| `R-<digits>` | `o.neil-2` |
| `ccops-R-*` | `ccops-o.neil-abc` |

Observed non-matches (literal, so a `.` is only a dot):

| Session | Filter | Result |
|---------|--------|--------|
| `oXneil` | `o.neil` | no match (a regex `.` would have matched) |
| `o.neil-x` | `o.neil` | no match (suffix must be digits only) |
| `o'neil-fileXtxt` | `o'neil-file.txt` | no match |

**Why this matters more than it looks:** a wrong session attach is a **silent wrong answer** — you land in another project’s tmux, not an error. Literal match keeps “reattach to this repo” from becoming “reattach to any session whose name happens to match a regex.”

## Honest status

### `ferry doctor [host]`

Read-only health checks. Exit **1** if any line is `FAIL`; exit **1** if no host can be resolved:

```text
mossferry: doctor: no host (pass one, or set FERRY_HOST_CANDIDATES / FERRY_DEFAULT_HOST)
```

Non-TTY lines are `ok …`, `FAIL …`, or `info …`. Doctor reports (among other things):

| Kind of check | What it means |
|---------------|----------------|
| config readable / absent | Local `~/.config/mossferry/config` |
| ssh config resolves host | `ssh -G` accepts the alias |
| ssh BatchMode connect | Passwordless connect works |
| local mosh binary | `mosh` on the laptop PATH |
| grok wrap / `FERRY_WRAP` | Optional wrap availability |
| `FERRY_TRANSPORT` | mosh vs ssh preference |
| remote `repo-session` executable | Host binary under `FERRY_REMOTE_BIN` |
| versions match | Local `VERSION` vs remote clone |
| remote fzf | Present or numbered-menu fallback |
| remote mosh-server count | Info only |
| MagicDNS / HostName note | Info only |
| Mac-reachable host | From `preview-host` if on PATH |
| reserved ports | Configured denylist string |
| servers summary | Counts of LISTEN / declared-missing / FOREIGN (best-effort; never fails doctor alone) |

### Session list / picker

`ferry <host> --list` / `repo-session --list` rows look like:

```text
1) my-app           bash                   2w attached bash
```

Fields: index, session name, window label, window count, attached/detached, command. That is **tmux state**, not product policy.

### What status does **not** tell you

| Gap | Reality |
|-----|---------|
| **Ship policy marker** | Repos may declare `<!-- desk:ship=human-end-gate -->` (or similar) in `AGENTS.md`. **Neither doctor nor the session list nor the servers view reads or displays that marker.** Operators must open the file (or rely on other fleet tools). Known gap. |
| **“Safe to ship” / CI green** | There is no hosted CI signal in ferry. Verification is whatever you run locally. |
| **Secrets / agent trust** | Doctor does not audit agent env, sandboxes, or credentials. See [Safety roadmap](./safety-roadmap.md). |
| **Which pane is “the” primary for a human** | Primary is the session named exactly like the repo basename; ferry does not rank “importance.” |
| **Symlink escape detail** | Realpath refusal reuses the “no repo” message — you are not told *why* the path failed containment. |

## Limitations (short)

- Quoting fixes transport; the allow-list still forbids spaces and quotes as **names**.
- Non-ASCII basenames may pass or fail depending on locale; stick to the ASCII table above.
- Realpath containment only runs when the joined path exists **and** `realpath` is on the host PATH.
- Client does not re-implement the allow-list locally; it relies on remote `--validate` (with quoting so the remote sees the full token).
- Ship policy is not a ferry status surface.

## See also

- [Usage](./usage.md) — flags, errors table, short repo-name summary
- [Getting started](./getting-started.md) — install and `ferry doctor`
- [Servers view](./servers-view.md) — listener rows (also not a policy view)
- [Safety roadmap](./safety-roadmap.md) — door vs host perimeter
