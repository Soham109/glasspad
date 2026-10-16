#!/bin/bash
# Draft of the v4 film, 1920x1080 at 60 fps, picture and mix muxed:
#   scripts/v4/render.sh            -> out/glasspad-film-v4.mp4 (and -no-vo)
# Needs: public/v4/phone (scripts/v4/capture.sh), public/footage (scripts/fetch-footage.sh and
# scripts/v4/footage.py), public/v4/vo (scripts/v4/voice.py), the score (MUSIC.md).
set -euo pipefail
cd "$(dirname "$0")/../.."
pnpm -s v4:cues
python3 -I scripts/v4/mix.py
python3 -I scripts/v4/srt.py
mkdir -p out
npx remotion render src/index.ts GlasspadFilmV4 out/_v4-picture.mp4 --muted --concurrency=4 --log=error
mux() { ffmpeg -nostdin -v error -y -i "$1" -i "$2" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 320k -ar 48000 -movflags +faststart -shortest "$3"; }
mux out/_v4-picture.mp4 public/v4/mix-film.wav out/glasspad-film-v4.mp4
mux out/_v4-picture.mp4 public/v4/mix-film-novo.wav out/glasspad-film-v4-no-vo.mp4
rm -f out/_v4-picture.mp4
for f in out/glasspad-film-v4.mp4 out/glasspad-film-v4-no-vo.mp4; do
  echo "$f: $(ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate:format=duration -of csv=p=0 "$f" | tr '\n' ' ')"
  ffmpeg -nostdin -v info -nostats -i "$f" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I|Peak):" | tr -s ' ' | tr '\n' ' '; echo
done
