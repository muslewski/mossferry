# Binary / runtime observations (grok 0.2.111 linux-x86_64)

## Source modules (path strings in binary)
- `crates/codegen/xai-grok-pager/src/pty_wrap.rs` — wrap PTY host
- `crates/codegen/xai-grok-pager/src/wrap_filter.rs` — output filter
- `crates/codegen/xai-grok-pager-render/src/clipboard/mod.rs` — clipboard routes + sink env

## Env names present in binary
- `GROK_OSC52_SINK` (4 occurrences; pty_wrap + clipboard)
- `LC_GROK_OSC52_SINK` (2 occurrences; same sites — LC_ prefix is the SSH-friendly form)
- `GROK_WRAP_IMG` / `GROK_WRAP_NONE` next to bracketed-paste markers `\x1b[200~` / `\x1b[201~`

## doctor JSON field
- `facts.clipboard.wrapSink` (boolean)
- finding id `terminal.ssh-wrap` when SSH and wrap not active

## Local probe (manjaro agent shell, TERM=dumb, over SSH)
- `grok wrap /usr/bin/sleep 15` replaced itself with sleep (no intermediate wrap process observed) — wrap can elide to plain exec in some environments (matches documented `grok ssh` behavior for native-OSC52 terminals).
- Non-ssh child did not show `GROK_OSC52_SINK` / `LC_GROK_OSC52_SINK` in environ when wrap elided.
- `grok doctor --json` on this host: `ssh: true`, `wrapSink: false`, recommendation `terminal.ssh-wrap`.
