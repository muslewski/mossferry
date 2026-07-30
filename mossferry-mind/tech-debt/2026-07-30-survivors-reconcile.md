---
type: debt
summary: "Surviving-defect reconcile after repair wave: 19 FIXED (with tests), 1 NOT-FIXED deferred (desk:ship status surface). t45 was PATH/node-dependent chrome parse — fixed to awk JSON."
severity: medium
effort: m
status: open
date: 2026-07-30
tags: [repo-session, fleet-devlog, client, install, survivors]
related:
  - "[[repo-session]]"
  - "[[client]]"
  - "[[install-config]]"
  - "[[tests]]"
  - "[[2026-07-30-hermetic-home-no-node-shim]]"
---

## Debt-dir consolidation

Atlas `folders.techDebt` is `tech-debt/` → **`mossferry-mind/tech-debt/`**.
Misplaced `mossferry-mind/map/tech-debt/2026-07-30-brutality-deferred.md` content
is folded here; that path is removed so the vault has one debt home.

## t45 PATH inversion (first task)

**Classification: (c) something else** — not a vacuous skip, not “missing binary
silently passes.”

- Product `print_picker_preview` called `sage about --json` then **`node -e`**
  to extract facts/judge.
- Test `setup` sets hermetic `HOME=tmp`. Desk PATH often resolves
  `~/.local/bin/node` (nvm24 shim). With `NVM_DIR` unset that shim looks under
  `$HOME/.nvm` and exits **127**.
- Observed fail shape (reproduced):  
  `FAIL t45 — out=[] sage_log=[about --tmux demo --json]`  
  (sage ran; chrome empty because node died; capture-pane empty in fixture.)
- Cold `PATH=/usr/bin:/bin:/usr/local/bin` uses `/usr/bin/node` → chrome works
  → `ok t45`. Same tree, opposite verdict.
- **Fix:** parse sage JSON with awk boolean/string helpers — no node. t45 now
  forces a broken `node` ahead on PATH and still expects chrome.  
  **Both PATHs:** `ok t45` (quoted from full suite runs 2026-07-30).

## Survivor table (20)

| # | sev | locus | STATE | evidence |
|---|-----|-------|-------|----------|
| 1 | critical | bin/repo-session:~599 → `_ferry_session_matches_repo` / `build_session_rows` | **FIXED** | Fixed-string match; never `grep -E` with repo. **t46** fails if decoy `o'neil-fileXtxt` matches. |
| 2 | critical | lib/fleet-devlog.sh:~308 | **FIXED** | Refuse symlink `events.jsonl`; realpath containment. Test `events-symlink-no-write-outside`. |
| 3 | major | bin/mossferry:817 → `_ferry_ssh_remote_cmd` | **FIXED** | `printf %q` remote argv. **m23** spaces. |
| 4 | major | bin/mossferry:817 (dup of 3) | **FIXED** | Same as #3 (pre-validate + mosh `bash -lc`). |
| 5 | major | bin/mossferry:226 `load_config` | **FIXED** | UTF-8 BOM strip before `source`. **m24**. |
| 6 | major | bin/repo-session:~1916 path tokens | **FIXED** | `_ferry_repo_token_ok` + `_ferry_claim_lockf`. **t47**, **t48**. |
| 7 | major | bin/repo-session:~1917 slash monorepo | **FIXED** | Slash tokens rejected before attach/lock. **t47b**. |
| 8 | major | bin/repo-session status / AGENTS.md | **NOT-FIXED** | No local surface reads `desk:ship` / pre-contract. Product design for picker/list chrome. Severity medium; effort **m**; not a silent wrong attach. Deferred. |
| 9 | major | bin/repo-session create_repo orphan | **FIXED** | `rmdir` empty non-git after `git init` fail. **t49**. |
| 10 | major | create_repo orphan (dup of 9) | **FIXED** | Same as #9. |
| 11 | major | install.sh:97 | **FIXED** | `mkdir`/`ln` failures `exit 1`. Test `mkdir failure exits nonzero`. |
| 12 | major | lib/fleet-devlog.sh machine enabled | **FIXED** | Exact `{"enabled":true\|false}` only. Tests `corrupt-config-fail-closed`, `invalid-json-config-fail-closed`. |
| 13 | major | same as 12 (dup) | **FIXED** | Same as #12. |
| 14 | minor | bin/mossferry VERSION strip | **FIXED** | `own_version` + remote strip BOM. **m25**. |
| 15 | minor | --validate leading-dash | **FIXED** | Bare `-name` and `-- -name` accepted. create_repo still requires leading alnum (rare; see deferred). |
| 16 | minor | scoped --list empty vs missing | **FIXED** | `validate_repo` before list. **t50**. |
| 17 | minor | scoped --list (dup of 16) | **FIXED** | Same as #16. |
| 18 | minor | empty list quote wrap | **FIXED** | `echo "no ${repo} sessions yet"` — no single-quote wrap. |
| 19 | minor | validate error quote / ls noise | **FIXED** | Apostrophe-safe message branch; suggestions only directories. |
| 20 | minor | lib/fleet-devlog.sh:90 concurrent mkdir | **FIXED** | EEXIST + `[[ -d ]]` success in `_devlog_ensure_dir`. |

## Still deferred (NOT-FIXED only)

1. **desk:ship / AGENTS.md on status surfaces** — severity medium, effort m.  
   Needs product judgment for what picker/list show for missing vs marked
   `desk:ship`. Not a containment or wrong-session attach bug.
2. **Machine config multi-key JSON** — `_devlog_machine_enabled` only accepts
   exact single-key object (fail-closed). Multi-key needs real parse without jq;
   current consumers use single-key form.
3. **create_repo leading-dash / leading non-alnum** — validate accepts; create
   still requires `^[A-Za-z0-9]…`. Rare worktree basenames.

## Verification (re-run cold)

| check | result |
|-------|--------|
| `npm test` (desk PATH) | exit **0** — includes `ok t45`, fleet-devlog 1 skip (JS dual-source optional) |
| `PATH=/usr/bin:/bin:/usr/local/bin npm test` | exit **0** — same `ok t45`; skip count match (1) |
| PATH-dependent suite verdict | **no** — both green after t45 fix |

## Prior false claims

- Prior receipt “t45 green on this host” without PATH caveat was **contradicted**
  under hermetic HOME + nvm shim. Do not re-claim without both PATH runs.
