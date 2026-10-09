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
import numpy as np
from PIL import Image
from scipy import ndimage
im = Image.open(sys.argv[1])
for i in range(im.n_frames):
    im.seek(i)
    a = np.array(im.convert("RGBA"))
    # Stray near-clear pixels and specks off the bird come out of the HEVC alpha layer as
    # white flecks on the ground (seen on grove, 2026-10-08): drop them.
    alpha = a[..., 3].copy()
    alpha[alpha < 48] = 0
    lab, n = ndimage.label(alpha > 0)
    sizes = ndimage.sum(np.ones_like(alpha), lab, range(1, n + 1))
    alpha[~np.isin(lab, 1 + np.where(sizes >= 40)[0])] = 0
    # Every pixel takes the colour of the nearest solid bird pixel, so the soft edge blends
    # into brown rather than into whatever the clear pixels held.
    idx = ndimage.distance_transform_edt(alpha < 250, return_distances=False, return_indices=True)
    rgb = a[..., :3][idx[0], idx[1]]
    Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA").save(f"{sys.argv[2]}/f{i:04d}.png")
print(im.n_frames, "frames")
PY
ffmpeg -hide_banner -loglevel error -y -framerate 24 -i "$tmp/f%04d.png" \
  -c:v hevc_videotoolbox -alpha_quality 1.0 -q:v 70 -tag:v hvc1 -pix_fmt bgra "$out"
cp "$out" "$(cd "$(dirname "$0")/../.." && pwd)/tvos/KhajistanTV/Resources/Media/tuning-pigeon.mov"
ls -l "$out"
