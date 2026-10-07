#!/bin/sh
# The receiver's tuning pigeon for the phone and iPad: the website's grooming loop
# (archive/assets/home-pigeon/grooming.webp, 300x276, 208 frames at 42 ms, transparent), as a
# looping HEVC movie with alpha, so the decoder plays it rather than 208 decoded frames held in
# memory (~69 MB). Frames come out of the WebP whole (PIL composites them), then VideoToolbox
# encodes them at 24 fps.
#   sh ios/scripts/make-tuning-pigeon.sh <path to grooming.webp>
set -eu
src="${1:?path to grooming.webp}"
out="$(cd "$(dirname "$0")/.." && pwd)/Khajistan/Resources/Media/tuning-pigeon.mov"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$src" "$tmp" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
for i in range(im.n_frames):
    im.seek(i)
    im.convert("RGBA").save(f"{sys.argv[2]}/f{i:04d}.png")
print(im.n_frames, "frames")
PY
ffmpeg -hide_banner -loglevel error -y -framerate 24 -i "$tmp/f%04d.png" \
  -c:v hevc_videotoolbox -alpha_quality 0.9 -q:v 70 -tag:v hvc1 -pix_fmt bgra "$out"
ls -l "$out"
