---
type: decision
summary: "Reject invalid repo tokens on the laptop before ssh; short-circuit doctor remote probes after BatchMode connect FAIL."
status: active
date: 2026-07-30
tags: [client, doctor, validation, dogfood]
related:
  - "[[client]]"
  - "[[repo-session]]"
---

# Local shape gate + doctor short-circuit

## Context

A clean-HOME dogfood run followed the docs and **failed**:

1. Docs claimed invalid repo tokens print `repo-session: invalid repo name '…'`
   and never start mosh. On the laptop with an unreachable host, `ferry
   workstation 'has space'` produced only `ssh: Could not resolve hostname…`
   because pre-validation was solely over ssh.
2. `ferry doctor <unreachable-host>` hung on later remote ssh probes after
   `FAIL ssh BatchMode connect`.

## Decision

1. **Shared shape gate** — extract `_ferry_repo_token_ok` (and the stable
   reject message helper) to `lib/repo-token.sh`. Both `bin/mossferry` and
   `bin/repo-session` source it (inline fallback if the lib file is missing).
2. **Local-first on the client** — `launch_remote` rejects shape-invalid repo
   tokens **before any ssh**, with the same `repo-session: invalid repo name
   '…'` line the host uses. Existence still uses remote `--validate` before
   mosh for shape-valid tokens.
3. **Doctor** — record `connect_ok` from the BatchMode connect probe; put
   `BatchMode=yes` + `ConnectTimeout=5` on every remote-connecting probe;
   when connect fails, skip remote probes, emit
   `info remote checks skipped — ssh BatchMode connect failed`, and keep
   the usual FAIL/info tokens so exit stays **1** without hanging.

## Why not only fix the docs

The documented behaviour (local invalid-name, terminating doctor) is the better
contract for a stranger. The validation rule already existed on the host;
factoring one definition avoids a second, subtly different charset.

## Consequences

- Help/docs now say: invalid tokens rejected **locally**; missing repos
  pre-validate **over ssh** before mosh.
- Suite: `m23`/`m23b` assert local reject (no transport log); `f1b` asserts
  doctor short-circuit under `FAKE_SSH_UNREACHABLE`.
