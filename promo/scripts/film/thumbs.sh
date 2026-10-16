#!/bin/bash
# Renders the five thumbnails: out/thumbnails/thumb-N-1920.png and thumb-N-1280.png.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p out/thumbnails
for i in 1 2 3 4 5; do
  npx remotion still src/index.ts GlasspadThumb$i out/thumbnails/thumb-$i-1920.png --log=error
  ffmpeg -v error -y -i out/thumbnails/thumb-$i-1920.png -vf scale=1280:720:flags=lanczos out/thumbnails/thumb-$i-1280.png
done
