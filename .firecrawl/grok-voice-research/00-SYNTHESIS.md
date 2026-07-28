# Grok CLI voice + wrap — research synthesis (2026-07-24)

Evidence from: local Grok 0.2.111 binaries (Linux + macOS), `grok doctor --json`,
shipped `~/.grok/docs`, official docs.x.ai / x.ai changelog, parallel web research.
Firecrawl cloud: **0 credits** this cycle — used web fetch + local docs instead.

## How voice actually works

```
[User chord] /voice | Ctrl+Space | F8
       │
       ▼
[Grok process on THIS host]
  Linux: spawn pw-record → (fallback) parec → arecord
         = PipeWire/Pulse/ALSA **default input on the host running grok**
  macOS: short-lived mic helper (cpal/CoreAudio); TCC on **terminal app**
       │
       ▼ PCM stream
[xai-grok-voice] WSS STT (stt_ws_path / api_base must be TLS)
       │
       ▼ transcript events (Partial/Done)
[prompt insert]  stop: Esc | Enter | chord again
```

**Facts (binary + docs):**
- Mic is **always process-local**. No SSH/mosh/tmux audio path in Grok.
- Linux doctor on Manjaro ferry session: `"name": "pw-record"`, `"detail": "system recorder; uses the audio server's default input"`.
- macOS: permission is Ghostty/iTerm/… not the grok binary; denied TCC = silence → ~10s "no speech detected".
- Config: `voice_capture_mode` (toggle vs hold-to-talk), `voice_stt_language`, env `GROK_VOICE_MODE`, `GROK_VOICE_CAPTURE=inprocess`.
- Gate string in binary: `/voice requires SuperGrok`.
- Claude Code + VS Code Speech document the **same** remote limit: voice needs local mic; Remote-SSH does not carry audio.

## How wrap actually works

```
[Mac] grok wrap <ssh|mosh|docker …>
         │ local PTY (pty_wrap + wrap_filter)
         │  - intercept OSC 52 (+ tmux DCS) → Mac clipboard
         │  - SIGWINCH size sync
         │  - reset dirty TUI modes on exit
         │  - image paste path (GROK_WRAP_IMG / GrokWrapClipboardImage) since 0.2.108
         ▼
[remote] ssh/mosh session → tmux → grok
```

**Facts:**
- Wrap is **clipboard + terminal hygiene only**. Help text: "forwards its clipboard to yours." Zero mention of mic/audio.
- Doctor field `clipboard.wrapSink` + finding `terminal.ssh-wrap` when over SSH without wrap.
- Markers: `GROK_OSC52_SINK` / `LC_GROK_OSC52_SINK` (LC_ for SSH AcceptEnv). Probes on 0.2.111 Linux often **did not** see these injected into child env → remote may still show `wrap: off` even when wrap is parent (OSC intercept can still work).
- mosh often **strips OSC 52** → wrap around mosh cannot invent missing bytes. Prefer **ssh** for clipboard.
- mossferry already: `FERRY_WRAP=auto` → `grok wrap mosh|ssh …` when local `grok` on PATH; `FERRY_TRANSPORT=mosh|ssh`.

## What does NOT make remote voice work

| Tool | Why it fails for voice |
|------|------------------------|
| `grok wrap` | OSC 52 clipboard only |
| mosh / ssh / ferry PTY | character stream, not audio devices |
| OSC 52 / tmux set-clipboard | text clipboard, not PCM |
| Starting grok via ferry `ctrl-g` / start menu | starts **remote** grok → remote `pw-record` |

## Patterns that *could* make Mac mic feed remote Grok

Ranked for ferry product (from agent 03):

1. **Local STT → inject text** into remote tmux/Grok pane (Mac capture, paste/send-keys). Same class as VS Code/Claude remote workarounds. Does not need remote `pw-record`.
2. **Roc toolkit** (Mac CoreAudio → UDP/Tailscale → PipeWire `roc-source` on Manjaro as default input). Only clean path where stock remote `/voice` + `pw-record` hears Mac.
3. **SSH PCM pipe → PipeWire `module-pipe-source` FIFO** — prototypeable, fragile clocks.

## Mossferry can / cannot (without forking Grok)

**Can:** ensure Mac wrap PATH; prefer `FERRY_TRANSPORT=ssh` for clipboard; doctor/nudge when hop is unwrapped or mosh; optional **voice-bridge** side feature (Roc or STT-inject); document SuperGrok + Ghostty TCC.

**Cannot:** make wrap forward mic; make remote grok open Mac CoreAudio; fix voice by config alone.

## Artifact index

| File | Content |
|------|---------|
| `01-official-docs-voice.md` | Official + shipped docs on voice |
| `02-grok-wrap-mechanism.md` | Wrap PTY, detection, mossferry implications |
| `03-remote-mic-patterns.md` | Network audio / STT-inject catalog |
| `04-local-binary-evidence.md` | 0.2.111 reverse-engineering |
| `raw/` | doctor JSON, strings dumps, scrapes |
