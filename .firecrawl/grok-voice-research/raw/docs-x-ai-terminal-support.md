#### CLI

# Terminal Support

Grok draws its interface with terminal escape sequences for color, clipboard, mouse, and full-screen control, and some terminals, multiplexers, and SSH sessions handle these differently. Run `/terminal-setup` (aliases `/terminal-check`, `/terminal-info`) inside Grok to see what was detected, which clipboard routes are active, and any issues with fixes.

## Colors look wrong

Set `COLORTERM=truecolor` in your shell profile. Inside tmux, also enable 24-bit RGB:

```text
# ~/.tmux.conf
set -g default-terminal "tmux-256color"
set -as terminal-features ",*:RGB"
set -g set-clipboard on
set -g allow-passthrough on
```

The last two lines also fix clipboard and notification passthrough; reload with `tmux source-file ~/.tmux.conf`.

## Copy does not reach my clipboard

Grok writes to the native OS clipboard, to the tmux paste buffer inside tmux, and emits OSC 52 for remote cases (SSH, containers, Linux). Two common blockers:

* iTerm2 ignores OSC 52 until you enable Settings → General → Selection → "Applications in terminal may access clipboard".
* Apple Terminal ignores OSC 52 entirely, so copies over SSH cannot reach your local clipboard. Wrap the remote command instead: `grok wrap ssh user@host` runs it in a local PTY that intercepts OSC 52 and writes to your clipboard. The same works for `grok wrap docker exec ...` and `grok wrap kubectl exec ...`. `grok wrap` is experimental.

## Keyboard chords do not work

* WezTerm: add `config.enable_kitty_keyboard = true` to `wezterm.lua`, then restart — this fixes `Ctrl+Enter` (interject) and `Shift+Enter` (newline).
* VS Code, Cursor, Windsurf, and Zed terminals cannot distinguish `Shift+Enter` from `Enter`; use `Alt+Enter` for newlines. The same applies to VS Code over SSH.
* Zellij intercepts many Ctrl chords. On Zellij 0.41+, switch to the "Unlock-First (non-colliding)" preset (`Ctrl+O` → `c` → Change Mode Behavior), then `Ctrl+G` temporarily unlocks Zellij when you need it.
* Apple Terminal: `Ctrl+O` interjects (it lacks the Kitty keyboard protocol for `Ctrl+Enter`).

## No fullscreen, or mouse scrolling stops

Grok intentionally runs inline under Zellij and tmux control mode (`tmux -CC`); force fullscreen with `alt_screen = "always"` under `[terminal]` in `~/.grok/pager.toml`, or disable it anywhere with `--no-alt-screen`.

If your terminal's native scrollbar takes over, mouse reporting is off: Apple Terminal re-enables it under View → Allow Mouse Reporting (`Cmd+R`); iTerm2 under Settings → Profiles → Terminal → "Enable mouse reporting".

Still stuck? Run `/feedback`.
