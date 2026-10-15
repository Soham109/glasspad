#!/bin/sh
# Same picture, another mix: scripts/remux-copy.sh in.mp4 mix.wav out.mp4
set -e
ffmpeg -loglevel error -y -i "$1" -i "$2" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -shortest -movflags +faststart "$3"
