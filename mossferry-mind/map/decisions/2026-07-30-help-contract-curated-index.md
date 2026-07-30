---
type: decision
summary: "Keep curated ferry/repo-session --help as an index while restoring test-pinned section headings, mossferry <host>, and truthful fzf --cycle wording."
status: active
date: 2026-07-30
tags: [help, docs, contract, tests]
related:
  - "[[client]]"
  - "[[repo-session]]"
---

# Curated help still satisfies the suite contract

## Context

The documentation fleet rewrote README and curated `--help` as scannable
indexes (purpose, primary verbs, one happy path, pointer to full docs). The
suite still greps fixed needles in README and help. Tests were deliberately
out of scope for that pass, so eight content-contract assertions failed.

## Decision

1. **Satisfy the contract in the new structure** — restore missing README
   sections (Open-sourcing, no personal paths / hardcoded hosts, `git remote
   add origin`, ghostty-grid composition) in the rewritten voice, not as
   bare keyword stuffing.
2. **Keep help curated** but restore section headings the suite pins:
   `Usage`, `Picker`, `Flags`, `Config`, `Examples` on the client; exact
   `Flags` on `repo-session` (that test has no case-insensitive fallback).
3. **Usage form stays `mossferry <host>`** so m6/m16 and the long-name form
   remain the documented primary line; `ferry` remains the short alias note.
4. **`--cycle` is mentioned as fzf list wrap-around**, not as a mossferry key
   chord or CLI flag (unknown flag `--cycle` is ignored by repo-session). This
   preserves the needle without reintroducing the old misleading picker-key
   wording.

## Why not change the tests

The needles map to real reader needs (OSS self-host story, grid composition,
scannable help sections). The suite is the public contract; rewriting tests
would weaken it for a pure wording preference.

## Consequences

Future help edits must keep those headings and the `mossferry <host>` usage
line (or change the tests loudly with justification). Full flag lists stay in
`docs/command-reference.md`.
