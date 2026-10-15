---
type: spec
summary: "Reboot-proof hosts: repo-session --snapshot (systemd user timer, 60 s) records every tmux window with its folder and, for Claude Code panes, the conversation id read from ~/.claude/sessions/<pid>.json. After a reboot the picker shows a ♻ restore row; picking it recreates the chosen sessions with `claude --resume <id>`, staggered and load-aware, then runs restore.d hooks."
tags: [picker, restore, snapshot, claude, reboot]
status: approved
created: 2026-10-15
---

# Snapshot + restore — design

## Why

On 2026-10-15 the host was force-shut down with 11 Claude Code sessions open
in tmux. The conversations survived on disk, but nothing recorded *which*
tmux session held *which* conversation. Recovery took an hour of grepping
transcripts for `customTitle`. Doing everything at once also drove load from
2 to 31.

Claude Code already keeps the missing mapping while a session is alive.
`~/.claude/sessions/<pid>.json` holds `sessionId`, `cwd`, `name` and
`"tmux":"<session>:@<window>.%<pane>"`. The file is deleted when the process
dies. mossferry only has to copy that knowledge out regularly, and offer to
replay it.

## Success

After a reboot, `ferry <host>` shows `♻ restore N sessions from <time>`. One
Enter (plus an optional deselect) brings every chosen tmux session back with
its windows, folders, names and Claude conversations. Starts are spaced out so
the host stays responsive. Nothing restores itself without the operator
pressing the row.

## Non-goals

- Pane splits, layouts and scrollback (tmux-resurrect territory). One pane
  per window is restored.
- Replaying arbitrary commands. Non-Claude windows get `FERRY_DEFAULT_CMD`,
  never the command that was running.
- Grok or other CLIs. Kind detection is one function, so it can grow later.
- Product-specific revival (Syndcast ext containers, dogfood lanes). Those go
  in `restore.d/` hooks owned by the operator, not in this OSS repo.
- Automatic restore at boot.

## Components

All new logic lives in **`lib/snapshot.sh`**, sourced by `bin/repo-session`
the same way `lib/servers.sh` is. repo-session only gains flag parsing and the
picker row.

### 1. Snapshot (`repo-session --snapshot`)

- **Where:** `${XDG_STATE_HOME:-$HOME/.local/state}/mossferry/snapshots/<epoch>.tsv`,
  or `FERRY_STATE_DIR` when set. Write to a temp file, then `mv`.
- **Format** (v1, tab-separated, bash 3.2 readable):
  ```
  # mossferry-snapshot v1
  # boot <boot-id>
  # taken <epoch>
  <session>\t<window_index>\t<window_name>\t<pane_cwd>\t<kind>\t<claude_id>\t<claude_name>
  ```
  `kind` is `claude` or `shell`. The id and name are `-` when absent. One row
  per window, taken from the window's active pane; if any pane in the window
  runs Claude, that pane wins.
- **Claude mapping:** read every `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/*.json`.
  Keep a file only if its `pid` is alive (`kill -0`). Take the pane id from the
  part of `tmux` after the last `.` (`%12`), plus `sessionId` and `name`. Join
  on `#{pane_id}` from `tmux list-panes -a`. Pane ids survive renames; the
  session name inside `tmux` does not, which was seen live on 2026-10-15. Fields
  are read with the existing `_ferry_json_str_field`, so there is no node or jq
  dependency.
- **Boot id:** Linux `/proc/sys/kernel/random/boot_id`; macOS the `sec` value
  of `sysctl -n kern.boottime`; otherwise `unknown`.
- **Churn control:** when the rows equal the newest snapshot from the same
  boot, rewrite that file's `# taken` line in place instead of writing a new
  file. (No `touch`: the label time then needs no portable `stat`.) Keep the newest
  200 files. No tmux server, or zero sessions,
  means no write.
- The picker also takes a snapshot in the background each time it opens, so a
  host without the timer still has a recent one.

### 2. Timer (`repo-session --snapshot-install`)

- Linux with `systemctl --user`: write `mossferry-snapshot.service` and
  `mossferry-snapshot.timer` (`OnBootSec=60`, `OnUnitActiveSec=60`) under
  `~/.config/systemd/user/`, pointing at the resolved repo-session path.
  Then `daemon-reload` and `enable --now`. Re-running it is idempotent.
- Elsewhere: print the one-line crontab entry and exit 0.
- `--snapshot-install --remove` disables the timer and deletes the units.

### 3. Pre-boot selection

The **restore source** is the newest snapshot whose boot id differs from the
current one. When the boot id is `unknown` on either side, it falls back to the
newest snapshot older than the tmux server's start time
(`#{start_time}`). **Candidates** are its sessions whose names are not live
now. Pick is per session; all windows of a picked session come back.

### 4. Picker row

- `print_picker_rows` emits `♻ restore N sessions from <Day HH:MM>` before
  `➕ new session…` when there are candidates and no dismiss marker
  (`state/restore-done-<snapshot-epoch>`) exists. It is keyed by snapshot, not
  boot id, so it also works when the boot id is `unknown`.
- **Enter** opens a second fzf: `--multi`, every candidate preselected, with a
  preview listing windows, folders and Claude names. Enter starts the restore
  in the background (`nohup repo-session --restore-run <snapshot> <names…>`,
  log at `state/restore.log`) and returns to the picker. Restored sessions
  appear as they start. Esc goes back.
- **ctrl-x on the row** writes the dismiss marker. That reuses the kill bind
  and kills nothing.
- Numbered-menu fallback gets `r) restore …`.

### 5. Restore runner (`--restore-run`, `--restore [--dry-run]`)

- One restore at a time, using `_ferry_lock_acquire` on `state/restore.lock`.
- For each picked session: skip it if it is live by then. Otherwise
  `new-session -d -s <name> -n <first window name> -c <cwd>`, then
  `new-window -t <name>: -n … -c …` for the rest. A cwd that no longer exists
  falls back to `$HOME`. Commands go via `send-keys -t "<name>:<idx>"`
  (never `=`-prefixed; that fails as a pane target):
  - claude: `claude --resume <id>`
  - shell: `FERRY_DEFAULT_CMD`
- **Pacing:** before each Claude window after the first, sleep
  `FERRY_RESTORE_STAGGER` seconds (default 15). Then wait while the 1-minute
  load is above the CPU count, capped at 300 seconds, then continue anyway.
- **Hooks:** afterwards, run every executable in `${FERRY_CONFIG_DIR}/restore.d/`
  in lexical order. Each gets the snapshot path as `$1` and the restored names
  in `FERRY_RESTORED_SESSIONS` (space-separated). A failing hook is logged and
  does not stop the others.
- Then write the dismiss marker for this boot.
- `--restore --dry-run` prints the plan (sessions, windows, commands) and does
  nothing. `--restore` without `--dry-run` runs everything in the foreground,
  for scripts and ssh.

## Config keys (all optional)

`FERRY_STATE_DIR`, `FERRY_RESTORE_STAGGER`. Keep-count (200), load ceiling
(CPU count, 300 s max wait) and the resume command are fixed: fewer knobs,
fewer ways to misconfigure a recovery path that runs once a year.
Documented in `config.example` and `docs/configuration.md`.

## Error handling

- Unreadable or partial session json → that pane is `shell`. The snapshot
  still writes.
- Claude Code changes the sessions file shape → every pane degrades to
  `shell`, and restore still rebuilds sessions and folders. Tests pin the
  parser to the shape observed on Claude Code 2.1.300.
- A missing snapshot dir, no tmux, or no candidates → no row, exit 0.
- `claude --resume` on a deleted conversation fails visibly inside that window.
  That is acceptable and leaves a shell for the operator.

## Testing

`tests/test-snapshot.sh` sources `lib/snapshot.sh` directly with a test-local
tmux stub (pane model, `-P` targets, call log). `fake-tmux` is tuned for the
picker and has no pane model. Temp HOME and state dir:

- snapshot rows from fake panes plus a fixture sessions json (live pid = `$$`),
  a stale pid ignored, a renamed session still joined by pane id
- identical content touches instead of writing; rotation keeps N
- pre-boot selection by boot id, and the `unknown` fallback
- candidates exclude live names; the row appears and hides; the dismiss marker
- `--restore --dry-run` plan text; `--restore-run` issues the exact
  new-session / new-window / send-keys sequence with stagger 0
- hooks run in order with args; a failing hook does not stop the next
- `--snapshot-install` writes units into a temp `XDG_CONFIG_HOME` with a stubbed
  `systemctl`

All of it must pass under macOS bash 3.2 rules (see decision
`2026-07-30-macos-bash32-portability`).

## Rollout

Bump the version to 2.9.0, add a CHANGELOG entry, and update the docs pages
(`command-reference`, `configuration`, `troubleshooting` "after a reboot"
section). Recollect the zones repo-session, install-config and tests. Shipping
(push, plus `npm i -g github:muslewski/mossferry` on the host) waits for the
operator's word, per `desk:ship=human-end-gate`.
