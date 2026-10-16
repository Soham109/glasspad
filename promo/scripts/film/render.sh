#!/bin/bash
# Builds the three deliverables from source:
#   out/glasspad-film.mp4            1920x1080 60 fps, voice + music + sound design
#   out/glasspad-film-no-vo.mp4      same picture, music + sound design
#   out/glasspad-teaser-vertical.mp4 1080x1920 60 fps, its own edit
# Audio is mixed offline (scripts/film/mix.py: -14 LUFS, true peak under -1 dBTP) and muxed.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -I scripts/film/tighten_voice.py
python3 -I scripts/film/build_edit.py
python3 -I scripts/film/mix.py
npx remotion render src/index.ts GlasspadFilm out/_film-picture.mp4 --muted --log=error
npx remotion render src/index.ts GlasspadTeaserVertical out/_teaser-picture.mp4 --muted --log=error
mux() { ffmpeg -v error -y -i "$1" -i "$2" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 320k -cutoff 20000 -ar 48000 -movflags +faststart -shortest "$3"; }
mux out/_film-picture.mp4 public/v2/mix-film.wav out/glasspad-film.mp4
mux out/_film-picture.mp4 public/v2/mix-film-novo.wav out/glasspad-film-no-vo.mp4
mux out/_teaser-picture.mp4 public/v2/mix-teaser.wav out/glasspad-teaser-vertical.mp4
for f in out/glasspad-film.mp4 out/glasspad-film-no-vo.mp4 out/glasspad-teaser-vertical.mp4; do
  echo "$f: $(ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate:format=duration -of csv=p=0 "$f" | tr '\n' ' ')"
  ffmpeg -v info -nostats -i "$f" -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I|Peak):" | tr -s ' ' | tr '\n' ' '; echo
done
