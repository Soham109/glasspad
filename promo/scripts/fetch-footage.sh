#!/bin/bash
# Downloads the stock footage the v4 film uses into public/footage/src (not committed: large).
# Every clip is from Mixkit under the Mixkit Stock Video Free License (commercial use, no
# attribution required). Sources and licence notes: FOOTAGE.md. The checksums below are of the
# files as first downloaded; a mismatch means Mixkit changed the file, so check it by eye.
#   scripts/fetch-footage.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=public/footage/src
mkdir -p "$DIR"
UA="GlasspadPromoFilm/1.0 (https://github.com/Soham109/glasspad)"

# name | url | sha256
CLIPS=$(cat <<'EOF'
desk-topdown|https://assets.mixkit.co/active_storage/video_items/100069/1719941344/100069-video-2160.mp4|b5041eff2aaa4f4f10903ed7b25f9a80bbde6be3feb02e13f664c58dde4b8528
couch-phone|https://assets.mixkit.co/active_storage/video_items/100059/1719878616/100059-video-2160.mp4|0d2990ae17db699836d83b72dc20b62a2bb79de5543dad92c4b5b87037f2dc87
focus-laptop|https://assets.mixkit.co/active_storage/video_items/100057/1719878197/100057-video-2160.mp4|141d8245ec7b53a41f3926cf242a23c9301f84bcaa1f12a8a11e92f7bad198a3
handoff|https://assets.mixkit.co/videos/42630/42630-2160.mp4|fec78a7934264c28797fb086844f9e16710a9d00f78f7e9c6b7529f52d6976ce
two-screens|https://assets.mixkit.co/videos/44737/44737-2160.mp4|a51db8be28aa32d3effb14bc49050fe8f1bb12c7b6ec730162fd9776b86317de
edit-suite|https://assets.mixkit.co/videos/51602/51602-2160.mp4|f57aa3faacec54faa26e1f74a7aa1130adbc958a23de5edec1cf98d0bde9de33
hands-phone|https://assets.mixkit.co/videos/28300/28300-1080.mp4|040e58b001fb158f27d0694772581469ea1bdeee9c897b3cf4f33886618f3d57
EOF
)

echo "$CLIPS" | while IFS='|' read -r name url sum; do
  [ -z "$name" ] && continue
  f="$DIR/$name.mp4"
  if [ ! -s "$f" ]; then
    curl -fsSL -A "$UA" -o "$f.part" "$url"
    mv "$f.part" "$f"
    sleep 2 # one file at a time, politely
  fi
  got=$(shasum -a 256 "$f" | cut -d' ' -f1)
  if [ -n "$sum" ] && [ "$got" != "$sum" ]; then echo "checksum differs: $name ($got)" >&2; fi
  echo "$name $(ffprobe -v error -select_streams v -show_entries stream=width,height,r_frame_rate -show_entries format=duration -of csv=p=0 "$f" | tr '\n' ' ') $got"
done
