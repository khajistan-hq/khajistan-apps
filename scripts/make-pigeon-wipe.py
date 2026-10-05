#!/usr/bin/env python3
"""Render the channel-change wing wipe for the apps: the website's own wipe (Higgsfield clip
0ea14f57, Seedance 2.5, 1080x1920, cropped to 16:9 at y=600 exactly as archive commit
acd81a521 cut it), lifted off its black ground so the app paints the skin's colour behind it.

  wipe-in   1.0-2.6 s  the pigeon flies at the viewer until a wing fills the screen
  wipe-out  2.6-3.5 s  the wing sweeps off

The matte is BiRefNet (rembg "birefnet-general", already on this machine), raised where the
pixel is clearly brighter than the black ground: the model is unsure of blurred wingtips and
pale feather edges, and a brightness key alone cannot hold the chest, which is as dark as the
ground. The ground is pure black, so a source
pixel is already alpha x colour: the colour is kept as the premultiplied value and clamped to
the matte. Frames are not enlarged: they stay at the crop's own 1080x608 and the GPU scales
them to the screen (see OUT). 24 fps, the
source's own rate. Output is HEVC with alpha (AVFoundation composites it premultiplied).

The model's memory grows from frame to frame and the machine's mem-guard stops a process over
16 GB, so masks are made in batches, each in a fresh process.

Usage: make-pigeon-wipe.py <Pigeon-Flight-Seedance25-Portrait-1080p.mp4> <out-dir>
"""
import os, subprocess, sys, tempfile
import numpy as np, cv2

CROP_Y, CROP_H = 600, 608
# Encoded at the crop's own 1080x608 and scaled to the screen by the GPU. An earlier 1920x1080
# encode was the same picture enlarged, and the owner's Apple TV HD (A8) decoded it at 15-21 fps
# against the clip's 24 (measured on the device, 2026-10-05): it would have stuttered.
OUT = (1080, CROP_H)
CUTS = {"wipe-in": (1.0, 2.6), "wipe-out": (2.6, 3.5)}
BATCH = 1   # the model passes 16 GB by its third frame in one process (measured)

def masks(frames, work):
    todo = [f for f in frames if not os.path.exists(f + ".a.png")]
    for i in range(0, len(todo), BATCH):
        code = ("import sys,numpy as np,cv2\nfrom PIL import Image\nfrom rembg import new_session,remove\n"
                "s=new_session('birefnet-general')\n"
                "for f in sys.argv[1:]:\n"
                " c=cv2.cvtColor(cv2.imread(f,cv2.IMREAD_UNCHANGED),cv2.COLOR_BGR2RGB)\n"
                " m=remove(Image.fromarray((c/257).astype(np.uint8)),session=s,only_mask=True)\n"
                " m.save(f+'.a.png')\n")
        subprocess.run([sys.executable, "-c", code, *todo[i:i + BATCH]], check=True,
                       stderr=subprocess.DEVNULL)
        print(f"  masks {min(i + BATCH, len(todo))}/{len(todo)}", flush=True)

def render(src, name, start, end, out_dir, work):
    d = os.path.join(work, name); os.makedirs(d, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-to", str(end), "-i", src,
                    "-vf", f"crop=1080:{CROP_H}:0:{CROP_Y}", "-pix_fmt", "rgb48le",
                    os.path.join(d, "%04d.png")], check=True)
    frames = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".png") and ".a." not in f)
    masks(frames, work)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
                            "-s", f"{OUT[0]}x{OUT[1]}", "-r", "24", "-i", "-",
                            "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9", "-q:v", "85",
                            "-tag:v", "hvc1", "-pix_fmt", "bgra", "-an",
                            os.path.join(out_dir, name + ".mov")], stdin=subprocess.PIPE)
    for f in frames:
        c = cv2.cvtColor(cv2.imread(f, cv2.IMREAD_UNCHANGED), cv2.COLOR_BGR2RGB).astype(np.float32) / 257
        a = cv2.imread(f + ".a.png", cv2.IMREAD_GRAYSCALE).astype(np.float32) / 255
        # On a pure black ground anything clearly brighter than black is bird. The model is
        # unsure of a motion-blurred wingtip or a pale feather edge and leaves them half clear;
        # brightness is sure of them. The model is what holds the dark chest. Take the larger.
        # The model's edge sits about a pixel outside the bird and carries a sliver of the black
        # ground as a dark line; pull it in by one pixel and soften it before the brightness max.
        a = cv2.GaussianBlur(cv2.erode(a, np.ones((3, 3), np.uint8)), (0, 0), 0.8)
        # Where the model is unsure (gaps opening between wing and frame) and the source is pure
        # black, it is ground: unsure pixels fade out between brightness 2 and 8. Measured over
        # every third frame: 0.11 % of the solid bird is that dark, 21,458 unsure pixels are.
        m = c.max(axis=2)
        unsure = a < 0.95
        a[unsure] *= np.clip((m[unsure] - 2) / 6, 0, 1)
        a = np.maximum(a, np.clip((m - 6) / 50, 0, 1))
        c = np.minimum(c, a[..., None] * 255)
        rgba = np.dstack([c, a * 255])
        enc.stdin.write(np.clip(rgba, 0, 255).astype(np.uint8).tobytes())
    enc.stdin.close()
    if enc.wait():
        sys.exit("ffmpeg failed")
    print(f"{name}.mov: {len(frames)} frames, {OUT[0]}x{OUT[1]} @ 24", flush=True)

if __name__ == "__main__":
    src, out_dir = sys.argv[1:3]
    work = os.environ.get("KJ_WIPE_WORK") or tempfile.mkdtemp(prefix="kj-wipe-")
    for name, (a, b) in CUTS.items():
        render(src, name, a, b, out_dir, work)
