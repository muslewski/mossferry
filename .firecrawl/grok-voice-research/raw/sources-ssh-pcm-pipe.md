# SSH/raw PCM virtual mic patterns (scraped 2026-07-24)

AskUbuntu webcam/mic share (laptop→PC):
  Laptop: arecord -f cd -c 1 | nc -l 7777
  PC:     sudo modprobe snd-aloop
          nc LAPTOP_IP 7777 | aplay -f cd -D hw:1,1   # loopback as virtual mic

PulseAudio module-pipe-source:
  pactl load-module module-pipe-source source_name=virtmic \
    file=/tmp/virtualmic format=s16le rate=16000 channels=1
  pactl set-default-source virtmic
  # then write s16le PCM into /tmp/virtualmic FIFO

SuperUser network feed into PA source (2025):
  load module-pipe-source; redirect nc stdout into FIFO
  OR null-sink + paplay + monitor source

Pulse reverse tunnel (playback direction, inverse of mic need):
  Mac: brew install pulseaudio; load module-native-protocol-tcp
  ssh -R 24713:localhost:4713 server
  remote: export PULSE_SERVER=tcp:localhost:24713
  (This routes REMOTE playback TO Mac speakers — not Mac mic to Linux.
   For mic, need tunnel-source / pipe / Roc in opposite direction.)
