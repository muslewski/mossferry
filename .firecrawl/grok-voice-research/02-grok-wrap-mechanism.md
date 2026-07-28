# Grok wrap — mechanism (clipboard / OSC 52 / terminal restore)

Research note for mossferry Mac→Linux hops.  
Scope: **what `grok wrap` does and does not do** (clipboard vs voice vs audio).

Documented against **Grok Build 0.2.111** (local install) plus official docs as of 2026-07-24.

---

## 1. Sources

### Official (public)

| Source | URL / path | What it establishes |
|--------|------------|---------------------|
| Terminal Support | https://docs.x.ai/build/cli/terminal-support | OSC 52 routes; Apple Terminal ignores OSC 52; `grok wrap ssh` local PTY intercept; experimental |
| CLI Reference | https://docs.x.ai/build/cli/reference | `grok wrap <command…>` = local PTY that forwards OSC 52 clipboard writes |
| Changelog | https://x.ai/build/changelog | Dirty-restore (0.2.103); image paste over wrap (0.2.108); `doctor fix terminal.ssh-wrap` (0.2.109); one-time SSH tip (0.2.103) |
| Install | `curl -fsSL https://x.ai/cli/install.sh \| bash` | Ships `grok` including `wrap` subcommand |

Raw scrapes:  
`mossferry/.firecrawl/grok-voice-research/raw/docs-x-ai-terminal-support.md`,  
`…/docs-x-ai-cli-reference.md`,  
`…/x-ai-build-changelog.md`.

### Installed product docs / CLI (authoritative detail)

| Source | Path |
|--------|------|
| User guide (fuller than public page) | `~/.grok/docs/user-guide/21-terminal-support.md` |
| README (`grok ssh` sibling) | `~/.grok/README.md` § SSH Passthrough |
| Changelog | `~/.grok/CHANGELOG.md` |
| CLI help | `grok wrap --help`, `grok doctor`, `grok doctor fix ssh-wrap` |
| Binary | `~/.grok/downloads/grok-0.2.111-linux-x86_64` (`pty_wrap.rs`, `wrap_filter.rs`, clipboard) |
| Live doctor | `grok doctor --json` → `facts.clipboard.wrapSink`, finding `terminal.ssh-wrap` |

### Mossferry (consumer of wrap, not implementer)

| Source | Path |
|--------|------|
| Grok + ferry guide | `docs/guides/grok-and-ferry.md` |
| Client | `bin/mossferry` (`FERRY_WRAP`, `_ferry_run_transport`) |

### Research method notes

- Firecrawl CLI searches returned **HTTP 402** this pass; official pages were fetched via docs markdown endpoints + web browse; mechanism details cross-checked against the installed binary and `grok doctor --json`.
- Raw artifacts under `.firecrawl/grok-voice-research/raw/` (`00-firecrawl-status.md`, `binary-detection-notes.md`, `doctor-linux.json`, CLI help, local guide copy).

**Public technical writeups beyond xAI:** none found that reverse-engineer wrap internals. OSC 52 itself is a general terminal standard (third-party explainers exist; they are not Grok-specific).

---

## 2. What wrap does (PTY, OSC 52 intercept, terminal mode reset)

### One-line job

`grok wrap <cmd…>` runs an **arbitrary local command** (ssh, mosh, docker exec, kubectl exec, …) inside a **local pseudo-terminal**, so that:

1. **OSC 52 clipboard sequences** (and tmux-wrapped / DCS-passthrough forms) from the child’s output are **intercepted** and written to the **local OS clipboard**.
2. The child’s TTY **window size tracks** the outer terminal (SIGWINCH).
3. On **dirty exit** (SSH drop mid-TUI, abrupt child death while mouse reporting / alternate screen / similar modes are on), wrap **resets terminal modes** so the local terminal is not left spraying mouse escapes.

CLI (`grok wrap --help`):

> Wraps an arbitrary command … in a local pseudo-terminal, intercepts OSC 52 clipboard escape sequences from its output, and writes them to your local system clipboard. … The wrapped command’s terminal is also kept in sync with your window size.

### How clipboard normally works (without wrap)

Grok’s TUI can write clipboard via up to three routes (`/doctor` **Clipboard** section):

| Route | When |
|-------|------|
| **native** | OS clipboard APIs (`arboard`, `pbcopy`/`wl-copy`/… as available) |
| **tmux buffer** | Inside tmux → `tmux load-buffer` |
| **OSC 52** | Escape sequence to the outer terminal; always used inside tmux; outside tmux on Linux, over SSH, or in a display-less container |

Kill switch: `GROK_CLIPBOARD_NO_OSC52=1` (doctor shows `osc 52 off`). Backup file: every copy also lands in `~/.grok/last-copy.txt` (override `GROK_COPY_FILE`).

### Why wrap exists

- **Apple Terminal ignores OSC 52 entirely** → remote Grok copies never reach the Mac clipboard.
- Some other terminals need explicit OSC 52 permission (iTerm2: Settings → General → Selection → “Applications in terminal may access clipboard”).
- Over SSH / in containers, native clipboard is the **remote** machine’s (or none) — OSC 52 is the bridge; wrap is a **local sink** when the outer terminal won’t honor OSC 52.
- Secondary: **dirty disconnect restore** (changelog 0.2.103; user guide).

### Implementation shape (from docs + binary)

```
┌────────────── Mac / laptop terminal ──────────────┐
│  outer emulator (Terminal.app / Ghostty / …)      │
│    └─ grok wrap   (local PTY host + filter)       │
│         └─ ssh | mosh | docker exec | …           │
│              └─ remote shell / tmux / grok TUI    │
│                   emits OSC 52 on copy ───────────┼──► wrap intercepts
│                                                   │     → local clipboard
│                   (on abrupt exit) ───────────────┼──► wrap resets modes
└───────────────────────────────────────────────────┘
```

Binary modules (path strings in 0.2.111):

- `xai_grok_pager::pty_wrap` — PTY spawn, SIGWINCH, termination handler  
- `xai_grok_pager::wrap_filter` — stream filter for OSC 52 (and related)  
- `clipboard` render path — native / tmux / OSC 52; respects sink env (below)

Related sibling: **`grok ssh`** (README) — SSH-specific convenience; on macOS, if the terminal lacks native OSC 52, same PTY+`pbcopy` pattern; if terminal has native OSC 52 (iTerm2, Ghostty, Kitty, WezTerm, Alacritty), **plain `ssh` exec with no wrapper**.

### Image paste over wrap

- Changelog **0.2.108**: “**Image paste** over grok wrap now works on headless remotes.”
- Binary markers: `GROK_WRAP_IMG` / `GROK_WRAP_NONE` adjacent to bracketed-paste CSI `\x1b[200~` / `\x1b[201~`.
- Interpretation: wrap is involved in **forwarding image paste payloads** into the remote TUI path (not only text OSC 52). Exact wire format is not public; treat as **text+image paste facilitation over the PTY**, not a separate media channel.

### Explicitly not claimed by wrap docs

See §6.

---

## 3. How wrap status is detected by remote /doctor

### Doctor facts (machine-readable)

`grok doctor --json` (and in-TUI `/doctor`) includes:

```json
"clipboard": {
  "nativeRoute": true,
  "tmuxRoute": true,
  "osc52Route": true,
  "wrapSink": false,
  "delivery": "confirmed",
  ...
}
```

| Field | Meaning (observed / inferred) |
|-------|--------------------------------|
| **`wrapSink`** | Whether this Grok session believes a **local wrap OSC 52 sink** is active |
| **`ssh`** (top-level fact) | Session is over SSH |
| Finding **`terminal.ssh-wrap`** | Recommendation when **SSH and not under wrap** — clipboard depends on terminal OSC 52; drop can leave local terminal dirty |

Example finding (remote Linux over SSH, wrap not active):

> Running over SSH without `grok wrap` — clipboard copies depend on the terminal’s escape-sequence support, and a dropped connection can leave your local terminal in a bad state  
> Fix: `grok wrap ssh <host>`  
> Auto: `grok doctor fix terminal.ssh-wrap` (run **on the local machine**)

### UX when not wrapped

- **One-time contextual tip** above the prompt when Grok starts in SSH **without** wrap (stops once you launch through wrap). Disable tip only: `ssh_wrap = false` under `[ui.contextual_hints]` in `~/.grok/config.toml` (or Settings → contextual hints → SSH wrap). Does **not** hide the doctor finding.
- Doctor keeps SSH wrapping as a **Recommendation** with local-only setup instructions.

### Detection channel (confirmed: env sink flags)

Present in binary (`pty_wrap` + clipboard modules) and **confirmed by live `grok doctor --json` probes** on Linux 0.2.111:

| Env var | Role |
|---------|------|
| **`GROK_OSC52_SINK`** | When **set** (any value, including `0`), doctor reports `clipboard.wrapSink: true` |
| **`LC_GROK_OSC52_SINK`** | Same effect alone — **`LC_` prefix** is the SSH-friendly form (OpenSSH often allows `AcceptEnv LANG LC_*` / client `SendEnv LC_*`) |

Observed side effects when either var is present:

- `facts.clipboard.wrapSink` → **`true`**
- `facts.clipboard.osc52Capability` → **`supported`** (was `unknown` without it on this host)
- finding **`terminal.ssh-wrap` disappears** (counts.recommendations drops)

So remote detection is: **“is a wrap sink env advertised into this process?”** — not a network probe. Active `grok wrap` is expected to inject these into the child (and via `LC_*` across SSH). Manual export of either var is enough to silence the doctor recommendation (and to prove the gate).

**Probe caveat (this host, 0.2.111):** wrapping a trivial local command (`sleep`) **elided** to a plain exec (no intermediate wrap process; no sink env on the child). That matches the documented **`grok ssh`** behavior of skipping the wrapper when the outer terminal already handles OSC 52 — wrap is not always a forced PTY layer. When wrap elides, remote detection correctly stays `wrapSink: false` unless a real sink is installed on the hop.

Artifacts: `raw/linux-doctor-with-osc52-sink.json` (`wrapSink: true`, no ssh-wrap finding) vs baseline `raw/doctor-linux.json` / `raw/linux-doctor.json` (`wrapSink: false` + recommendation).

### What doctor does *not* use wrap for

- **Microphone / Voice** section is independent (local audio device name, e.g. `pw-record` on Linux). Wrap is not part of voice diagnostics.
- Color, themes, kitty keyboard, tmux probes are separate findings.

---

## 4. Setup paths

### A. One-off wrap (any command)

```bash
# SSH
grok wrap ssh user@host
grok wrap ssh user@host -- tmux attach

# Containers / k8s
grok wrap docker exec -it <container> bash
grok wrap kubectl exec -it <pod> -- bash

# Anything else (generic)
grok wrap mosh user@host
```

Install once on the **laptop** (not the remote):

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
```

### B. Permanent alias — `grok doctor fix ssh-wrap`

```bash
# On the LOCAL machine (Mac), interactive shells:
grok doctor fix ssh-wrap
# canonical id also accepted:
grok doctor fix terminal.ssh-wrap
# non-interactive after plan print:
grok doctor fix ssh-wrap --yes
```

Behavior (user guide + CLI strings):

- Shows the **exact planned change**, asks confirmation (unless `--yes`).
- Adds an interactive-shell **alias** so `ssh …` becomes `grok wrap ssh …` in:
  - `~/.bashrc`
  - `~/.zshrc`
  - `~/.config/fish/config.fish`
- **Windows:** automatic setup **unavailable**.
- Safety scan refuses if the target file already has a direct `ssh` alias/function; sourced plugins need manual review.
- Bypass: `command ssh …`
- **Not fully transparent** for: `ssh -f`, ControlPersist workflows, OpenSSH local suspend `~^Z` — use bypass.
- Alias does not recurse: wrap spawns real SSH directly.
- Alias loads only in **new interactive** shells.

In-TUI (0.2.111+): `/doctor fix ssh-wrap` (or `terminal.ssh-wrap`) can apply the same remediation from inside the TUI.

### C. Mossferry (keep `ferry` as entrypoint)

Do **not** replace ferry with raw `grok wrap ssh` for day-to-day use. Ferry already optionally prefixes the hop:

| Env | Default | Effect |
|-----|---------|--------|
| `FERRY_WRAP` | `auto` | `auto`: wrap if local `grok` on PATH; `on` / `off` force |
| `FERRY_TRANSPORT` | `mosh` | `mosh` (roam) or `ssh` (better OSC 52 with wrap) |

```bash
# Mac
# FERRY_WRAP=auto          # default
# FERRY_TRANSPORT=ssh      # when clipboard reliability > roam
ferry
ferry doctor               # reports local grok wrap + transport
```

Implementation: `_ferry_run_transport` → `grok wrap mosh …` or `grok wrap ssh -t …` (`bin/mossferry`). Non-interactive `--list` never wraps.

---

## 5. Limitations

| Topic | Status |
|-------|--------|
| **Experimental** | Official: “`grok wrap` is **experimental** and may misbehave in some setups.” |
| **mosh** | Wrap can prefix `mosh`, but **many mosh builds strip OSC 52**. Wrap cannot invent clipboard bytes that never arrive on the stream. Prefer `FERRY_TRANSPORT=ssh` (or plain `grok wrap ssh`) for reliable Grok→local clipboard; keep host-side yank pipes (tmux → `pbcopy`) as fallback. mosh still wins for roaming. |
| **Windows** | `doctor fix ssh-wrap` automatic alias setup unavailable. Wrap PTY story is Unix-oriented in the docs examples. |
| **Native OSC 52 terminals** | iTerm2 / Ghostty / Kitty / WezTerm / Alacritty may not need wrap for clipboard; `grok ssh` may plain-exec. Dirty-restore still a reason to wrap. iTerm2 needs explicit clipboard permission. |
| **Apple Terminal** | Primary motivation for wrap (no OSC 52). |
| **SSH edge modes** | Not transparent for `ssh -f`, ControlPersist, `~^Z` local suspend. |
| **Nested wrap inside remote tmux** | Useless for Mac clipboard: wrap must surround the **whole hop on the laptop**. Remote `ctrl-g` / start-menu only sets the remote start command. |
| **Selected-text paste** | Remote process still cannot read local PRIMARY/CLIPBOARD; use terminal-native Shift+Insert / Shift+middle-click. Wrap is about **copy out** (and image paste path), not full bidirectional selection API. |
| **Elision** | Wrapper may become a no-op exec when it decides filtering is unnecessary (observed for trivial local child; documented for `grok ssh` on native-OSC52 terminals). |

---

## 6. Explicit statement: does wrap forward microphone or audio?

### Official / installed docs

**No.** Wrap is documented solely as:

- local PTY around a command  
- OSC 52 (clipboard) intercept → local clipboard  
- terminal mode reset on dirty disconnect  
- (changelog) image paste over wrap on headless remotes  

There is **no** mention of microphone, voice, PCM, audio devices, WebRTC, or mic forwarding in:

- `grok wrap --help`  
- public Terminal Support / CLI Reference  
- user guide wrap sections  
- changelog wrap bullets  

### Voice is a separate, local feature

- `/voice`, `Ctrl+Space` / F8 dictation capture audio on the **machine running the Grok process**.
- `grok doctor` Voice section names a **local** recorder (e.g. macOS helper, Linux `pw-record`).
- macOS: mic permission belongs to the **terminal app hosting Grok**, not to wrap.
- Enterprise can disable voice via `requirements.toml` independently of wrap.

### Not mentioned = not a wrap feature

| Capability | Wrap? | Where it actually lives |
|------------|-------|-------------------------|
| Text copy remote → local clipboard | **Yes** (OSC 52 sink) | wrap +/or terminal OSC 52 |
| Dirty TUI terminal restore | **Yes** | wrap |
| Image paste into remote Grok | **Yes** (0.2.108+) | wrap PTY / bracketed-paste path |
| Microphone / dictation | **No** | local Grok process + OS audio |
| Bidirectional audio / voice hop Mac→Linux | **No** (not mentioned anywhere for wrap) | would need a separate design (not wrap) |
| Remote Grok hearing Mac mic over ferry/mosh/ssh | **No** | PTY stream is not an audio device |

Mossferry’s own guide states the same product boundary: ferry/mosh/ssh carry a **terminal stream**, not audio devices; use **local Mac `grok`** for voice.

---

## 7. Implications for mossferry ferry Mac→Linux hop

```
Mac Terminal
  └─ ferry  (FERRY_WRAP=auto → grok wrap when grok on PATH)
       └─ mosh|ssh  (FERRY_TRANSPORT)
            └─ remote repo-session / tmux
                 └─ grok   (ctrl-g / start menu — remote process)
```

| Need | Correct layer |
|------|----------------|
| Grok coding on Manjaro | ferry hop + remote `grok` |
| Clipboard Grok→Mac | **local** wrap around hop; prefer **`FERRY_TRANSPORT=ssh`** if OSC 52 is stripped by mosh |
| Dirty disconnect cleanup | same local wrap |
| Image paste into remote Grok | local wrap (0.2.108+); still needs a working PTY path |
| Voice / Ctrl+Space / mic | **local Mac `grok` only** — wrap does **not** ferry the mic |
| “Is wrap on?” from remote | `/doctor` → `wrapSink` / finding `terminal.ssh-wrap`; tip until fixed |

### Practical defaults for this fleet

1. Install Grok CLI on the **Mac** (`install.sh`) so `FERRY_WRAP=auto` can prefix wrap.  
2. Keep typing **`ferry`**, not raw `grok wrap ssh`.  
3. When clipboard must be reliable: `FERRY_TRANSPORT=ssh` (or host-side tmux→`pbcopy`).  
4. When you need dictation: open **local** Grok (or Grok desktop) on the Mac; do not expect remote TUI + wrap to open the Mac mic.  
5. `ferry doctor` / remote `grok doctor` both help: ferry checks **local** wrap availability; remote doctor reports **`wrapSink`** and SSH-wrap recommendation.

### Orthogonal features (do not confuse)

- **Picker `ctrl-g` / start menu** — sets remote start command to `grok`; does not install wrap.  
- **`grok doctor fix ssh-wrap`** — aliases bare `ssh` on the laptop; ferry’s own wrap prefix is independent and preferred for ferry users.  
- **Native memory / mail / MCP** — unrelated to wrap.

---

## Appendix A — Version timeline (wrap-relevant)

| Version | Date (changelog) | Note |
|---------|------------------|------|
| 0.2.103 | 2026-07-17 | SSH one-time tip for `grok wrap ssh`; wrap restores terminal after abrupt exits; clearer SSH/container copy feedback |
| 0.2.106 | 2026-07-18 | `GROK_CLIPBOARD_NO_OSC52`; always write copy backup file |
| 0.2.108 | 2026-07-21 | Image paste over wrap on headless remotes; standalone `grok doctor` |
| 0.2.109 | 2026-07-21 | `grok doctor fix terminal.ssh-wrap` alias installer; `/doctor` main diagnostics |
| 0.2.111 | 2026-07-22 | `doctor fix` from inside TUI; voice capture memory helper on macOS (unrelated to wrap) |

## Appendix B — Quick verification checklist

```bash
# Local (Mac)
which grok && grok wrap -h
ferry doctor                    # wrap available + transport

# After hop, inside remote Grok
/doctor                         # Clipboard: wrapSink? SSH wrap recommendation?
# or outside TUI:
grok doctor --json | jq '.facts.clipboard.wrapSink, .findings[] | select(.id=="terminal.ssh-wrap")'
```

## Appendix C — What wrap is not (summary)

1. **Not** a VPN, audio bridge, or mic forwarder.  
2. **Not** a remote Grok feature (it runs on the **client** machine).  
3. **Not** required for every terminal (native OSC 52 terminals already clipboard-copy).  
4. **Not** a substitute for mosh’s reconnect benefits (tradeoff vs clipboard).  
5. **Not** guaranteed stable (explicitly experimental).  

---

*End of mechanism note. Raw materials: `.firecrawl/grok-voice-research/raw/`.*
