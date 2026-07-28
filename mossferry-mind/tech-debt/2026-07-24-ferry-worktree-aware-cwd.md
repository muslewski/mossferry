---
type: tech-debt
summary: "Ferry starts Grok at monorepo root; Grok fs_notify crawls nested .claude/worktrees (dozens of node_modules) and freezes launch. Future: worktree-aware attach/create so Grok cwd is one worktree."
tags: [ferry, grok, worktrees, performance, deferred]
status: open
created: 2026-07-24
related:
  - "[[client]]"
  - "[[repo-session]]"
---

# Debt — ferry worktree-aware Grok cwd (deferred Approach A)

## Why deferred

Operator chose **not** to build worktree-aware ferry attach yet (2026-07-24). Prefer syndcast **worktree hygiene** (remove merged/stale trees) first.

## Symptom

`grok-muslewski` from `~/Repositories/syndcast` (or ferry session cwd = repo root) hangs minutes at ~100% CPU. Process FDs show walks into `.claude/worktrees/*/node_modules` even with `GROK_RESPECT_GITIGNORE=1` and path gitignored. Nested worktrees are the preferred layout (WORKTREES.md) — must **keep** using them, not abandon the convention.

## Mossferry coupling

Ferry/repo-session opens one tmux session per **repo** with pane cwd = `FERRY_REPO_BASE/<repo>`. Start menu / `grok-*` runs there → worst Grok scan scope.

## Desired (Approach A — later)

1. After picking repo, if `git worktree list` shows nested trees under `.claude/worktrees/`, offer pick (or MRU).
2. Create/attach with **cwd = that worktree path**; start command runs there.
3. Explicit **root mode** for monorepo-wide work (optional slow-start warning).
4. Session/window naming can encode worktree slug.

## Non-goals for that wave

- Moving worktrees out of `.claude/worktrees/`
- Changing WORKTREES.md nesting preference
- Upstream Grok product fix (file separately if needed)

## Interim (syndcast ops)

See syndcast tech-debt: worktree GC after merge + audit of stale advisor trees.
