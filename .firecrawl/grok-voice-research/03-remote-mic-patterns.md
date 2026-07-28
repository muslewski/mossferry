# Remote mic patterns for SSH / mosh / ferry (Mac → Linux)

**Date:** 2026-07-24  
**Scope:** How people get a **laptop microphone** into remote-dev / coding-agent CLIs when the agent process runs on Linux (Manjaro) but the human is on a MacBook over mosh/SSH/tmux.  
**Local fact (this fleet):** Grok doctor on remote reports voice backend `pw-record` (“system recorder; uses the audio server's default input”). Ferry guide already states mic is on Mac and terminal stream has no audio.  
**Research method:** Firecrawl CLI unavailable (0/1000 credits, HTTP 402). Completed with web search + page fetch. Raw notes under `.firecrawl/grok-voice-research/raw/`.

---

## 1. Pattern catalog

| # | Pattern name | How it works | Complexity | Latency | Mac→Linux viability for `pw-record` |
|---|--------------|--------------|------------|---------|-------------------------------------|
| A | **Local STT → text inject** | Capture mic on Mac; Whisper/native dictation → transcript; paste / OSC-52 clipboard / `tmux send-keys` / local wrap into remote TUI | Low–med | STT-bound (0.3–2s+) | **Excellent for dictation.** Does **not** feed audio; remote never sees a mic |
| B | **Roc Toolkit (roc-send + PipeWire roc-source)** | Mac `roc-send` captures CoreAudio mic → RTP/FEC to Linux; Linux loads `libpipewire-module-roc-source` as a capture **source** | Med | Tunable ~50–200 ms target | **Best real-audio path.** Source appears to PipeWire; default + `pw-record` can hear it |
| C | **Roc VAD (macOS virtual device)** | CoreAudio HAL driver: virtual speaker/mic devices; connect endpoints to remote Roc peers | Med–high (reboot, driver) | Same as Roc | Strong when you want persistent devices/GUI routing; for **mic out**, often still use `roc-send -i core://…` |
| D | **SSH raw PCM + `module-pipe-source` / FIFO** | Mac records PCM (`sox`/`ffmpeg`/`arecord` via brew); pipe over `ssh`/`nc` into Linux FIFO; PA/PipeWire pipe-source presents virtual mic | Low–med | RTT + buffer (often 50–300 ms; can glitch) | **Works.** Fragile clocks, drops, format mismatch |
| E | **SSH PCM + `snd-aloop` / ALSA loopback** | Same stream into ALSA loopback (`aplay -D hw:Loopback,1`); apps record the other half | Med | Similar to D | Works if something uses ALSA directly; PipeWire can expose loopback too |
| F | **Pulse tunnel / `PULSE_SERVER` reverse** | Classic: `ssh -R …:4713` so **remote apps use Mac’s Pulse server** | Med | High over WAN; OK on LAN/TS | **Direction usually inverted.** Docs/tools (AgentVibes, Medium Mac guides) move **remote playback → local speakers**. Mac Pulse exists via Homebrew but is a second stack; not the natural macOS path for mic |
| G | **PipeWire pulse-tunnel source** | `libpipewire-module-pulse-tunnel` `tunnel.mode=source` toward a remote Pulse TCP endpoint | Med | Default ~200 ms | **Linux↔Linux** friendly. Mac needs a Pulse-compatible server exporting the mic — rare/painful |
| H | **SonoBus / NDI-style peer audio** | P2P realtime audio app (Mac+Linux clients); route into system via JACK/ALSA/plugins | Med | Low on LAN | Viable for monitoring/music; extra hop to make default `pw-record` source |
| I | **VS Code / Cursor Speech extension** | STT **in the local UI process**; inserts text into editor/chat | Low | On-device / local | **Local UI only.** Microsoft docs: Speech extension **not** available in Remote-SSH / Dev Containers / Codespaces (extension host is remote) |
| J | **Claude Code `/voice`** | CLI holds mic on the **machine running `claude`**, streams audio to Anthropic STT | Low (when local) | Network STT | **Officially broken over SSH.** Docs: “does not work in … SSH sessions.” VS Code remote same reason |
| K | **WebRTC local capture → cloud STT → inject** | Browser/`getUserMedia` on Mac; WebRTC/WS to ASR; text lands in remote session via agent protocol | High | Realtime-capable | Great product architecture; not a drop-in for stock `pw-record` |
| L | **Terminal-only wrap / OSC 52 / plain mosh** | PTY filter for clipboard/keys | Low | n/a | **No audio channel.** Cannot carry mic samples |

**Legend for ferry/Grok:**  
- Patterns **A, I, J, K** solve **dictation** (text).  
- Patterns **B–E, G–H** solve **virtual microphone** (audio samples on Linux).  
- Grok remote default is **audio capture via `pw-record`**, so only B–E (and maybe G/H with extra wiring) make **remote Grok voice** hear the Mac mic without Grok code changes.

---

## 2. Tools and commands that are concrete

### 2.1 Roc: Mac mic → Linux PipeWire source (recommended audio path)

**Linux (Manjaro, PipeWire) — receive as virtual source**

```bash
# Arch/Manjaro package often provides modules:
# pacman -S pipewire-roc   # or ensure roc modules ship with pipewire

mkdir -p ~/.config/pipewire/pipewire.conf.d
cat > ~/.config/pipewire/pipewire.conf.d/roc-source.conf <<'EOF'
context.modules = [
  { name = libpipewire-module-roc-source
    args = {
      local.ip = 0.0.0.0
      resampler.profile = medium
      fec.code = rs8m
      sess.latency.msec = 100
      local.source.port = 10001
      local.repair.port = 10002
      # optional control: 10003 if your PW build exposes it
      source.name = "Roc Source"
      source.props = {
        node.name = "roc-source"
      }
    }
  }
]
EOF
systemctl --user restart pipewire pipewire-pulse
pw-record --list-targets   # expect "Roc Source" / roc-source
pactl set-default-source roc-source   # name may vary; use pw-cli/pactl list sources
```

**Mac — send default / mic CoreAudio device**

```bash
# build/install roc-toolkit tools, then:
# Use Tailscale IP of manjaro, e.g. 100.101.198.44
roc-send -vv \
  -s rtp+rs8m://100.101.198.44:10001 \
  -r rs8m://100.101.198.44:10002 \
  -c rtcp://100.101.198.44:10003 \
  -i "core://default"
# or pick a specific device from: system_profiler SPAudioDataType
```

**Firewall / Tailscale:** open UDP 10001–10003 on Linux for the Mac peer (or use `tailscale serve`/ACLs). Roc is designed for lossy links (FEC); better than raw TCP PCM over Wi‑Fi.

**Roc VAD (optional Mac virtual devices)**

```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/roc-streaming/roc-vad/HEAD/install.sh)"
# reboot
roc-vad info
roc-vad device add sender    # virtual *speakers* (apps play → network)
# For capturing the hardware mic toward Linux, roc-send -i core://… is the direct path.
```

### 2.2 Raw PCM over SSH into a virtual mic (`pw-record` can default to it)

**Linux once:**

```bash
pactl load-module module-pipe-source \
  source_name=virtmic \
  file=/tmp/virtmic \
  format=s16le rate=16000 channels=1
pactl set-default-source virtmic
# Keep FIFO open / fed or consumers may hang on open()
```

**Mac continuous stream (illustrative):**

```bash
# brew install sox ffmpeg
# Prefer mono 16 kHz for STT-style capture
rec -t raw -r 16000 -e signed -b 16 -c 1 - | \
  ssh manjaro 'cat > /tmp/virtmic'
```

**Or netcat (no SSH crypto; use only on Tailscale/LAN):**

```bash
# Linux: nc -l 7777 > /tmp/virtmic
# Mac:   rec -t raw -r 16000 -e signed -b 16 -c 1 - | nc MANJARO_TS_IP 7777
```

**ALSA loopback variant (Linux):**

```bash
sudo modprobe snd-aloop
# Mac → SSH → aplay into loopback playback side; capture from capture side
# ssh … "aplay -f S16_LE -r 16000 -c 1 -D hw:Loopback,0,0"
```

### 2.3 Pulse reverse tunnel (usually **playback**, not mic)

Common AgentVibes / blog pattern (remote TTS → local speakers):

```bash
# Mac (local Pulse via brew) listens 4713; reverse forward from remote
ssh -R 14713:localhost:4713 user@manjaro
# On remote:
export PULSE_SERVER=tcp:localhost:14713
paplay something.wav   # plays on Mac
```

To invert for **mic**, you need a **source** on the Mac Pulse server and either:

- remote `module-tunnel-source server=…`, or  
- remote apps using `PULSE_SERVER` that points at Mac (whole session audio redirects — heavy, breaks headless remote defaults).

macOS + Homebrew Pulse is second-class vs CoreAudio; prefer Roc for Mac→Linux mic.

### 2.4 Local STT inject (dictation without virtual mic)

```bash
# Examples of the product shape people actually use:
# - macOS Dictation / Superwhisper / Wispr: type into focused terminal (local or remote SSH window)
# - stt2desktop / faster-whisper-dictation: hotkey → clipboard → paste
# - tmux-aware inject: transcript | ssh manjaro 'tmux send-keys -t session -- "$(cat)"'
# - MCP voice (VoiceMode): still binds PortAudio on the host process machine
```

### 2.5 What agent vendors document

| Product | Remote SSH voice? | Mic location assumption |
|---------|-------------------|-------------------------|
| **Claude Code `/voice`** | **No** (docs explicit) | Machine running CLI |
| **Claude Code VS Code ext voice** | **No** in Remote-SSH/containers | Local UI, but extension host remote |
| **VS Code Speech (`ms-vscode.vscode-speech`)** | Local desktop; **not** Remote-SSH | Local VS Code process |
| **Grok CLI** | Remote backend = `pw-record` on host (doctor) | Audio server default **on remote** |
| **mossferry guide** | Voice/mic: use **local** Grok | Terminal stream has no devices |

---

## 3. What would make remote `pw-record` hear the Mac mic

`pw-record` records whatever PipeWire (or Pulse compatibility) treats as the **default capture source** (or an explicit target).

### Minimum success path

1. **A PipeWire/Pulse *source* exists on Manjaro** whose PCM is fed from the Mac mic stream (Roc Source, pipe-source FIFO, tunnel-source, ALSA loopback exposed to PW).  
2. That source is **default** or Grok/`pw-record` is pointed at it:
   - `pactl set-default-source <name>`
   - or `pw-record --target <node>` / env if Grok honors it  
3. Stream is **live whenever** the user hits voice (or always-on with VAD on the agent side).  
4. Format is sane: mono or stereo, typically 16–48 kHz, s16/f32; resampling handled by PW.  
5. Network path: Tailscale UDP (Roc) or long-lived SSH pipe; **mosh does not replace this** (no port forwards, no side channels for audio).

### Concrete “Mac → Manjaro default source” recipes

| Recipe | Steps summary |
|--------|----------------|
| **Roc (preferred)** | Linux: roc-source module; Mac: `roc-send -i core://…` to TS IP; set default source to roc-source |
| **FIFO** | Linux: `module-pipe-source` → `/tmp/virtmic`; Mac: `rec … \| ssh cat >/tmp/virtmic`; default source virtmic |
| **Always-on sidecar** | systemd user unit on Manjaro receiving Roc; LaunchAgent on Mac running roc-send when on tailnet |

### What Grok would need (product note)

- Today: remote process opens **host** mic via `pw-record` → empty/wrong device over SSH.  
- With pattern B/D: no Grok change if default source is virtual.  
- Cleaner long-term: Grok voice modes: `local-stt`, `remote-pipewire`, `inject-text-only` — and ferry starts the Mac-side sender.

---

## 4. What would NOT work

| Approach | Why it fails |
|----------|--------------|
| **Plain mosh / ferry terminal only** | Byte stream is PTY text/control sequences. No PCM, no CoreAudio, no PipeWire. |
| **`grok wrap` / OSC 52** | Clipboard (and terminal restore) only. Doctor already frames wrap as clipboard/SSH hygiene, not audio. |
| **tmux alone** | Multiplexes terminals; no audio device passthrough. |
| **Expecting Claude-style `/voice` over SSH without extra plumbing** | Anthropic documents this as unsupported; same architectural bind for any remote-hosted recorder. |
| **VS Code Speech while Remote-SSH’d into Manjaro** | Extension host runs remote; mic is local; Microsoft/marketplace behavior and Claude docs agree remote sessions lack mic. |
| **SSH `-R` Pulse “because blogs say so” without direction care** | Most tutorials solve **hear remote TTS on laptop**, not **laptop mic on remote**. Opposite problem. |
| **Mac BlackHole alone** | Loopback **on Mac** between apps; does not cross the network by itself. |
| **Assuming Tailscale magic-audio** | TS gives L3 reachability; you still need Roc/Pulse/pipe. |
| **WebRTC “somehow” inside the TUI** | Needs a browser or embedded engine + signaling; not provided by stock SSH/mosh. |

---

## 5. Recommended patterns ranked for a ferry / mosh product

Context: mossferry is a **session launcher** (SSH/mosh + tmux), not a media stack. Users want Grok (or Claude/Codex) voice while the agent runs on Manjaro.

### Rank 1 — **Local STT → inject text into remote session** (product default)

- **Why first:** Matches how Claude/VS Code solve voice (capture where the mic is). Avoids audio clocks, FEC, default-source fights.  
- **Ferry shape:** optional Mac-side helper: hotkey → STT (Whisper/native) → paste into focused terminal **or** `tmux send-keys` over the same SSH control path ferry already uses.  
- **Pros:** Robust over mosh; works offline with local Whisper; no Manjaro audio deps.  
- **Cons:** Does not satisfy “Grok’s remote `pw-record` hears me” without Grok accepting text as voice input; live partial transcripts harder.

### Rank 2 — **Roc Toolkit mic bridge (Mac → PipeWire source)** (for true remote `pw-record`)

- **Why:** Purpose-built realtime audio Mac↔Linux; FEC; first-class PipeWire module; Tailscale-friendly UDP.  
- **Ferry shape:** `ferry doctor audio` / `ferry audio up`: ensure Linux roc-source unit; print Mac LaunchAgent `roc-send` one-liner with peer TS IP; verify `pw-record --list-targets` shows Roc.  
- **Pros:** Unblocks stock remote Grok voice; reusable for other Linux tools.  
- **Cons:** Extra daemons; UDP ports; latency tuning; always-on mic privacy UX.

### Rank 3 — **SSH FIFO / pipe-source sidecar** (debug / zero-new-protocol)

- **Why:** Fewest new packages; good for “prove pcm reaches Manjaro.”  
- **Ferry shape:** `ferry audio pipe` starts `ssh … cat >/tmp/virtmic` + loads pipe-source.  
- **Pros:** Easy to reason about; works through SSH only (no extra UDP).  
- **Cons:** Glitchy; holds SSH; format brittle; not great over flaky Wi‑Fi vs Roc.

### Rank 4 — **Product split: local Grok for voice, ferry for remote work** (status quo docs)

- Already written in `docs/guides/grok-and-ferry.md`. Lowest engineering cost.  
- **Cons:** Two sessions / two minds; no single remote agent that “hears you.”

### Explicit non-goals for ferry v1

- Embedding WebRTC in the green TUI  
- Emulating Claude `/voice` server-side without Anthropic-like STT pipeline  
- Claiming mosh carries audio  
- Depending on Homebrew Pulse on Mac as primary path  

### Suggested decision tree

```
Need only dictation text in remote TUI?
  → Rank 1 local STT inject

Need remote process (Grok pw-record / arecord / Zoom-on-Linux) to hear laptop mic?
  → Rank 2 Roc (prod) or Rank 3 FIFO (prototype)

Only occasional voice, OK to leave ferry?
  → Rank 4 local Grok
```

---

## 6. Sources

| Topic | URL |
|-------|-----|
| Claude Code voice — SSH not supported | https://code.claude.com/docs/en/voice-dictation |
| VS Code Speech extension | https://marketplace.visualstudio.com/items?itemName=ms-vscode.vscode-speech |
| VS Code voice docs | https://code.visualstudio.com/docs/configure/accessibility/voice |
| PipeWire pulse-tunnel module | https://docs.pipewire.org/page_module_pulse_tunnel.html |
| Roc 0.4 tutorial (PipeWire + macOS + CLI) | https://gavv.net/articles/roc-0.4/ |
| Roc VAD (macOS virtual devices) | https://github.com/roc-streaming/roc-vad |
| Roc Toolkit | https://github.com/roc-streaming/roc-toolkit |
| SuperUser: feed network PCM into PA source | https://superuser.com/questions/1874559/how-to-supply-a-pulseaudio-source-with-data-coming-in-over-the-network |
| SuperUser: PipeWire stream Linux↔Linux | https://superuser.com/questions/1713253/how-to-stream-audio-through-pipewire-from-one-linux-system-to-another |
| AskUbuntu: laptop mic via nc + snd-aloop | https://askubuntu.com/questions/1225088/use-webcam-from-laptop-on-desktop-pc |
| Pulse `module-pipe-source` examples | https://stackoverflow.com/questions/51128790/linux-pipe-audio-to-virtual-microphone-using-pactl |
| AgentVibes remote audio (playback reverse tunnel) | https://github.com/paulpreibisch/AgentVibes/blob/master/docs/remote-audio-setup.md |
| Medium: Mac client reverse Pulse tunnel (playback) | https://medium.com/@cristianduguet/play-remote-audio-over-an-ssh-connection-with-a-mac-client-9b7135dfe129 |
| HN: Pulse socket over SSH | https://news.ycombinator.com/item?id=30613125 |
| SonoBus | https://sonobus.net/ |
| VoiceMode (Claude MCP voice) | https://voicemode.dev/ |
| Local STT → Claude in tmux | https://github.com/marcindulak/stt-mcp-server-linux |
| stt2desktop (Whisper → clipboard paste) | https://github.com/jedie/stt2desktop |
| PulseAudio modules reference | https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/Modules/ |
| ArchWiki PipeWire network overview | https://wiki.archlinux.org/title/PipeWire |
| mossferry local guide (status quo) | `docs/guides/grok-and-ferry.md` |
| Grok doctor sample (remote `pw-record`) | `raw/doctor-linux.json` |

### Raw research files

- `.firecrawl/grok-voice-research/raw/00-firecrawl-status.md` — credits exhausted  
- `.firecrawl/grok-voice-research/raw/sources-*.md` — condensed extracts  
- `.firecrawl/grok-voice-research/raw/doctor-linux.json` — remote doctor voice=`pw-record`  
- `.firecrawl/grok-voice-research/raw/docs-x-ai-terminal-support.md` — wrap/OSC52 only  

---

## Appendix A — Direction cheat sheet

```
Mac mic ──► Linux virtual SOURCE ──► pw-record / Grok voice     [NEED THIS]
Linux TTS ──► Mac speakers (PULSE_SERVER reverse)               [common blogs; opposite]
Mac clipboard ◄── OSC 52 / grok wrap                            [not audio]
Mac STT text ──► remote TUI (paste / tmux)                      [dictation without mic]
```

## Appendix B — Latency / reliability rough order

1. Local STT inject (no live audio path)  
2. Roc over Tailscale LAN-like RTT with FEC  
3. SSH PCM FIFO (TCP; stalls under loss)  
4. Pulse tunnel defaults (~200 ms) without tuning  
5. Broken: mosh-only / wrap-only / hope  

## Appendix C — Security / privacy

- Always-on mic bridge is a **standing capture device** on the remote host — treat like a security boundary (who can `pw-record`?).  
- Prefer push-to-talk: start `roc-send` only while ferry voice hotkey held.  
- Prefer Tailscale over exposing Pulse TCP / raw PCM on LAN.  
- Local STT keeps audio on Mac; only text crosses — better default for secrets.
