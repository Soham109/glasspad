#!/bin/bash
# The motion film at 3840x2160, 60 fps, rendered in 600 frame chunks so one crash loses one
# chunk, gently for a shared Mac: two browser tabs, JPEG frames, and before each chunk it waits
# until memory_pressure reports at least 25% free (four tabs pushed this Mac's swap to 7 GB).
#   scripts/motion/render-4k.sh   -> out/glasspad-motion-4k.mp4 (and -no-vo)
# Re-running skips chunks already rendered (out/motion-4k-chunks/NNN.mp4).
set -euo pipefail
cd "$(dirname "$0")/../.."
CHUNK=${CHUNK:-600}
MAX_CHUNKS=${MAX_CHUNKS:-0} # for a test: stop after this many chunks (0 = all)
DIR=out/motion-4k-chunks
mkdir -p "$DIR"
pnpm -s motion:cues
python3 -I scripts/motion/mix.py
python3 -I scripts/motion/srt.py
TOTAL=$(npx remotion compositions src/index.ts 2>/dev/null | awk '$1=="GlasspadMotion"{print $4}')
[ -n "$TOTAL" ] || { echo "could not read the film length" >&2; exit 1; }
free_pct() { memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/{gsub("%","",$2); print int($2)}'; }
i=0
for ((a = 0; a < TOTAL; a += CHUNK)); do
  b=$((a + CHUNK - 1)); [ $b -ge $TOTAL ] && b=$((TOTAL - 1))
  out=$(printf "%s/%03d.mp4" "$DIR" $i); i=$((i + 1))
  [ -s "$out" ] && continue
  if [ "$MAX_CHUNKS" -gt 0 ] && [ $i -gt "$MAX_CHUNKS" ]; then echo "stopping after $MAX_CHUNKS chunk(s)"; exit 0; fi
  while [ "$(free_pct)" -lt 25 ]; do echo "memory: $(free_pct)% free, waiting"; sleep 30; done
  echo "frames $a-$b -> $out"
  npx remotion render src/index.ts GlasspadMotion "$out.part.mp4" --frames=$a-$b --scale=2 --concurrency=2 \
    --image-format=jpeg --jpeg-quality=95 --codec=h264 --crf=16 --x264-preset=slow --pixel-format=yuv420p --muted --log=error
  mv "$out.part.mp4" "$out"
done
ls "$DIR"/[0-9][0-9][0-9].mp4 | sed "s#^#file '$(pwd)/#; s#\$#'#" > "$DIR/list.txt"
ffmpeg -nostdin -v error -y -f concat -safe 0 -i "$DIR/list.txt" -c copy out/_motion-4k-picture.mp4
mux() { ffmpeg -nostdin -v error -y -i "$1" -i "$2" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 320k -ar 48000 -movflags +faststart -shortest "$3"; }
mux out/_motion-4k-picture.mp4 public/motion/mix-film.wav out/glasspad-motion-4k.mp4
mux out/_motion-4k-picture.mp4 public/motion/mix-film-novo.wav out/glasspad-motion-4k-no-vo.mp4
rm -f out/_motion-4k-picture.mp4
ffprobe -v error -show_entries stream=codec_name,profile,width,height,r_frame_rate,bit_rate:format=duration -of compact out/glasspad-motion-4k.mp4
