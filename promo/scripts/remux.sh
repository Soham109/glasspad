#!/bin/sh
# Re-mux a rendered cut with its source mix so the audio is sample-aligned to picture
# (Remotion's AAC track arrives 42.7 ms late from uncompensated encoder priming).
# usage: scripts/remux.sh out/film.mp4 public/mix.wav
set -e
tmp="${1%.mp4}.remux.mp4"
ffmpeg -loglevel error -y -i "$1" -i "$2" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -shortest -movflags +faststart "$tmp"
mv "$tmp" "$1"
