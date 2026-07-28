# 04 — Local binary / docs evidence: Grok voice + wrap

**Collected:** 2026-07-24 on manjaro (Linux) + `ssh mac` (macOS aarch64)  
**Grok version (both hosts):** `0.2.111 (94172f2aa4…)` stable  
**Method:** local docs under `~/.grok/docs/`, `CHANGELOG.md`, `grok doctor --json`, `strings` on the static/Mach-O binaries, controlled env probes, mossferry source (`bin/mossferry`).  
**Not used as primary:** marketing web pages.

Raw dumps: `.firecrawl/grok-voice-research/raw/linux-doctor.json`, `linux-doctor-with-osc52-sink.json`, `mac-doctor.json`.

---

## 1. Binary / path inventory (Mac + Linux)

### Linux (manjaro)

| Item | Path / value |
|------|----------------|
| User-facing `grok` | `/home/kento/.local/bin/grok` — **bash profile router** (sets `GROK_HOME` from sticky profile, then `exec`s real binary) |
| Real binary | `/home/kento/.local/bin/grok.real` → same content as downloads |
| Official install link | `~/.grok/bin/grok` → `../downloads/grok-0.2.111-linux-x86_64` |
| Agent link | `~/.grok/bin/agent` → same binary |
| Binary type | ELF 64-bit LSB pie, **static-pie**, stripped, ~156 MB |
| BuildID | `7c08fa42d62484cf04745324eb1a47da46526f26` |
| Docs | `~/.grok/docs/user-guide/` (22 chapters; voice/wrap concentrated in `21-terminal-support.md`) |
| Config | `~/.grok/config.toml` (and profile homes under `~/.grok-profiles/*`) |
| Leader socket default | `~/.grok/leader.sock` (also `GROK_LEADER_SOCKET` / `--leader-socket`) |
| Copy backup | `~/.grok/last-copy.txt` (`GROK_COPY_FILE`) |

Older downloads still present: `grok-0.2.106-linux-x86_64`, `grok-linux-x86_64`.

### macOS (MacBook / `mac`)

| Item | Path / value |
|------|----------------|
| Official install | `~/.grok/bin/grok` → `../downloads/grok-0.2.111-macos-aarch64` |
| Binary type | Mach-O 64-bit arm64, ~123 MB |
| PATH wiring | `~/.zshrc` installer block: `export PATH="$HOME/.grok/bin:$PATH"` |
| Non-interactive bare PATH | `/usr/bin:/bin:/usr/sbin:/sbin` — **`grok` not found** unless login/interactive zsh loads `.zshrc` |
| Ghostty | `/Applications/Ghostty.app`, bundle id `com.mitchellh.ghostty` |
| Mic devices seen by doctor | Default input **AirPods Pro** (`24000 Hz, 1 ch, F32`); also MacBook Air Microphone, iPhone Microphone |
| mossferry client | `~/.local/bin/ferry` / `mossferry`; config `~/.config/mossferry/config` |

### Crates visible inside the binary (voice/wrap-relevant)

From `strings` source paths:

- `xai_grok_voice` — STT + capture (`audio/capture_linux.rs`, `audio/capture.rs`, `audio/capture_subprocess.rs`, `audio/pipe.rs`, `stt/streaming.rs`, `pipeline.rs`, `auth.rs`, `config.rs`)
- `xai_grok_pager::pty_wrap` — `grok wrap` PTY layer
- `xai_grok_pager::wrap_filter` — OSC 52 / wrap image filter
- `xai_grok_pager_render::clipboard` — native + OSC 52 + backup file
- macOS audio: **cpal 0.15.3** + **coreaudio-rs** (host/coreaudio/macos)
- clipboard: **arboard** (Linux X11/Wayland data-control); macOS **pbcopy** path in doctor

`leader.sock` / `GROK_LEADER_SOCKET` is the multi-client **leader process** IPC, **not** the wrap clipboard channel.

---

## 2. Voice pipeline facts (docs + strings)

### User-facing entry points

| Entry | Behavior |
|-------|----------|
| `/voice` | Toggle dictation (slash help: *“Toggle dictation (Ctrl+Space/F8; Esc/Enter to stop)”*) |
| `Ctrl+Space` | Primary chord (may conflict with macOS input-source switching) |
| `F8` (or `Fn+F8` on laptops) | Alternate chord when Ctrl+Space is stolen |
| Esc / Enter | Stop recording (voice steals Esc before cancel/clear/rewind) |
| Settings | **Voice capture:** Toggle vs Hold-to-talk (hold needs Kitty keyboard protocol) |
| Settings | **Voice language:** Grok STT locale (en default; System → supported STT lang; many languages listed in binary) |

Config keys persisted (from binary): `voice_capture_mode`, `voice_stt_language`.  
Feature flag: `features.voice_mode` / env **`GROK_VOICE_MODE`**.

### Capture is always local to the grok process host

Voice does **not** ride SSH/mosh. The machine that runs the `grok` binary opens the mic.

### Linux capture (`capture_linux.rs`)

Priority chain of **external recorders** on `PATH`:

1. **`pw-record`** (PipeWire) — doctor label: `"system recorder; uses the audio server's default input"`
2. **`parec`** (PulseAudio utils)
3. **`arecord`** (ALSA utils)

Error if none found:

> `no microphone recorder found on PATH: install pipewire (pw-record), pulseaudio-utils (parec), or alsa-utils (arecord)`

Manjaro has all three; doctor reports:

```json
"voice": {
  "status": "available",
  "name": "pw-record",
  "detail": "system recorder; uses the audio server's default input"
}
```

PCM is read from the child stdout (`audio/pipe.rs`); messages include `voice capture stream (subprocess) produced no stdout`, `voice capture dropped PCM chunks (slow consumer)`.

### macOS capture (`capture.rs` + `capture_subprocess.rs`)

- Uses **cpal → CoreAudio** (default input device).
- Doctor shows real device name + format, e.g. `AirPods Pro (24000 Hz, 1 ch, F32)`.
- Default path (0.2.111): **short-lived mic-helper subprocess** per dictation (CHANGELOG: lower memory; re-exec of same binary with helper flags such as `--device-info` / mic mode). Helper protocol strings: `READY` / `ERR`, `oversized mic helper header`, `mic-helper`.
- **`GROK_VOICE_CAPTURE=inprocess`** forces legacy in-process capture for debugging.
- Fallback strings: `mic helper unavailable; falling back to in-process capture`, `voice capture forced in-process (=inprocess)`.
- Permission: macOS feeds **silence** (not an error) when the **host terminal app** lacks Microphone TCC. Docs name Ghostty, iTerm2, etc. — **not** the grok binary. Fix: System Settings → Privacy & Security → Microphone → enable terminal → **restart terminal**. Passive doctor **cannot** detect denied grant.

### STT path (`stt/streaming.rs`)

- Streaming speech-to-text over **TLS WebSocket** (`wss://…`).
- Refuses plaintext: `voice requires a TLS endpoint (https:// / wss://). Refusing to send the bearer token over a plaintext connection.`
- Events: Created / Partial / Error / Done; interim results + endpointing config.
- Auth via Grok session credentials (same stack as the rest of the CLI).
- ~**10 seconds** without transcript → toast **`no speech detected — voice stopped`** (+ Linux hint: check `pavucontrol` / `wpctl status`).
- 0.2.109+: distinguishes **mic delivered only silence** (macOS permission) vs **no speech detected**.

### Doctor surface

- Standalone `grok doctor` always includes **Voice** when the build can capture audio (passive device lookup only).
- In-TUI `/doctor` adds Voice section **when voice mode is on**; aliases `/terminal-setup`, `/terminal-check`, `/terminal-info`.

### What is *not* voice capture

- `ffmpeg` in the binary is for **image/video inline playback** (`Install ffmpeg to view inline`, video frames), not STT capture.
- Bundled skills `speech-to-text` / `text-to-speech` in config are unrelated product skills; can be disabled separately.

---

## 3. Wrap pipeline facts (docs + strings)

### What `grok wrap` is

CLI help (verbatim intent):

> Run any command inside a local PTY that forwards its clipboard to yours.  
> Wraps an arbitrary command … intercepts **OSC 52** clipboard escape sequences from its output, and writes them to your **local** system clipboard. … terminal size sync.  
> Experimental.

Examples: `grok wrap ssh user@host`, `grok wrap docker exec -it …`, `grok wrap kubectl exec -it …`.

Implementation modules: `pty_wrap.rs`, `wrap_filter.rs`.

### What wrap does (local side only)

1. **OSC 52 intercept** (plain + **tmux DCS** passthrough) → local clipboard (`pbcopy` on macOS, arboard / wl-copy / xclip on Linux).
2. **Terminal hygiene** on dirty disconnect: reset mouse reporting, alternate screen, etc., so a dropped remote TUI does not leave the local terminal broken.
3. **Image paste over wrap** (CHANGELOG 0.2.108): custom OSC payload token **`999;GrokWrapClipboardImage`**; env marker **`GROK_WRAP_IMG`** appears next to bracketed-paste style `[201~` in strings. Allows image clipboard into headless remotes when wrap is the local sink.

### What wrap does *not* do

- Does **not** forward the Mac microphone.
- Does **not** replace mosh’s roaming semantics when you use mosh as the inner transport.
- Is **not** `leader.sock` (multi-session agent leader).

### Related: `grok ssh`

README still documents `grok ssh` as macOS OSC-52 passthrough for Apple Terminal → `pbcopy`. Terminals with native OSC 52 (iTerm2, Ghostty, Kitty, WezTerm, Alacritty) get plain `ssh`. The general/modern entry is **`grok wrap <cmd>`**; doctor fix is **`grok doctor fix ssh-wrap`** (alias shell `ssh` → `grok wrap ssh` on local machine only).

### Remote clipboard write routes (inside remote grok)

Up to three legs (`21-terminal-support.md` + doctor JSON):

| Route | Doctor field | Notes |
|-------|--------------|-------|
| native | `nativeRoute`, `nativeTool` | Linux: arboard; Mac: pbcopy. Over SSH often `nativePreflight: remote_only` |
| tmux | `tmuxRoute` | `tmux load-buffer` when inside tmux |
| OSC 52 | `osc52Route` | Always inside tmux; outside: Linux / SSH / no-display containers |

Kill switches: `GROK_CLIPBOARD_NO_OSC52=1`, `GROK_CLIPBOARD_NO_DATA_CONTROL=1`.  
Backup file always: `~/.grok/last-copy.txt` / `GROK_COPY_FILE`.

### `wrapSink` detection (critical)

Doctor field `clipboard.wrapSink` / plain line **`wrap: off|on`**.

Binary reads **`GROK_OSC52_SINK`** and **`LC_GROK_OSC52_SINK`** (`clipboard/mod.rs` + `pty_wrap.rs`).  
`LC_*` prefix is the classic OpenSSH-forwardable form (`AcceptEnv LC_*`).

**Controlled probe (Linux 0.2.111):**

| Env | `wrapSink` |
|-----|------------|
| unset | `false` |
| `LC_GROK_OSC52_SINK` set to any value including **empty string** | `true` |
| same for `GROK_OSC52_SINK` | `true` |

Also flips `osc52Capability` toward confirmed/supported when sink vars present.

**Wrap child env probe:** `grok wrap bash -c '…dump /proc/$$/environ…'` showed **no** `GROK_OSC52_SINK` / `LC_GROK_OSC52_SINK` injection in this build/environment — only `GROK_AGENT=1` (+ profile `GROK_HOME`).  
So: **OSC intercept can still work** (wrap filters child *output*), but **remote doctor still shows `wrap: off`** unless something sets those env vars into the remote process environment (and SSH forwards `LC_*`). This matches “remote grok started by ferry sees wrap off” even when ferry prefixes `grok wrap`.

`GROK_WRAP_NONE` exists in the binary (likely disables wrap-related behavior; not deeply exercised here).

### Contextual tip / config

- Over SSH without wrap sink: one-time tip + doctor finding `terminal.ssh-wrap`.
- Suppress tip only: `[ui.contextual_hints] ssh_wrap = false` (does not hide doctor finding).
- Auto alias: `grok doctor fix ssh-wrap` → local `~/.bashrc` / `.zshrc` / fish (not Windows).

---

## 4. Doctor / JSON field dump

### Linux manjaro (SSH session context, tmux, no wrap sink)

```json
{
  "schemaVersion": "1",
  "facts": {
    "terminal": { "name": "unknown", "xtversion": { "status": "unavailable", "value": null } },
    "multiplexer": { "kind": "tmux", "byobu": null },
    "ssh": true,
    "clipboard": {
      "nativeRoute": true,
      "nativeTool": "arboard",
      "nativePreflight": "remote_only",
      "tmuxRoute": true,
      "osc52Route": true,
      "osc52Capability": "unknown",
      "wrapSink": false,
      "displayServer": "unknown",
      "containerNoDisplay": false,
      "dataControl": "not_applicable",
      "delivery": "confirmed",
      "fix": null
    },
    "voice": {
      "status": "available",
      "name": "pw-record",
      "detail": "system recorder; uses the audio server's default input"
    }
  },
  "findings": [
    { "id": "terminal.limited-color", "disposition": "issue", ... },
    {
      "id": "terminal.ssh-wrap",
      "disposition": "recommendation",
      "message": "Running over SSH without `grok wrap` -- clipboard copies depend on the terminal's escape-sequence support, and a dropped connection can leave your local terminal in a bad state",
      "remediation": { "fix": "grok wrap ssh <host>" },
      "automaticRemediation": { "fixId": "terminal.ssh-wrap", "command": "grok doctor fix terminal.ssh-wrap" }
    }
  ]
}
```

With `LC_GROK_OSC52_SINK=1 GROK_OSC52_SINK=1`: **`wrapSink: true`**, finding set changes (ssh-wrap recommendation goes away when sink is detected).

### macOS (`ssh mac` → `~/.grok/bin/grok doctor --json`)

```json
"clipboard": {
  "nativeRoute": true,
  "nativeTool": "pbcopy",
  "nativePreflight": "remote_only",
  "tmuxRoute": false,
  "osc52Route": true,
  "osc52Capability": "unknown",
  "wrapSink": false,
  "displayServer": "quartz",
  "delivery": "unverified",
  "fix": "grok wrap <ssh command> or /minimal"
},
"voice": {
  "status": "available",
  "name": "AirPods Pro",
  "detail": "24000 Hz, 1 ch, F32"
}
```

(Note: doctor over SSH to Mac still sets `ssh: true` / remote_only preflight because the doctor process itself is under SSH.)

---

## 5. Env vars and detection markers

### Voice

| Variable / marker | Role |
|-------------------|------|
| `GROK_VOICE_MODE` | Feature toggle (`features.voice_mode`) |
| `GROK_VOICE_CAPTURE=inprocess` | Force legacy in-process mic capture (macOS helper bypass) |
| `voice_capture_mode` | Config: toggle vs hold-to-talk |
| `voice_stt_language` | Config: STT locale |
| Recorders | `pw-record`, `parec`, `arecord` on PATH (Linux) |
| Helper mode strings | `mic-helper`, `READY`/`ERR`, `--device-info`, `--rate=` |

### Wrap / clipboard

| Variable / marker | Role |
|-------------------|------|
| `GROK_OSC52_SINK` | Presence ⇒ `wrapSink=true` |
| `LC_GROK_OSC52_SINK` | Same; intended to survive SSH `AcceptEnv LC_*` |
| `GROK_WRAP_IMG` | Image-over-wrap path |
| `GROK_WRAP_NONE` | Wrap-related disable (binary marker) |
| `GROK_CLIPBOARD_NO_OSC52` | Kill OSC 52 emission |
| `GROK_CLIPBOARD_NO_DATA_CONTROL` | Disable Wayland data-control protocol |
| `GROK_COPY_FILE` | Override copy backup path |
| OSC token | `999;GrokWrapClipboardImage` |
| Doctor finding | `terminal.ssh-wrap` / fix id same |

### Unrelated but adjacent

| Variable | Role |
|----------|------|
| `GROK_LEADER_SOCKET` / `~/.grok/leader.sock` | Leader process IPC |
| `GROK_AGENT=1` | Seen under wrap child env in probe (agent mode marker) |
| `GROK_HOME` | Config/state home (profiles router sets this) |

---

## 6. Hard constraints for MacBook → Manjaro ferry

### Topology

```
[Mac Ghostty] --(mosh|ssh)-- [manjaro tmux] --(local process)-- [grok on manjaro]
     ^ wrap must live HERE if used at all              ^ mic + native clipboard are HERE
```

### Voice constraints (cannot be fixed by wrap)

1. **Mic capture binds to the host running `grok`.** Remote manjaro grok → `pw-record` on manjaro’s default input — **not** AirPods on the Mac.
2. **macOS TCC is per terminal app** (`com.mitchellh.ghostty`, iTerm, …). Irrelevant for remote-manjaro voice; only matters if grok runs natively on Mac.
3. **No OSC/SSH path carries PCM** in stock Grok. Ferry cannot “turn on voice” for remote sessions without a **different architecture** (local Mac STT → inject text; or local Mac grok; or custom audio bridge outside Grok).
4. Hold-to-talk needs Kitty keyboard protocol end-to-end; over SSH/tmux many chords degrade.

### Wrap / clipboard constraints

1. **`grok wrap` must be the outermost local process on the Mac** around `mosh`/`ssh`. Launching grok *inside* remote tmux cannot retroactively wrap the hop.
2. **Default ferry transport is `mosh`.** Docs in mossferry itself: *“OSC 52 often stripped”*. Even with wrap filtering the local PTY, if mosh drops OSC sequences, clipboard never arrives. Prefer **`FERRY_TRANSPORT=ssh`** when clipboard fidelity matters.
3. **`wrapSink: false` on remote** is the common state: wrap may intercept OSC without advertising sink env into the remote process. Doctor still recommends ssh-wrap; tips may still fire.
4. **Apple Terminal** ignores OSC 52 entirely; Ghostty/iTerm2/Kitty/WezTerm/Alacritty have native support — wrap still helps for mode-reset + image paste + terminals without OSC.
5. **Mac PATH:** `grok` lives in `~/.grok/bin` via `.zshrc`. Non-login / minimal PATH contexts → `command -v grok` fails → `FERRY_WRAP=auto` skips wrap.
6. **Image paste Mac → remote** needs wrap’s image OSC path (0.2.108+); text paste of local selection often needs terminal-native Shift+Insert / Shift-middle-click (remote process cannot read Mac PRIMARY/CLIPBOARD).

### mossferry-specific knobs (already in product)

| Knob | Default | Effect |
|------|---------|--------|
| `FERRY_WRAP` | `auto` | Prefix interactive hop with `grok wrap` when `grok` on PATH |
| `FERRY_TRANSPORT` | `mosh` | `ssh` = better OSC 52 through wrap; no mosh roam |
| `_ferry_should_wrap` | — | `off/0/false/no` → never; `on` → require grok; `auto` → if grok exists |
| Launchers (`ctrl-g` → grok) | remote start cmd | **Orthogonal** to wrap; wrap must already surround the hop |

Matthew’s Mac config (`~/.config/mossferry/config`) currently sets host candidates and quiet default cmd; **does not set `FERRY_TRANSPORT=ssh`**, so interactive ferry stays on **mosh** unless overridden.

---

## 7. What mossferry can and cannot change (without forking Grok)

### Can change (ops / ferry layer)

| Action | Effect |
|--------|--------|
| Ensure Mac interactive PATH includes `~/.grok/bin` for ferry launches | Makes `FERRY_WRAP=auto` actually engage |
| Default or document `FERRY_TRANSPORT=ssh` for Grok clipboard sessions | Stops mosh from eating OSC 52 |
| Always `FERRY_WRAP=on` for interactive hops | Local OSC intercept + dirty-exit restore |
| Optionally export `LC_GROK_OSC52_SINK=1` into the remote environment (ssh `SendEnv` / remote shell profile) | Forces remote `wrapSink=true`, silences doctor ssh-wrap tip when accurate |
| tmux on manjaro: `set-clipboard on`, `allow-passthrough on` | Improves OSC/tmux legs |
| Mac Ghostty: Microphone permission + restart | Only if running **local** Mac grok voice |
| Install/keep `pw-record` on manjaro | Remote voice uses manjaro mic if desired |
| Ferry doctor already checks `grok wrap -h` | Can harden messaging around transport vs wrap |

### Cannot change without forking / replacing Grok

| Desire | Why blocked |
|--------|-------------|
| Remote grok hears Mac mic | Capture is local process only; no remote mic RPC in Grok |
| Make wrap inject sink env reliably | Closed-source binary behavior; our 0.2.111 probe saw no injection — can only work *around* with explicit env |
| Teach mosh to preserve OSC 52 | mosh protocol limitation; ferry can only switch to ssh or accept loss |
| Change STT endpoint / offline STT | `xai-grok-voice` talks to xAI WSS with bearer token |
| Merge wrap into remote-side grok | Wrap is deliberately **local** PTY filter |
| Use `leader.sock` as a clipboard/mic bus | Different subsystem (multi-session agent leader) |

### Practical recommendation matrix

| Goal | Setup |
|------|--------|
| Clipboard Mac ← remote grok copy | Mac: `FERRY_WRAP=on` + ideally `FERRY_TRANSPORT=ssh`; terminal with OSC 52 or wrap; manjaro tmux passthrough |
| Voice dictation with AirPods | Run **grok on the Mac** (local), or build a side-channel that pastes STT text into remote TUI |
| Voice while coding on manjaro | Plug/select mic on manjaro; use `/voice` there; expect manjaro `pw-record` device |
| Image paste into remote grok | Local wrap (0.2.108+ image path); not plain mosh |

---

## Executive summary — actual mechanism (10 bullets)

1. **Voice is local capture + cloud STT:** the grok process opens a mic on *its* host, streams PCM to xAI over **WSS**, and inserts text into the prompt — there is no SSH mic tunnel.
2. **Linux mic path** is external CLI recorders in order **`pw-record` → `parec` → `arecord`**; manjaro doctor reports `pw-record`.
3. **macOS mic path** is **cpal/CoreAudio**, preferably a **short-lived mic-helper subprocess** of the same binary; `GROK_VOICE_CAPTURE=inprocess` reverts; TCC permission belongs to **Ghostty/iTerm/…**, not Grok.
4. **UI entry:** `/voice`, **Ctrl+Space** / **F8**, stop with Esc/Enter; settings for toggle vs hold-to-talk and STT language; feature flag `GROK_VOICE_MODE`.
5. **Silence handling:** ~10s without transcript → “no speech detected — voice stopped”; macOS denied mic yields silence (called out since 0.2.109); doctor cannot see denied TCC passively.
6. **`grok wrap` is a local PTY OSC-52 (and image-OSC) interceptor + terminal-reset wrapper** around ssh/mosh/docker/kubectl — experimental; implemented in `pty_wrap` + `wrap_filter`.
7. **Remote grok detects wrap via env presence** of `GROK_OSC52_SINK` / `LC_GROK_OSC52_SINK` (`wrapSink`); 0.2.111 wrap did **not** inject these into children in our probe, so ferry sessions commonly show **`wrap: off`** even under `grok wrap`.
8. **Clipboard without wrap** still tries native + tmux + OSC 52; delivery quality depends on terminal (Ghostty OK, Apple Terminal not) and whether **mosh stripped OSC**.
9. **mossferry** can prefix `grok wrap` (`FERRY_WRAP`) and choose `ssh` vs `mosh` (`FERRY_TRANSPORT`); it **cannot** make remote grok use the Mac mic; default mosh + wrapSink gap explains “wrap off” reports.
10. **Without forking Grok**, mossferry should treat voice and wrap as separate: wrap = Mac-side clipboard/TUI hygiene; voice = either local-Mac grok, manjaro-local mic, or a custom text-injection side channel — never “ferry the mic through wrap.”

---

## Appendix A — strings inventory (hits)

| Needle | Linux binary count (approx) | Notes |
|--------|----------------------------|-------|
| `pw-record` | 2 | Linux recorder |
| `parec` | 4 | Linux recorder |
| `arecord` | 3 | Linux recorder |
| `GROK_VOICE_CAPTURE` | 1 | helper override |
| `GROK_VOICE_MODE` | present | feature flag |
| `inprocess` | 1 | capture mode |
| `GROK_OSC52_SINK` | 4 | wrap detection |
| `LC_GROK_OSC52_SINK` | 2 | SSH-friendly |
| `GROK_WRAP_IMG` | 1 | image paste |
| `GROK_WRAP_NONE` | 1 | disable marker |
| `GrokWrapClipboardImage` | 1 | OSC token |
| `ffmpeg` | present | media view, not voice |
| `cpal` / `coreaudio` | macOS binary | native capture |
| `leader.sock` | present | leader IPC only |

## Appendix B — CHANGELOG voice/wrap (0.2.108–0.2.111)

- **0.2.111:** macOS voice capture in temporary helper process (memory).
- **0.2.109:** `grok doctor fix ssh-wrap`; silence vs no-speech messaging; `/doctor` main terminal check.
- **0.2.108:** standalone `grok doctor`; **image paste over grok wrap** on headless remotes.
