# Claude Code official voice docs (scraped 2026-07-24)
URL: https://code.claude.com/docs/en/voice-dictation

Key quotes:
- "A local microphone: voice dictation does not work in remote environments such as Claude Code on the web or SSH sessions."
- VS Code extension: "It is not available in VS Code Remote sessions, including SSH, Dev Containers, and Codespaces, because the microphone is on your local machine and the extension runs on the remote host."
- Linux fallbacks: arecord (ALSA) or rec (SoX); native module preferred
- WSL: needs WSLg + sox libsox-fmt-pulse
