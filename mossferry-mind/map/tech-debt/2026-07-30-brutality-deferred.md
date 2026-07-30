---
type: debt
summary: "Deferred brutality-fleet findings after critical/major containment and honesty fixes: desk:ship status surface, leading-dash validate edge cases, and full multi-key JSON machine config."
severity: medium
effort: m
status: open
date: 2026-07-30
tags: [repo-session, fleet-devlog, desk-ship]
related:
  - "[[repo-session]]"
  - "[[client]]"
---

## Deferred (with why)

- **desk:ship / AGENTS.md on status surfaces** (`bin/repo-session` status paths)
  — no local display currently distinguishes missing vs marked `desk:ship`.
  Needs product design for what to show in picker/list; not a silent
  wrong-answer on attach, so deferred after containment work.
- **Machine config multi-key JSON** — `_devlog_machine_enabled` only accepts
  exact `{"enabled":true|false}` after whitespace strip (fail-closed). A
  future multi-key config needs a real JSON parse without jq (or optional
  pre-captured node). Current contract consumers use the single-key form.
- **Leading-dash repo basenames** — `--validate -foo` is accepted as a name
  now, but create_repo still requires a leading alnum. Rare; document later.
- **t45 sage picker-preview** — environment-dependent on this host; out of
  scope for the false-green repair. Do not claim green/red without a run.
