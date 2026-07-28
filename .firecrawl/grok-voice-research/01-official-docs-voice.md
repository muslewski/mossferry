# Official Grok CLI (Grok Build) — Voice / Microphone / Dictation Research

**Date:** 2026-07-24  
**CLI version probed:** `grok 0.2.111 (94172f2aa4) [stable]`  
**Host:** Linux x86_64 (manjaro), over SSH + tmux  
**Method notes:** `firecrawl` CLI was **not on PATH** (`command not found`). Research used `web_fetch` / HTTP scrapes of official docs, the public changelog, the **shipped local user guide** under `~/.grok/docs/`, live `grok doctor`, and **read-only string extraction** from the installed binary. Raw materials: `.firecrawl/grok-voice-research/raw/`.

**Scope:** Grok **Build** interactive TUI voice *dictation* (prompt speech-to-text). This is **not** the separate product surface of Grok Voice Agent / STT/TTS developer APIs (those are enterprise audio APIs for building voice agents).

---

## 1. Sources (URLs + what each contained)

| Source | What it contained re: voice / mic / remote |
|--------|---------------------------------------------|
| [https://x.ai/build/changelog](https://x.ai/build/changelog) | **Richest public voice history.** Introduced STT dictation chords; Linux capture deps; SuperGrok/enterprise gates; macOS helper; silence vs no-speech diagnostics; auth fixes for API-key STT. |
| [https://docs.x.ai/build/cli/terminal-support](https://docs.x.ai/build/cli/terminal-support) | Terminal, clipboard, SSH, **`grok wrap`**. **No voice section.** Explicitly: wrap intercepts **OSC 52 clipboard** for remote commands. |
| [https://docs.x.ai/build/overview](https://docs.x.ai/build/overview) | Install, session, headless. **No voice.** |
| [https://docs.x.ai/build/keyboard-shortcuts](https://docs.x.ai/build/keyboard-shortcuts) | Essentials/input/scrollback chords. **Does not list Ctrl+Space, F8, or /voice.** |
| [https://docs.x.ai/build/modes-and-commands](https://docs.x.ai/build/modes-and-commands) | Slash command table. **`/voice` not listed.** |
| [https://docs.x.ai/build/settings](https://docs.x.ai/build/settings) + [reference](https://docs.x.ai/build/settings/reference) | Config layers, env vars, TOML. **No documented `GROK_VOICE_*` or `voice_*` keys** in the public reference tables (as of scrape). |
| [https://docs.x.ai/build/enterprise](https://docs.x.ai/build/enterprise) | Managed config / `requirements.toml` pins. **Does not mention voice dictation disable** (changelog does). |
| [https://docs.x.ai/developers/model-capabilities/audio/voice](https://docs.x.ai/developers/model-capabilities/audio/voice) | **Different product:** Grok Voice / STT / TTS **APIs** for builders — not CLI dictation UX. |
| Local `~/.grok/docs/user-guide/21-terminal-support.md` | **Best official-ish voice troubleshooting** shipped with the CLI. Documents `/voice`, Ctrl+Space, doctor Voice section, macOS permissions, `GROK_VOICE_CAPTURE=inprocess`. |
| Local `~/.grok/docs/user-guide/03-keyboard-shortcuts.md` | Only that **voice steals Esc** before cancel/rewind. No chord table entry. |
| Local `~/.grok/docs/user-guide/04-slash-commands.md` | **No `/voice` entry** in the prose guide (binary embeds command metadata). |
| Live `grok doctor` / `grok doctor --json` on this host | Reports **Voice → microphone: `pw-record`**, ssh yes, wrap off. |
| Binary `~/.grok/downloads/grok-0.2.111-linux-x86_64` strings | Settings copy, Linux recorder fallback chain, SuperGrok gate, STT WS path `/v1/stt`, crate paths `xai-grok-voice`. |
| `grok wrap --help` | **Clipboard + terminal restore only.** No audio/mic wording. |

Raw saves: `raw/docs-x-ai-*.md`, `raw/x-ai-build-changelog.md`, `raw/local-21-terminal-support.md`, `raw/grok-doctor.json`, `raw/binary-voice-strings.txt`.

---

## 2. How voice is activated (commands, keys, config)

### Primary UX (from changelog + embedded help strings + local terminal guide)

| Mechanism | Behavior |
|-----------|----------|
| **`/voice`** | Slash command: **toggle** dictation. Binary: `"Toggle dictation (Ctrl+Space/F8; Esc/Enter to stop)"` / command id `voice`. Works as toggle **everywhere**. |
| **`Ctrl+Space`** | Primary voice chord. |
| **`F8`** (often **Fn+F8** on laptops) | Alternate chord “where Ctrl+Space is taken, e.g. macOS input-source switching”. |
| **Esc / Enter** | Stop dictation (also listed on the slash command help). |
| **Voice capture setting** | **Toggle** (default): press Ctrl+Space/F8 to start, press again to stop. **Hold to talk**: hold Ctrl+Space/F8 to record, release to stop — **requires Kitty keyboard protocol**; otherwise falls back to toggle. |
| **Welcome screen** | Changelog v0.2.82: “Pressing voice on the welcome screen now starts a new session”. |
| **Plan mode** | v0.2.91: voice indicator and stop button remain visible/clickable during plan review. |
| **Speech result** | “Speech is transcribed straight into the prompt.” |

### Gating / availability

| Gate | Evidence |
|------|----------|
| **SuperGrok** | Binary string: **`/voice requires SuperGrok`**. Changelog historically introduced feature then later “Voice mode is now available for API-key sessions” (v0.2.97) and enterprise API-base STT (v0.2.102) — **tier/auth story evolved**; SuperGrok string still present in 0.2.111. |
| **Enterprise disable** | Changelog v0.2.102: *“Enterprise deployments can now disable voice dictation via `requirements.toml` so `/voice` and Ctrl+Space are hidden for everyone.”* |
| **Remote/feature flag** | Binary field `voice_mode_enabled` (server/remote settings style). Env **`GROK_VOICE_MODE`** appears next to other feature env switches. |

### What public docs do **not** say

- Public keyboard-shortcuts and modes-and-commands pages **omit** `/voice`, Ctrl+Space, and F8 entirely (as of 2026-07-24 scrape).
- Public settings reference **omits** voice TOML/env keys.

---

## 3. How mic capture works per platform

### Architecture (binary + local docs)

Internal crate: **`xai-grok-voice`** with modules including:

- `audio/capture_linux.rs` — Linux system recorders  
- `audio/pipe.rs` — pipe from capture process (`--rate=` seen in strings; “voice capture stream (subprocess) produced no stdout”)  
- `stt/streaming.rs` — streaming STT  
- `auth.rs`, `pipeline.rs`, `config.rs`  
- Settings keys: `voice_capture_mode`, `voice_stt_language`  
- STT client config fields: `stt_ws_path`, `stt_endpointing_ms`, `stt_interim_results`  
- Transport: **WebSocket STT** path string **`/v1/stt`** (Grok STT API; not local Whisper)

Transcription is cloud STT over the authenticated session / API key path (changelog: works with API keys, enterprise API bases, per-model keys in `config.toml`).

### Linux (explicit)

Changelog **v0.2.89**:

> “Voice dictation now works on Linux (requires pipewire, pulseaudio-utils or alsa-utils)”

Binary error / doctor strings (ordered fallback):

1. **`pw-record`** (package **pipewire**)  
2. **`parec`** (package **pulseaudio-utils**)  
3. **`arecord`** (package **alsa-utils**)

If none on `PATH`:

> `no microphone recorder found on PATH: install pipewire (pw-record), pulseaudio-utils (parec), or alsa-utils (arecord)`

Doctor description when found:

> `system recorder; uses the audio server's default input`

Live on this host (`grok doctor`):

```text
Voice
  · microphone                   pw-record (system recorder; uses the audio server's default input)
```

JSON:

```json
"voice": {
  "status": "available",
  "name": "pw-record",
  "detail": "system recorder; uses the audio server's default input"
}
```

Linux “no speech” guidance (binary toast copy):

> check the default input device and its volume in your sound settings (e.g. `pavucontrol`, or `wpctl status` on PipeWire)

Finding id: **`no-input-device`** — “Voice dictation can't capture audio — Connect or select an input device…”

Capture is a **subprocess** (not pure in-process cpal-only path on Linux for the system-recorder path).

### macOS (explicit in local guide + changelog)

- Permission is on the **terminal app** hosting Grok (Ghostty, iTerm2, …), **not** “Grok” itself. Denied apps receive **silence**.  
- **System Settings → Privacy & Security → Microphone** → enable terminal → **restart terminal**.  
- Check **Sound → Input** device/level.  
- **v0.2.111 / local docs:** capture runs in a **short-lived helper subprocess** per dictation (memory).  
- Escape hatch: **`GROK_VOICE_CAPTURE=inprocess`** forces legacy in-process capture.  
- **v0.2.109:** distinguishes **mic delivered only silence** (permission) vs **no speech detected**.

### Windows

No first-class public doc statement found in scraped materials for Windows dictation capture backend. Not asserted here.

### Doctor diagnostics

- Standalone `grok doctor` reports which microphone backend it **would** open (passive; **does not open a stream**).  
- **Cannot** detect denied macOS mic permission passively.  
- In-TUI `/doctor` (aliases `/terminal-setup`, `/terminal-check`, `/terminal-info`) shows a **Voice section when voice mode is on**.

---

## 4. What happens over SSH / tmux / remote (**explicit statements only**)

### What docs **do** say about `grok wrap` and SSH

Official terminal support (public + local) — **clipboard and terminal hygiene only**:

- `grok wrap ssh user@host` runs the command in a **local PTY** that **intercepts OSC 52** and writes to the **local clipboard**.  
- Same for `docker exec` / `kubectl exec`.  
- Wrap **restores terminal modes** if the remote TUI dies with mouse/alt-screen dirty state.  
- **Experimental.**  
- SSH sessions without wrap get a one-time tip recommending wrap for **clipboard + terminal restore**.  
- `grok doctor fix terminal.ssh-wrap` installs a local shell **ssh alias** for wrap.  
- Changelog: image paste over wrap; copy success over SSH; OSC 52 unverified on unknown terminals.

**`grok wrap --help` (verbatim scope):**

> Run any command inside a local PTY that forwards its **clipboard** to yours.  
> … intercepts **OSC 52 clipboard escape sequences** …  
> **No mention of microphone, audio, or voice.**

### What docs **do not** claim

- **No** official statement that `grok wrap` tunnels the **local Mac/laptop microphone** to a remote `grok` process.  
- **No** official statement that dictation over SSH uses the client-side mic.  
- **No** “SSH voice” or “remote dictation” guide page.

### What follows from capture design (evidence-based inference, labeled)

- Linux/macOS capture attaches to the **audio stack of the machine running the `grok` binary**.  
- On a remote Linux host (this environment), doctor reports **`pw-record` on that host**. Dictation therefore uses the **remote host’s default input**, if any — **not** automatically the Mac’s mic via wrap.  
- To use a laptop mic while coding on a remote box, official materials do **not** document a solution; that would require process-local audio (run grok locally) or an undocumented/out-of-band audio forward (not in wrap).

### tmux

- Docs discuss tmux for **clipboard passthrough** (`set-clipboard`, `allow-passthrough`) and terminal detection limits.  
- Voice chord delivery depends on the terminal/multiplexer forwarding **Ctrl+Space / F8 / Kitty protocol** (hold-to-talk needs Kitty protocol). No special “tmux voice” feature is documented.

---

## 5. Env vars / config keys

| Key | Role | Evidence strength |
|-----|------|-------------------|
| **`GROK_VOICE_CAPTURE=inprocess`** | Force legacy in-process mic capture on macOS (vs helper subprocess) | **Documented** in local `21-terminal-support.md` |
| **`GROK_VOICE_MODE`** | Feature switch sibling to other `GROK_*` feature envs | Binary env list; **not** in public settings reference table |
| **`voice_capture_mode`** | Persist setting: toggle vs hold-to-talk | Binary settings/persist keys; UI label “Voice capture” |
| **`voice_stt_language`** | STT language (en default; System; many locales) | Binary + changelog v0.2.86 “Voice language setting… Editor settings” |
| **`voice_mode` / `voice_mode_enabled`** | Runtime/feature enable | Binary |
| **`requirements.toml` (enterprise)** | Can hide `/voice` and Ctrl+Space for everyone | Changelog v0.2.102 only (exact TOML key **not** quoted publicly) |
| **STT internals** | `stt_ws_path`, `stt_endpointing_ms`, `stt_interim_results` | Binary `VoiceConfig` — not user-facing docs |

**Public settings reference** (docs.x.ai/build/settings/reference): lists many `GROK_*` vars and TOML sections — **does not document the voice keys above** as of this research.

Related non-voice (often confused): `GROK_CLIPBOARD_NO_OSC52`, `GROK_COPY_FILE`, wrap OSC52 sink vars — **clipboard only**.

---

## 6. Gaps / unknowns that need deeper reverse-engineering

1. **Exact SuperGrok vs API-key entitlement matrix** for dictation in 0.2.111 (binary still says SuperGrok; changelog added API-key paths — need live `/voice` under free/API/SuperGrok accounts).  
2. **Exact `requirements.toml` key** that disables voice (changelog names the file, not the key path).  
3. **macOS helper binary identity** (path, codesign, how it requests TCC, whether it is a nested executable or `grok` re-exec).  
4. **Windows capture backend** (WASAPI/ffmpeg/other).  
5. **Whether any audio is ever forwarded over wrap** (string search found none; confirm with wrap debug / pcap if policy requires).  
6. **Full STT auth path** when using OAuth vs `XAI_API_KEY` vs per-model keys (changelog claims all work; wire format undocumented for CLI).  
7. **Hold-to-talk exact Kitty encoding** and which terminals negotiate it for Ctrl+Space.  
8. **Public docs lag:** keyboard + slash pages omit voice; only changelog + embedded help + local terminal guide are authoritative for UX.  
9. **Open-source / third-party “grok-cli”** (e.g. superagent-ai Telegram STT, VS Code community extension with ffmpeg) are **not** official Grok Build — do not conflate.

---

## 7. Direct quotes that matter

### Dictation feature introduction (changelog v0.2.80)

> Voice dictation STT feature: uses `Ctrl+Space` or `F8`, with optional hold-to-talk on supported terminals

### Linux (changelog v0.2.89)

> Voice dictation now works on Linux (requires pipewire, pulseaudio-utils or alsa-utils)

### Enterprise hide (changelog v0.2.102)

> Enterprise deployments can now disable voice dictation via `requirements.toml` so `/voice` and Ctrl+Space are hidden for everyone

### macOS helper (changelog v0.2.111)

> Voice dictation on macOS now uses less memory by running capture in a temporary helper process

### Silence vs no speech (changelog v0.2.109)

> Voice dictation now explains when the microphone delivered only silence (macOS permission) versus no speech detected

### Local terminal guide — activation + empty transcript

> You start voice (`/voice` or `Ctrl+Space`), talk, and no words appear. After ~10 seconds without a transcript Grok stops and shows a **"no speech detected — voice stopped"** toast with fix steps.

### Local terminal guide — macOS helper env

> On macOS, capture runs in a short-lived helper subprocess (spawned per dictation) so the audio stack's memory never accumulates in the long-running TUI. If you suspect the helper itself is misbehaving, `GROK_VOICE_CAPTURE=inprocess` forces the legacy in-process capture for comparison.

### Public docs — what wrap is for

> Wrap the remote command instead: `grok wrap ssh user@host` runs it in a local PTY that intercepts OSC 52 and writes to your clipboard. The same works for `grok wrap docker exec ...` and `grok wrap kubectl exec ...`. `grok wrap` is experimental.

### wrap CLI help (clipboard-only)

> Run any command inside a local PTY that forwards its clipboard to yours.  
> … intercepts OSC 52 clipboard escape sequences from its output, and writes them to your local system clipboard.

### Binary — Linux recorder missing

> no microphone recorder found on PATH: install pipewire (pw-record), pulseaudio-utils (parec), or alsa-utils (arecord)

### Binary — SuperGrok gate

> `/voice requires SuperGrok`

### Binary — Voice capture setting

> Voice capture — How the voice chord (Ctrl+Space / F8) behaves: Toggle (press to start/stop) or Hold to talk (hold to record, release to stop; needs a Kitty-protocol terminal).

### Binary — Voice language setting

> Voice language — Speech-to-text language for voice dictation (Grok STT). English by default; System uses your locale when supported.

### Binary — F8 rationale

> Microphone capture for dictation, bound to Ctrl+Space (or F8 — handy where Ctrl+Space is taken, e.g. macOS input-source switching; use Fn+F8 on a laptop).

### SSH tip (changelog v0.2.103) — clipboard, not mic

> SSH sessions now show a one-time tip recommending `grok wrap ssh <host>` for clipboard and terminal restore

---

## Bottom line (for mossferry / remote voice design)

| Question | Official answer |
|----------|-----------------|
| Does Grok Build have voice dictation? | **Yes** — STT into the prompt via `/voice`, Ctrl+Space, F8. |
| Is wrap a mic tunnel? | **No.** Documented as **OSC 52 clipboard + terminal restore** only. |
| Where does the mic live? | **Process host** (remote Linux → `pw-record`/`parec`/`arecord` on that host; local macOS → terminal’s mic permission + helper). |
| SSH “use Mac mic while grok runs on manjaro”? | **Not documented / not wrap.** Would need local grok or out-of-band audio. |
| Best primary sources today | Changelog + local `21-terminal-support.md` + doctor + binary; **not** the public keyboard/commands pages. |

---

## Research limitations

- Firecrawl CLI unavailable; HTML scrapes may be JS-shell heavy (saved under `raw/`).  
- No interactive TUI session was driven to capture live `/voice` UI for this report.  
- Binary strings confirm presence of messages/settings; they are not a substitute for source.  
- Product surface may change quickly (changelog shows multiple voice-related ships in July 2026).
