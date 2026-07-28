# Local STT inject patterns for remote CLIs

1. macOS native Dictation / Wispr Flow / Superwhisper → paste into focused terminal
2. faster-whisper-dictation / stt2desktop: hotkey → STT → clipboard → paste
3. stt-mcp-server-linux (HN): Right Ctrl → Whisper → inject into Claude in tmux
4. VoiceMode (voicemode.dev): MCP for Claude Code, local PortAudio mic — still needs local mic on the machine running the MCP/host process
5. Vocalinux Remote API: capture local, STT on LAN Whisper server, inject into focused Linux app

Key insight for remote SSH/mosh: best UX is often **text injection**, not raw mic tunneling.
