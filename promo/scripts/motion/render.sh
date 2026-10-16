#!/bin/bash
# Draft of the motion film, 1920x1080 at 60 fps, picture and mix muxed:
#   scripts/motion/render.sh   -> out/glasspad-motion.mp4, out/glasspad-motion-no-vo.mp4, out/glasspad-motion.srt
# Needs: the voice (scripts/motion/voice.py, cached) and the score (MUSIC.md).
set -euo pipefail
cd "$(dirname "$0")/../.."
pnpm -s motion:cues
python3 -I scripts/motion/mix.py
python3 -I scripts/motion/srt.py
mkdir -p out
npx remotion render src/index.ts GlasspadMotion out/_motion-picture.mp4 --muted --concurrency=${CONCURRENCY:-4} --crf=16 --log=error
mux() { ffmpeg -nostdin -v error -y -i "$1" -i "$2" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 320k -ar 48000 -movflags +faststart -shortest "$3"; }
mux out/_motion-picture.mp4 public/motion/mix-film.wav out/glasspad-motion.mp4
mux out/_motion-picture.mp4 public/motion/mix-film-novo.wav out/glasspad-motion-no-vo.mp4
rm -f out/_motion-picture.mp4
for f in out/glasspad-motion.mp4 out/glasspad-motion-no-vo.mp4; do
  echo "$f: $(ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate:format=duration -of csv=p=0 "$f" | tr '\n' ' ')"
  ffmpeg -nostdin -v info -nostats -i "$f" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I|Peak):" | tr -s ' ' | tr '\n' ' '; echo
done
