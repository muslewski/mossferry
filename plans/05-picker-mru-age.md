# Plan 05: Most-recently-used ordering and a relative-age column in the picker (opt-in)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 88cd1f4..HEAD -- bin/repo-session config.example README.md tests/fake-tmux tests/test-repo-session.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch that this plan does not explain, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: `plans/02-*.md` — the plan that rewrites `build_session_rows`
  into a single `list-sessions -F` fetch (see the DEPENDENCY / DRIFT WARNING
  below). **02 must be DONE before this plan runs.**
- **Category**: ux
- **Planned at**: commit `88cd1f4`, 2026-07-18

## ⚠️ DEPENDENCY / DRIFT WARNING — READ BEFORE ANYTHING ELSE

This plan is written for the codebase **after** plan 02 lands. At the planning
commit `88cd1f4`:

- `plans/` is **empty** — plan 02 does not exist in the repo yet. It is a
  sibling plan being written in the same review batch. **Do not start plan 05
  until plan 02 has been implemented and its tests pass.**
- `build_session_rows` (bin/repo-session) still has its **pre-02** shape: it
  fetches session names with `list-sessions -F '#{session_name}'` and then loops
  calling `display-message -p` once per field per session, ending in a single
  6-field `printf`. Plan 02 is expected to collapse that into one
  `list-sessions -F '<multi-field>'` call.

Because plan 02's exact code cannot be quoted here, this plan changes
`build_session_rows` in a way that is **robust to either shape**: it hooks the
two structural points that survive plan 02's rewrite — (1) where the session
**name list** is produced/sorted, and (2) the single **row-emit `printf`**. It
fetches per-session activity with `display-message` rather than weaving
`#{session_activity}` into plan 02's `-F` string, so plan 05 does not depend on
the precise format string plan 02 chose. See "Maintenance notes" for why, and
for the follow-up optimization the brief anticipated.

If, when you open `build_session_rows`, it **still matches the pre-02 excerpt in
"Current state" verbatim** (name fetch via `list-sessions -F '#{session_name}'`
+ per-field `display-message` loop and no single multi-field `-F`), then plan 02
has **not** landed → this is a **STOP condition** (see STOP conditions). Do not
proceed.

## Why this matters

The picker lists sessions in lexical order (`sort -V`), so the session you were
just in is buried wherever its name falls alphabetically, and there is no cue
for how fresh each session is. On a host with a dozen sessions you scan the
whole list every time to find "the one I used five minutes ago". This plan adds,
**for the picker only**, most-recently-used ordering plus a compact relative-age
column (`3m`, `2h`, `5d`), gated behind an opt-in config key
`FERRY_PICKER_SORT` so nobody's muscle memory (today's alphabetical order)
breaks by default. MRU is scoped to the **global** cross-repo picker, where it
helps most; the repo-scoped `repo`, `repo-2`, … picker keeps its stable slot
order (a `repo-N` list is easier to reason about when the slots never move).

The hard constraint: the `--list` / `-l` output and the shared
`build_session_rows` row contract are **byte-stable and asserted by tests**. The
age column and MRU order must live in the picker path only and must not change
the 6-field rows that `--list` and the unit tests read.

## Current state

Files and their roles:

- `bin/repo-session` — remote brain. `load_config` (config keys),
  `build_session_rows` (the shared row builder; **plan-02 territory**),
  `run_picker` (the interactive picker; both an fzf path and a numbered-menu
  fallback), `print_list` (the `--list` renderer — must stay byte-stable).
- `config.example` — commented `FERRY_*` template.
- `README.md` — the `## Configuration` key table and the `## The picker` section.
- `tests/fake-tmux` — stub tmux driven by env; must learn to report
  `#{session_activity}`.
- `tests/test-repo-session.sh` — the unit/integration suite for repo-session.

### `load_config` — where the new config key is registered (STABLE; not plan-02 territory)

Env snapshot locals (bin/repo-session:116-117):

```bash
  local e_REMOTE_BIN e_REPO_BASE e_DEFAULT_CMD e_DEFAULT_HOST e_SERVER_TIMEOUT e_REMOTE_REPO
  local e_HIDDEN_WINDOW_GLOB e_BANNER e_LAUNCHERS
```

Snapshot line (bin/repo-session:126):

```bash
  e_LAUNCHERS="${FERRY_LAUNCHERS-__UNSET__}"
```

Defaults line (bin/repo-session:136):

```bash
  FERRY_LAUNCHERS="ctrl-a:claude,ctrl-g:grok"
```

Env-wins override line (bin/repo-session:151):

```bash
  [[ "$e_LAUNCHERS" != "__UNSET__" ]] && FERRY_LAUNCHERS="$e_LAUNCHERS"
```

### `build_session_rows` — the shared row builder (⚠️ PLAN-02 TERRITORY; excerpt is PRE-02)

Signature, locals, and the name fetch (bin/repo-session:361-371):

```bash
build_session_rows() {
  local filter="${1:-}" s cname wins att cmd attword
  local active_name active_idx display_name preview_target glob wline widx wname found
  local -a names=()
  glob="${FERRY_HIDDEN_WINDOW_GLOB:-_*}"
  if [[ -n "$filter" ]]; then
    mapfile -t names < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null \
      | grep -E "^${filter}(-[0-9]+)?$" | sort -V)
  else
    mapfile -t names < <("$TMUXBIN" list-sessions -F '#{session_name}' 2>/dev/null | sort -V)
  fi
```

The single row-emit `printf` at the bottom of the per-session loop
(bin/repo-session:401):

```bash
    printf '%s\t%s\t%sw\t%s\t%s\t%s\n' "$s" "$display_name" "$wins" "$attword" "$cmd" "$preview_target"
```

The 6 tab fields are, in order:
`1=session  2=display_window  3=<N>w  4=attached|detached  5=cmd  6=preview_target`.
`preview_target` is `session:index` and the fzf picker's preview references it as
field `{6}`. **This 6-field contract is asserted by `t8` (exactly 6 fields,
`preview` == field 6) and consumed by `print_list` / `--list` — it must not
change for the default and `--list` call sites.**

### `run_picker` — the interactive picker (STABLE; not plan-02 territory)

Function head and locals (bin/repo-session:680-685):

```bash
run_picker() {
  # Uses global $repo (may be empty = global).
  local -a rows=()
  local line choice name i nsel key ans newname pickfile
  local new_label=$'➕ new session…'
  local is_new=0
```

The numbered-menu (no-fzf) rows are built here (bin/repo-session:691-693):

```bash
      while IFS= read -r line; do
        [[ -n "$line" ]] && rows+=("$line")
      done < <(build_session_rows "$repo")
```

The fzf-path rows are built here (bin/repo-session:733-735):

```bash
    while IFS= read -r line; do
      [[ -n "$line" ]] && rows+=("$line")
    done < <(build_session_rows "$repo")
```

The fzf invocation feeds `rows` + the new-session label and previews field `{6}`
(bin/repo-session:748-757). `name` is extracted as field 1 with
`name="${choice%%$'\t'*}"` (bin/repo-session:786). Both keep working when a 7th
field is appended, because a 7th field does not move fields 1 or 6.

### `print_list` — the `--list` renderer (must stay byte-stable; **do NOT touch**)

bin/repo-session:459-466:

```bash
print_list() {
  local i=1 s cname wins att cmd _preview
  while IFS=$'\t' read -r s cname wins att cmd _preview; do
    [[ -z "$s" ]] && continue
    printf '%d) %-16s %-22s %s\n' "$i" "$s" "$cname" "$wins $att $cmd"
    ((i++)) || true
  done < <(build_session_rows "${repo:-}")
}
```

It calls `build_session_rows "${repo:-}"` with **one** argument → default mode →
6 fields. Leave this file region untouched.

### `tests/fake-tmux` — stub tmux (STABLE; you will extend it)

Header docs (tests/fake-tmux:1-8), the `list-sessions` handler
(tests/fake-tmux:66-71), the `display-message` `case "$format"` block
(tests/fake-tmux:136-168 — arms for `#{window_name}`, `#{window_index}`,
`#{session_windows}`, `#{session_attached}`, `#{pane_current_command}`, then a
`*)` default), and the `_lookup_meta` helper (tests/fake-tmux:18-43). The
`pane_current_command` arm you will add a sibling after is:

```bash
      *'#{pane_current_command}'*)
        printf '%s\n' "$_cmd"
        ;;
```

There is currently **no** `#{session_activity}` support and **no**
`FAKE_TMUX_ACTIVITY` env. Existing meta parsing (`FAKE_TMUX_META` +
`_lookup_meta`) must **not** be modified — your activity support is additive and
independent (see STOP conditions).

### Repo conventions you must honor

- `set -u` is on, `set -e` is OFF. Every new variable used must be declared
  `local`; guard array expansions as `"${arr[@]+"${arr[@]}"}"`.
- Targets: `bin/repo-session` is effectively Linux (already uses `mapfile` and
  `flock` by design — keep them).
- Non-TTY output is byte-stable and asserted. The age column and MRU order are
  **picker-only** — they must never appear in `build_session_rows`'s default
  (0-arg / 1-arg) output, so `--list`, `t8`, `t20` stay byte-identical.
- The two scripts deliberately duplicate helpers to stay self-contained — do not
  try to share code with `bin/mossferry`.
- `lib/green-ui.sh` may be missing; do not assume `UI_*` are non-empty.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift check | `git diff --stat 88cd1f4..HEAD -- bin/repo-session config.example README.md tests/fake-tmux tests/test-repo-session.sh` | review; explained changes only |
| Prereq confirm | open `build_session_rows`; confirm it is the **post-02** single-`-F` shape | not the pre-02 excerpt (else STOP) |
| Syntax (script) | `bash -n bin/repo-session` | exit 0, no output |
| Syntax (stub) | `bash -n tests/fake-tmux` | exit 0, no output |
| Syntax (tests) | `bash -n tests/test-repo-session.sh` | exit 0, no output |
| Lint | `shellcheck bin/repo-session` | exit 0 (honor existing `# shellcheck disable=`; if `shellcheck` is not on PATH, skip and note it) |
| Focused tests | `bash tests/test-repo-session.sh` | every line `ok …`, no `FAIL`, exit 0 |
| Full suite | `bash tests/run.sh` | exit 0 (no `FAIL` anywhere) |

## Scope

**In scope** (the only files you may modify):

- `bin/repo-session` — `load_config` (register `FERRY_PICKER_SORT`), a new
  `_ferry_relage` helper, `build_session_rows` (mode param: MRU ordering + a
  picker-only 7th age field), `run_picker` (choose mode, pass it in).
- `config.example` — one new commented line.
- `README.md` — one config-table row + a short picker-section note.
- `tests/fake-tmux` — add `FAKE_TMUX_ACTIVITY` + `#{session_activity}` reporting.
- `tests/test-repo-session.sh` — add the picker-ordering tests (t36–t39) and
  register them in the runner dispatch.

**Out of scope** (do NOT touch, even though they look related):

- `print_list` and the `--list` code path / ordering — must stay `sort -V` and
  byte-stable. Do not add the age column or MRU there.
- The picker's bind/kill/rename/launcher logic (`picker_kill`, `picker_rename`,
  `launcher_cmd`, the `ctrl-x`/`ctrl-r`/launcher key handling).
- `bin/mossferry`, `lib/green-ui.sh`, `install.sh`.
- The existing `FAKE_TMUX_META` / `_lookup_meta` parsing in `tests/fake-tmux`.
- Any change to the 6-field row contract for the default/`--list` call sites, or
  to any existing non-TTY token (`t8`'s 6 fields, `t20`'s `--list` text, etc.).

## Git workflow

- Branch: `advisor/05-picker-mru-age` (or the repo's convention if one is
  evident from `git log`).
- Commit per step or per logical unit; message style: conventional commits
  (recent history uses `chore(demo): …`, `feat: …`). Example:
  `feat(picker): opt-in MRU order + relative-age column`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

Do the steps in order. Steps 1–2 and 6 (fake-tmux) touch only stable code and
can land first; step 3 (`build_session_rows`) is the plan-02-coupled one.

### Step 1: Register the `FERRY_PICKER_SORT` config key in `load_config`

In `bin/repo-session`, make four additive edits to `load_config` (all four
mirror how `FERRY_LAUNCHERS` is handled — add a parallel line each time):

1. Extend the second env-snapshot `local` line (currently line 117) to declare
   `e_PICKER_SORT`:

   ```bash
   local e_HIDDEN_WINDOW_GLOB e_BANNER e_LAUNCHERS e_PICKER_SORT
   ```

2. After the `e_LAUNCHERS="${FERRY_LAUNCHERS-__UNSET__}"` snapshot line, add:

   ```bash
   e_PICKER_SORT="${FERRY_PICKER_SORT-__UNSET__}"
   ```

3. After the `FERRY_LAUNCHERS="ctrl-a:claude,ctrl-g:grok"` default line, add:

   ```bash
   FERRY_PICKER_SORT="name"
   ```

4. After the `[[ "$e_LAUNCHERS" != "__UNSET__" ]] && FERRY_LAUNCHERS="$e_LAUNCHERS"`
   override line, add:

   ```bash
   [[ "$e_PICKER_SORT" != "__UNSET__" ]] && FERRY_PICKER_SORT="$e_PICKER_SORT"
   ```

Valid values are `name` (default; today's `sort -V`) and `mru`. Do not validate
the value here — an unknown value simply falls through to name order in step 4's
guard (`== "mru"` is the only branch).

**Verify**: `bash -n bin/repo-session` → exit 0, no output.

### Step 2: Add the `_ferry_relage` helper

Add a small, pure formatter **immediately above** `build_session_rows` (at the
planning commit that is right after `own_version`, near line 357 — place it just
before the `# One line per live session …` comment that heads
`build_session_rows`):

```bash
# Compact relative age token from an epoch activity stamp: now / 3m / 2h / 5d.
# Empty/non-numeric epoch or empty now → empty string (no column shown).
_ferry_relage() {
  local ts="${1:-}" now="${2:-}" d
  [[ -z "$ts" || -z "$now" ]] && { printf ''; return 0; }
  [[ "$ts" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] || { printf ''; return 0; }
  d=$(( now - ts ))
  (( d < 0 )) && d=0
  if   (( d < 60 ));    then printf 'now'
  elif (( d < 3600 ));  then printf '%dm' $(( d / 60 ))
  elif (( d < 86400 )); then printf '%dh' $(( d / 3600 ))
  else                       printf '%dd' $(( d / 86400 ))
  fi
}
```

**Verify**: `bash -n bin/repo-session` → exit 0. Quick functional check:

```bash
REPO_SESSION_LIB=1 bash -c 'source bin/repo-session; \
  printf "[%s][%s][%s][%s][%s]\n" \
    "$(_ferry_relage 99970 100000)" "$(_ferry_relage 99400 100000)" \
    "$(_ferry_relage 92800 100000)" "$(_ferry_relage 1 172801)" \
    "$(_ferry_relage "" 100000)"'
```

Expected output exactly: `[now][10m][2h][1d][]`

### Step 3: Add MRU ordering + a picker-only age field to `build_session_rows`

⚠️ This is the plan-02-coupled step. First **confirm plan 02 landed** (open
`build_session_rows`; it must be the single-`list-sessions -F` shape, NOT the
pre-02 excerpt in "Current state"). If it still matches the pre-02 excerpt →
STOP (see STOP conditions).

Make three changes. They are described by **structural role**, with concrete
snippets, because plan 02 renumbers the lines:

**3a — accept a mode argument and compute `now` once.** At the top of
`build_session_rows`, add a `mode` parameter and, when in a picker mode, a
`now` timestamp. Add all new names to the function's `local` declarations
(`mode`, `now`, and the temporaries used below: `_act`, `_age`, `_pairs`, `_n`,
`_a`). Concretely, change the signature/first-locals so `mode` is read from
`$2` and `now` exists:

```bash
build_session_rows() {
  local filter="${1:-}" mode="${2:-}" now=""
  # ... keep the rest of the existing local declarations, and also declare:
  #     local _act _age _n _a
  #     local -a _pairs=()
  [[ "$mode" == picker-* ]] && now=$(date +%s)
```

`mode` values:
- empty (default) or anything not starting with `picker-` → **today's behavior**
  exactly: `sort -V` by name, 6-field rows. This is what `t8`, `print_list`,
  and `--list` use.
- `picker-name` → name order (like default) **plus** a 7th age field.
- `picker-mru` → activity-descending order (name `sort -V` tiebreak) **plus** a
  7th age field.

**3b — MRU reorder of the name list.** *After* the block that populates the
`names` array (whatever plan 02 renamed it to — the ordered list of session
names the emit loop iterates), insert an MRU re-sort that runs only for
`picker-mru`. It fetches each session's activity via `display-message` (so it
does not depend on plan 02's `-F` string) and re-sorts:

```bash
  if [[ "$mode" == "picker-mru" ]] && (( ${#names[@]} > 1 )); then
    _pairs=()
    for _n in "${names[@]}"; do
      [[ -z "$_n" ]] && continue
      _a=$("$TMUXBIN" display-message -p -t "=$_n" '#{session_activity}' 2>/dev/null)
      [[ "$_a" =~ ^[0-9]+$ ]] || _a=0
      _pairs+=("${_a}"$'\t'"${_n}")
    done
    mapfile -t names < <(printf '%s\n' "${_pairs[@]+"${_pairs[@]}"}" \
      | sort -t$'\t' -k1,1nr -k2,2V | cut -f2-)
  fi
```

`sort -k1,1nr` = activity numeric descending (most-recent first); `-k2,2V` =
name version-sort as the tiebreak. Only names are reordered; the row fields are
still built by plan 02's existing loop.

**3c — append the age as a 7th field, picker modes only.** Find the single
row-emit `printf` (pre-02 it is the line
`printf '%s\t%s\t%sw\t%s\t%s\t%s\n' "$s" "$display_name" ...` shown in "Current
state"; post-02 it is plan 02's equivalent single 6-field `printf`). Replace it
with a mode branch that keeps the exact 6-field line for non-picker modes and
appends one `\t%s` age field for picker modes:

```bash
    if [[ "$mode" == picker-* ]]; then
      _act=$("$TMUXBIN" display-message -p -t "=$s" '#{session_activity}' 2>/dev/null)
      _age=$(_ferry_relage "$_act" "$now")
      printf '%s\t%s\t%sw\t%s\t%s\t%s\t%s\n' "$s" "$display_name" "$wins" "$attword" "$cmd" "$preview_target" "$_age"
    else
      printf '%s\t%s\t%sw\t%s\t%s\t%s\n' "$s" "$display_name" "$wins" "$attword" "$cmd" "$preview_target"
    fi
```

Use the **same field expressions plan 02 uses** for fields 1–6 (the names above,
`$s $display_name $wins $attword $cmd $preview_target`, are the pre-02 names —
match whatever plan 02 renamed them to). The non-picker `printf` must remain
byte-identical to plan 02's current 6-field line. The 7th field is the age token
only; `preview_target` stays field 6 so the fzf `--preview {6}` is untouched.

**Verify**:

```bash
# Default (0-arg) mode still yields exactly 6 fields, name order — even with activity set:
REPO_SESSION_LIB=1 FAKE_TMUX_SESSIONS=$'alpha\nbeta' \
  FAKE_TMUX_META=$'alpha|Awin|1w detached bash\nbeta|Bwin|1w detached bash' \
  FAKE_TMUX_ACTIVITY=$'alpha|100\nbeta|200' \
  REPO_SESSION_TMUXBIN=tests/fake-tmux \
  bash -c 'source bin/repo-session; build_session_rows | head -1 | awk -F"\t" "{print NF}"'
```

Expected: `6` (do step 6 first so `tests/fake-tmux` understands
`FAKE_TMUX_ACTIVITY`; if you run this before step 6, activity is simply ignored
and you still get `6`). Then `bash -n bin/repo-session` → exit 0.

### Step 4: Choose the mode in `run_picker` and pass it to both call sites

In `run_picker`, after the existing `local is_new=0` line (bin/repo-session:685),
add the mode selection — MRU only for the **global** picker (`repo` empty) when
the user opted in:

```bash
  # Picker order: global picker honours FERRY_PICKER_SORT=mru; repo-scoped stays name.
  local sort_mode="picker-name"
  if [[ -z "$repo" && "${FERRY_PICKER_SORT:-name}" == "mru" ]]; then
    sort_mode="picker-mru"
  fi
```

Then change **both** `build_session_rows "$repo"` call sites inside `run_picker`
(the numbered-menu one at bin/repo-session:693 and the fzf one at
bin/repo-session:735) to pass the mode:

```bash
      done < <(build_session_rows "$repo" "$sort_mode")
```

Do **not** change `print_list`'s `build_session_rows "${repo:-}"` call (that is
`--list`, out of scope). Both picker paths now render the age column; only the
global opt-in path reorders MRU-first.

**Verify**: `bash -n bin/repo-session` → exit 0. `grep -c 'build_session_rows "\$repo"' bin/repo-session`
should now be `0` (both picker calls carry a second argument), while
`grep -c 'build_session_rows "\${repo:-}"' bin/repo-session` stays `1`
(`print_list`, untouched).

### Step 5: Document the key (config.example + README)

In `config.example`, after the two `FERRY_LAUNCHERS` lines (config.example:10-11),
add:

```
#FERRY_PICKER_SORT="name"                    # picker order: name (sort -V) | mru (global picker: most-recently-used first + age column)
```

In `README.md`, add one row to the `## Configuration` table, immediately after
the `FERRY_LAUNCHERS` row (README.md:157):

```
| `FERRY_PICKER_SORT` | `name` | remote: picker order — `name` (version-sort, today's default) or `mru` (the **global** picker lists most-recently-used sessions first and shows a relative-age column) |
```

Also extend the picker-row description bullet (README.md:115-116) so the age
column is documented. Change:

```
- One fzf list; each row: session name, active-window name, window count,
  attached/detached, current command.
```

to:

```
- One fzf list; each row: session name, active-window name, window count,
  attached/detached, current command, and a relative age (`3m`, `2h`, `5d`).
- **Ordering:** default `name` (version-sort). Set `FERRY_PICKER_SORT=mru` to
  make the **global** picker list most-recently-used sessions first; the
  repo-scoped picker keeps stable slot order.
```

**Verify**: `git diff --stat -- config.example README.md` shows only these files
changed; visually confirm the new table row and bullet render as intended.

### Step 6: Teach `tests/fake-tmux` to report `#{session_activity}`

All changes here are **additive** and must not touch `FAKE_TMUX_META` /
`_lookup_meta`.

1. Add a header doc line near the other env docs (tests/fake-tmux:3-7):

   ```bash
   # FAKE_TMUX_ACTIVITY — lines "name|epoch" for #{session_activity} (default 0)
   ```

2. Add a lookup helper next to `_lookup_meta` (after it, before
   `_active_window_index`):

   ```bash
   _lookup_activity() {
     # print epoch for session $1 from FAKE_TMUX_ACTIVITY ("name|epoch"); default 0
     local name="$1" line mname rest
     [[ -z "${FAKE_TMUX_ACTIVITY:-}" ]] && { printf '0\n'; return 0; }
     while IFS= read -r line; do
       [[ -z "$line" ]] && continue
       mname="${line%%|*}"
       rest="${line#*|}"
       if [[ "$mname" == "$name" ]]; then
         printf '%s\n' "$rest"
         return 0
       fi
     done <<< "$FAKE_TMUX_ACTIVITY"
     printf '0\n'
   }
   ```

3. In the `display-message` handler's `case "$format"` block, add an arm for
   `#{session_activity}` **immediately after** the `*'#{pane_current_command}'*)`
   arm (tests/fake-tmux, the `printf '%s\n' "$_cmd"` arm shown in "Current
   state"):

   ```bash
         *'#{session_activity}'*)
           _lookup_activity "$name"
           ;;
   ```

   (`#{session_activity}` matches none of the earlier arms, so this arm is only
   reached by an explicit activity query; the unconditional `_lookup_meta "$name"`
   call earlier in the handler is harmless here.)

**Verify**: `bash -n tests/fake-tmux` → exit 0. Direct check:

```bash
FAKE_TMUX_ACTIVITY=$'alpha|100\nbeta|200' bash tests/fake-tmux display-message -p -t '=beta' '#{session_activity}'
```

Expected: `200`. With an unknown name or unset env → `0`.

### Step 7: Add the picker-ordering tests (t36–t39)

Add four test functions to `tests/test-repo-session.sh` (model them on the
existing `t8`/`t20`/`t36`-style: `setup`/`teardown`, `ok`/`fail`, LIB sourcing
via `REPO_SESSION_LIB=1`, integration via subprocess + `FAKE_TMUX_*`). Insert
them before the dispatch block at the bottom.

```bash
# ---- t36: FERRY_PICKER_SORT=mru → global no-fzf menu lists MRU session first ----
t36() {
  setup
  local out first
  export FERRY_NO_FZF=1
  export FERRY_BANNER=off
  export FERRY_PICKER_SORT=mru
  export FAKE_TMUX_SESSIONS=$'alpha\nbeta'
  export FAKE_TMUX_META=$'alpha|Awin|1w detached bash\nbeta|Bwin|1w detached bash'
  export FAKE_TMUX_ACTIVITY=$'alpha|100\nbeta|200'   # beta most recent
  out=$(printf 'q\n' | bash "$RS" 2>/dev/null)        # global picker (no repo)
  first=$(printf '%s\n' "$out" | grep -E '^1\)' | head -1)
  if [[ "$first" == *beta* ]]; then
    ok t36
  else
    fail t36 "first=[$first] out=[$out]"
  fi
  teardown
}

# ---- t37: --list stays sort -V even with activity set (byte-stable order) ----
t37() {
  setup
  local out line1
  export FAKE_TMUX_SESSIONS=$'beta\nalpha'
  export FAKE_TMUX_META=$'alpha|Awin|1w detached bash\nbeta|Bwin|1w detached bash'
  export FAKE_TMUX_ACTIVITY=$'alpha|100\nbeta|200'   # beta most recent, but --list ignores it
  out=$(bash "$RS" --list 2>/dev/null)
  line1=$(printf '%s\n' "$out" | grep -E '^1\)' | head -1)
  if [[ "$line1" == *alpha* ]]; then
    ok t37
  else
    fail t37 "line1=[$line1] out=[$out]"
  fi
  teardown
}

# ---- t38: build_session_rows default mode = 6 fields even with activity set ----
t38() {
  setup
  local rows fields f1 f2
  export FAKE_TMUX_SESSIONS=$'alpha\nbeta'
  export FAKE_TMUX_META=$'alpha|Awin|1w detached bash\nbeta|Bwin|1w detached bash'
  export FAKE_TMUX_ACTIVITY=$'alpha|100\nbeta|200'
  export REPO_SESSION_TMUXBIN="$FAKE"
  rows=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    build_session_rows
  )
  fields=$(printf '%s\n' "$rows" | head -1 | awk -F'\t' '{print NF}')
  f1=$(printf '%s\n' "$rows" | head -1 | cut -f1)
  f2=$(printf '%s\n' "$rows" | sed -n '2p' | cut -f1)
  if [[ "$fields" -eq 6 ]] && [[ "$f1" == "alpha" ]] && [[ "$f2" == "beta" ]]; then
    ok t38
  else
    fail t38 "fields=$fields f1=[$f1] f2=[$f2] rows=[$rows]"
  fi
  teardown
}

# ---- t39: _ferry_relage compact tokens (now/m/h/d/empty) ----
t39() {
  setup
  local out
  export REPO_SESSION_TMUXBIN="$FAKE"
  out=$(
    export REPO_SESSION_LIB=1
    # shellcheck source=/dev/null
    source "$RS"
    printf '[%s][%s][%s][%s][%s]\n' \
      "$(_ferry_relage 99970 100000)" "$(_ferry_relage 99400 100000)" \
      "$(_ferry_relage 92800 100000)" "$(_ferry_relage 1 172801)" \
      "$(_ferry_relage '' 100000)"
  )
  if [[ "$out" == '[now][10m][2h][1d][]' ]]; then
    ok t39
  else
    fail t39 "out=[$out]"
  fi
  teardown
}
```

Then register them in the runner dispatch at the very bottom of the file. The
current tail is:

```bash
t29; t30; t31; t32
t33; t34; t35
exit $FAIL
```

Change it to add a line before `exit $FAIL`:

```bash
t29; t30; t31; t32
t33; t34; t35
t36; t37; t38; t39
exit $FAIL
```

**Verify**: `bash -n tests/test-repo-session.sh` → exit 0, then
`bash tests/test-repo-session.sh` → lines `ok t36`, `ok t37`, `ok t38`,
`ok t39` all present, **no `FAIL`**, and every prior `t1`…`t35` still `ok`.

### Step 8: Full verification

Run the whole suite and lint.

**Verify**:
- `bash tests/run.sh` → exit 0 (no `FAIL` in any test file).
- `bash -n bin/repo-session && bash -n tests/fake-tmux && bash -n tests/test-repo-session.sh` → exit 0.
- `shellcheck bin/repo-session` → exit 0 (skip with a note if `shellcheck` is
  not on PATH in your environment).

## Test plan

New tests in `tests/test-repo-session.sh` (registered in the dispatch line):

- **t36** — happy path for the feature: `FERRY_PICKER_SORT=mru` on the global,
  no-fzf picker with `FAKE_TMUX_ACTIVITY` set lists the most-recently-active
  session as menu entry `1)`.
- **t37** — the regression guard the whole plan hinges on: `--list` stays
  `sort -V` (alphabetical) even when activity is set, i.e. the byte-stable path
  is untouched.
- **t38** — 6-field contract guard: `build_session_rows` with **no** mode
  argument still emits exactly 6 tab fields and name order, even with
  `FAKE_TMUX_ACTIVITY` present (protects the same contract `t8` asserts).
- **t39** — unit test of `_ferry_relage`'s formatting (`now`/`m`/`h`/`d`/empty).

Structural patterns to copy: `t8` (LIB sourcing + `build_session_rows` +
`awk -F'\t' NF`), `t20`/`t9` (subprocess `--list`), `t6` (no-fzf menu driven by
piped input). The `fake-tmux` activity plumbing (step 6) is what makes t36/t37/t38
observable.

Verification: `bash tests/run.sh` → exit 0 including the 4 new tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `bash tests/run.sh` exits 0 (all test files, including t36–t39, pass).
- [ ] `bash -n bin/repo-session`, `bash -n tests/fake-tmux`,
      `bash -n tests/test-repo-session.sh` each exit 0.
- [ ] `shellcheck bin/repo-session` exits 0 (or is unavailable and noted).
- [ ] `t8` and `t20` still pass unchanged (6-field row + `--list` byte-stable).
- [ ] `grep -c 'build_session_rows "\$repo"' bin/repo-session` → `0`;
      `grep -c 'build_session_rows "\${repo:-}"' bin/repo-session` → `1`
      (only `print_list` calls the default form).
- [ ] Default `FERRY_PICKER_SORT` is `name`; with it unset the picker order and
      the age-free `--list` are identical to pre-change behavior.
- [ ] `config.example` and the README config table both document
      `FERRY_PICKER_SORT`.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row updated (unless a reviewer owns the index).

## STOP conditions

Stop and report back (do not improvise) if:

- **Plan 02 has not landed.** `build_session_rows` still matches the **pre-02**
  excerpt in "Current state" (name fetch via `list-sessions -F '#{session_name}'`
  + per-field `display-message` loop, no single multi-field `-F`), or `plans/`
  contains no plan 02. This plan is `Depends on: 02`; report and wait.
- The code at the "Current state" locations doesn't match the excerpts in a way
  this plan does **not** explain (i.e. drift beyond plan 02's expected rewrite).
- You cannot locate, in the post-02 `build_session_rows`, both (a) the point
  where the `names` list is produced/sorted and (b) the single 6-field row-emit
  `printf` — i.e. plan 02's rewrite is unrecognizable relative to this plan's
  hooks.
- **`#{session_activity}` cannot be modeled in `tests/fake-tmux` without
  touching the existing `FAKE_TMUX_META` / `_lookup_meta` parsing.** (The step-6
  design keeps it fully additive; if for any reason it collides, stop rather
  than modify meta parsing.)
- Adding the mode argument or the 7th field makes `t8` or `t20` fail (the
  default/`--list` output changed) and a reasonable fix does not restore them.
- Any verification command fails twice after a reasonable fix attempt.
- The change appears to require editing an out-of-scope file (`print_list`,
  `bin/mossferry`, `install.sh`, `lib/green-ui.sh`, or the `--list` ordering).

## Maintenance notes

For whoever owns this code next:

- **Plan-02 coupling / deliberate deviation from the brief.** The originating
  brief suggested adding `#{session_activity}` to plan 02's single
  `list-sessions -F` format string. This plan instead fetches activity with
  per-session `display-message` calls (for both the MRU re-sort and the age
  column), so plan 05 does not hard-depend on plan 02's exact `-F` string —
  which did not exist at planning time and could not be quoted. The cost is a
  couple of extra tmux round-trips per picker render (interactive path, not a
  hot loop). **Follow-up optimization (deferred on purpose):** once plan 02's
  `-F` is stable, fold `#{session_activity}` into that single fetch and drop the
  per-session `display-message` calls in `build_session_rows` (the MRU re-sort
  block and the age fetch in the emit branch). Keep the mode/field-count
  contract identical when you do.
- **The 6-field vs 7-field contract is load-bearing.** Fields 1–6 must stay
  byte-identical for non-picker modes (`t8`, `print_list`, `--list`). The age is
  strictly field 7 and strictly picker-only. `preview_target` must remain field
  6 or the fzf `--preview {6}` breaks. A reviewer should scrutinize that the
  non-picker `printf` branch is byte-identical to plan 02's line and that no
  code path leaks the 7th field to a 0-arg/1-arg call.
- **MRU is global-only by design.** The repo-scoped (`repo`, `repo-2`, …) picker
  intentionally keeps stable slot order. If someone later wants repo-scoped MRU,
  relax the `[[ -z "$repo" ]]` guard in `run_picker` and add a scoped test.
- **`FAKE_TMUX_ACTIVITY` default is `0`.** Existing tests that don't set it get
  epoch `0` → in MRU mode all sessions tie and fall back to name `sort -V`, so
  they behave exactly as before. Keep that default if you extend the stub.
