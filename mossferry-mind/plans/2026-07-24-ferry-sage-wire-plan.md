# Ferry × SAGE wire — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended). Steps use checkbox syntax.

**Goal:** Optional sage one-liners in ferry picker + ⚖ new judge create path; sage owns auto annotate + `sage about`.

**Architecture:** Phase 1 agentic-sage (about + session_lines on briefs). Phase 2 mossferry (FERRY_SAGE adapter, preview wrapper, judge create). Soft detect; silent degrade.

**Tech Stack:** Node ≥20 (sage), bash (ferry), node:test / bash tests.

## Global Constraints

- Neither product hard-depends on the other.
- One-liners automatic in sage; ferry never writes sage store.
- `FERRY_SAGE` default auto; `off` hard-kills.
- Preview about timeout ≤250ms; never block attach/kill.
- Exit 0 for `sage about` not-found.
- Keep ➕ empty-{6} preview guard.
- Specs/plans live under `mossferry-mind/` (not `docs/superpowers/`).
- Commits in each repo separately.

---

### Task 1: sage — `factsLine` + `aboutTmux` + CLI

**Repos:** agentic-sage

**Files:**
- Create: `lib/about.mjs`
- Create: `test/about.test.mjs`
- Modify: `bin/sage` (case `about`)
- Modify: `SCHEMA.md` (sage.about + session_lines)

**Produces:** `factsLine(s)`, `aboutTmux(home, tmuxName, opts)`, `sage about --tmux X [--json]`

- [ ] **Step 1:** Tests for factsLine + about match by tmux session prefix + not-found
- [ ] **Step 2:** Implement lib/about.mjs + CLI
- [ ] **Step 3:** `node --test test/about.test.mjs` green; commit

### Task 2: sage — brief `session_lines` auto on fact judge run

**Files:**
- Modify: `lib/brief.mjs` (normalize session_lines)
- Modify: `lib/judge-run.mjs` (buildFactBrief fills session_lines)
- Modify: `test/brief.test.mjs` / `test/judge-run.test.mjs`
- about.mjs reads fresh brief session_lines for judge field

- [ ] **Step 1:** Test fact brief includes session_lines; about surfaces judge text
- [ ] **Step 2:** Implement
- [ ] **Step 3:** Tests green; commit

### Task 3: mossferry — detect + picker-preview

**Repo:** mossferry

**Files:**
- Modify: `bin/repo-session` (FERRY_SAGE, `_ferry_sage_enabled`, `--picker-preview`)
- Modify: `config.example`
- Create: `tests/fake-bin/sage`
- Modify: `tests/test-repo-session.sh`

- [ ] **Step 1:** Tests for sage off/on/missing
- [ ] **Step 2:** Preview wrapper wires about + capture
- [ ] **Step 3:** Suite green; commit

### Task 4: mossferry — ⚖ new judge create

**Files:**
- Modify: `bin/repo-session` (row + flow)
- Modify: tests + README/CHANGELOG/works-with if present

- [ ] **Step 1:** Tests fake sage judge run invocation
- [ ] **Step 2:** Implement scope menus + startcmd
- [ ] **Step 3:** Suite green; commit; docs

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| facts one-liner | T1 |
| about CLI | T1 |
| session_lines / judge run auto | T2 |
| ferry detect hybrid | T3 |
| preview chrome | T3 |
| new judge create | T4 |
| FERRY_SAGE=off | T3–T4 |
| silent degrade | T3 |
