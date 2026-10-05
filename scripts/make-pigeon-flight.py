#!/usr/bin/env python3
"""Render the channel-change pigeon for the apps: HEVC with alpha, so the app draws the skin
colour itself and one clip serves day, grove and smut.

Sources are the Higgsfield ProRes 4444 masters (owner-local, not in this repo):
  output/Higgsfield Assets/Grooming Pigeon Masters/Smooth Derivatives/Flight-Across-V10-Alpha-60fps.mov
  output/Higgsfield Assets/Grooming Pigeon Masters/Smooth Derivatives/Flight-Upward-V10-Alpha-60fps.mov

The masters were keyed off black and carry a black rim several pixels wide inside the matte.
Each frame's matte is pulled in by CHOKE pixels and the colour at the new edge is rebuilt from
the feathers further in, so no keyed rim shows on yellow, green or pink. The colour is then premultiplied by
the matte, which is how AVFoundation composites HEVC with alpha. 6 px was chosen by eye
at native size against 3 (rim still visible) and 10 (eats the beak).

Usage: make-pigeon-flight.py <source.mov> <out.mov>
"""
import subprocess, sys
import numpy as np, cv2

CHOKE = 6
# The flights cross their own 9:16 frame (Across touches a side edge in 72 of 75 frames). On a
# 16:9 screen that edge would be a hard vertical line through the wing, so the outer FEATHER
# pixels at left and right fade the bird in and out instead.
FEATHER = 160

def clean(rgba):
    a = rgba[..., 3].astype(np.float32) / 255
    c = rgba[..., :3].astype(np.float32)
    d = cv2.distanceTransform((a > 0.5).astype(np.uint8), cv2.DIST_L2, 5)
    core = (d > CHOKE + 2).astype(np.float32)
    out, have = c.copy(), core.copy()
    for sigma in (2, 4, 8, 16, 32):
        num = cv2.GaussianBlur(c * core[..., None], (0, 0), sigma)
        den = cv2.GaussianBlur(core, (0, 0), sigma)
        fill = (have < 0.5) & (den > 1e-4)
        out[fill] = num[fill] / den[fill][..., None]
        have[fill] = 1
    colour = np.where((d <= CHOKE + 2)[..., None], out, c)
    alpha = np.clip((d - CHOKE) / 1.5, 0, 1) * a
    x = np.arange(alpha.shape[1], dtype=np.float32)
    edge = np.clip(np.minimum(x, alpha.shape[1] - 1 - x) / FEATHER, 0, 1)
    alpha = alpha * (edge * edge * (3 - 2 * edge))[None, :]
    # Premultiplied: AVFoundation composites HEVC-alpha as premultiplied, so colour left in a
    # transparent pixel is added to the picture beneath as a pale box round the bird.
    colour = colour * alpha[..., None]
    return np.dstack([np.clip(colour, 0, 255), alpha * 255]).astype(np.uint8)

def main(src, dst):
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                            "stream=width,height,r_frame_rate", "-of", "csv=p=0", src],
                           capture_output=True, text=True, check=True).stdout.strip().split(",")
    w, h, rate = int(probe[0]), int(probe[1]), probe[2]
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", src, "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
                           stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
                            "-s", f"{w}x{h}", "-r", rate, "-i", "-",
                            "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9", "-q:v", "80",
                            "-tag:v", "hvc1", "-pix_fmt", "bgra", "-an", dst], stdin=subprocess.PIPE)
    size, frames = w * h * 4, 0
    while (buf := dec.stdout.read(size)) and len(buf) == size:
        enc.stdin.write(clean(np.frombuffer(buf, np.uint8).reshape(h, w, 4)).tobytes())
        frames += 1
    enc.stdin.close()
    if enc.wait() or dec.wait():
        sys.exit("ffmpeg failed")
    print(f"{dst}: {frames} frames, {w}x{h} @ {rate}")

if __name__ == "__main__":
    main(*sys.argv[1:3])
