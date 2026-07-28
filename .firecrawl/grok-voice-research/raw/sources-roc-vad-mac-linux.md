# Roc Toolkit / Roc VAD for Mac→Linux audio (scraped 2026-07-24)
URLs:
- https://gavv.net/articles/roc-0.4/
- https://github.com/roc-streaming/roc-vad

Mac sender (mic or default CoreAudio):
  roc-send -vv -s rtp+rs8m://<LINUX_IP>:10001 -r rs8m://<LINUX_IP>:10002 -c rtcp://<LINUX_IP>:10003 -i "core://default"

Linux PipeWire roc-source module (~/.config/pipewire/pipewire.conf.d/roc-source.conf):
  libpipewire-module-roc-source with local.source.port=10001, repair=10002
  source.name = "Roc Source" → appears as capture source for pw-record

Mac virtual device path:
  roc-vad device add sender
  roc-vad device connect 1 --source rtp+rs8m://LINUX:10001 --repair rs8m://LINUX:10002 --control rtcp://LINUX:10003
  Then apps play TO virtual speaker (sender). For mic capture, use roc-send -i core://default (or specific CoreAudio device).

Note: Roc VAD "sender" = virtual SPEAKERS (apps write audio out). For laptop MIC → remote, use roc-send CLI capturing core:// mic, or route mic into a sender path carefully.
