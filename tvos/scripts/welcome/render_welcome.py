#!/usr/bin/env python3
"""Render the welcome's two Higgsfield clips onto each skin's ground, so the welcome has no black
box (owner, 2026-11-20: "no black backgroiund"). Opaque H.264, like the flights' first render:
the Apple TV HD has no hardware for HEVC with alpha.

    render_welcome.py <archive>/assets/tv  tvos/KhajistanTV/Resources/Media

Both clips are lit on black, and the black is taken out two ways:
  wordmark  black is "no light": alpha = the brightest channel, colour over the ground added
            (out = c + ground * (1 - a)), so the glow and its rays shine on the ground.
  ident     the bird is a solid object: alpha = a soft step on the brightest channel, the colour
            un-mixed from black (c / a), so the bird stays whole and only the black goes.
Writes welcome-<ident|wordmark>-<day|grove|smut>.mp4. `--check` runs the self-test."""
import subprocess, sys
import numpy as np
import cv2

# Kept in step with Skin.groundHex in KhajistanTV/Core/Sky.swift.
SKINS = {"day": (0xF3, 0xFB, 0x04), "grove": (0x18, 0x64, 0x09), "smut": (0xC1, 0x1B, 0x6B)}
CLIPS = {"ident": ("khajistan-signon-ident.mp4", "solid"), "wordmark": ("khajistan-wordmark-jeweled.mp4", "light")}
W, H = 1280, 720
FLOOR = 0.10


def edge_fade(h, w, share=0.12):
    """1 inside, falling to 0 at the frame's edge over `share` of each side."""
    ramp = lambda n: np.clip(np.minimum(np.arange(n) + 0.5, n - np.arange(n) - 0.5) / (n * share), 0, 1)
    return np.outer(ramp(h), ramp(w))


def composite(frame, ground, mode):
    """frame: HxWx3 floats 0-1 lit on black; ground: 3 floats 0-1. Returns HxWx3 floats 0-1."""
    if mode == "light":
        # The wordmark's "black" is a grey vignette up to 0.09: below FLOOR is no light at all,
        # or the clip shows as a lighter box on the page.
        frame = np.clip((frame - FLOOR) / (1 - FLOOR), 0, 1)
    peak = frame.max(axis=2)
    if mode == "light":
        # The letters are solid (their own pink and gold on any ground); only the faint glow and
        # rays around them are light added to the ground.
        # Solid where there is colour (the pink and the gold) or a near-white highlight (the
        # stones); the grey glow and rays have neither, and stay light.
        chroma = peak - frame.min(axis=2)
        coloured = np.clip((chroma - 0.10) / 0.12, 0, 1) * np.clip((peak - 0.10) / 0.10, 0, 1)
        bright = np.clip((peak - 0.55) / 0.15, 0, 1)
        a = np.maximum(peak, np.maximum(coloured, bright))
        # Light fades out toward the clip's edges, so a ray never stops on a straight line where
        # the clip ends on the page. Not the bird: it is an object, and its head reaches the top.
        a = a * edge_fade(*a.shape)
    else:
        # The bird: a step on brightness, its holes filled (dark feathers inside the outline are
        # bird, not background) and its edge pulled in a pixel, so no black fringe is left.
        hard = (peak > 0.05).astype(np.uint8)
        flood = hard.copy()
        mask = np.zeros((hard.shape[0] + 2, hard.shape[1] + 2), np.uint8)
        cv2.floodFill(flood, mask, (0, 0), 1)
        solid = hard | (1 - flood)
        solid = cv2.erode(solid, np.ones((3, 3), np.uint8))
        a = cv2.GaussianBlur(solid.astype(np.float32), (5, 5), 0)

    a = a[..., None]
    colour = np.clip(frame / np.maximum(a, 1e-3), 0, 1)
    return colour * a + ground * (1 - a)


def check():
    g = np.array([0.95, 0.98, 0.02])
    black = np.zeros((1, 1, 3))
    vignette = np.full((1, 1, 3), 0.09)
    assert np.allclose(composite(vignette, g, "light"), g), "the clip's grey vignette is the ground too"
    assert np.allclose(composite(black, g, "light"), g), "black must become the ground"
    assert np.allclose(composite(np.zeros((9, 9, 3)), g, "solid"), g), "black must become the ground"
    white = np.ones((1, 1, 3))
    assert np.allclose(composite(white, g, "light"), 1)
    bird = np.zeros((40, 40, 3)); bird[10:30, 10:30] = [0.5, 0.3, 0.2]; bird[18:22, 18:22] = 0.01
    out = composite(bird, g, "solid")
    assert np.allclose(out[20, 20], 0.01, atol=0.02), "a dark feather inside the bird stays bird"
    assert np.allclose(out[2, 2], g), "outside the bird is the ground"
    assert np.allclose(out[15, 15], [0.5, 0.3, 0.2]), "the bird's body is its own colour"
    top = np.zeros((40, 40, 3)); top[0:20, 10:30] = [0.9, 0.9, 0.85]
    assert np.allclose(composite(top, g, "solid")[2, 20], [0.9, 0.9, 0.85]), "a bird at the frame's edge is not faded"
    pink = np.full((1, 1, 3), [0.8, 0.2, 0.5])
    ray = np.full((40, 40, 3), 0.5)
    edge = composite(ray, g, "light")
    assert np.allclose(edge[0, 0], g, atol=0.08) and not np.allclose(edge[20, 20], g, atol=0.08), "light fades to the ground at the edge"
    lit = (pink - FLOOR) / (1 - FLOOR)
    assert np.allclose(composite(pink, g, "light"), lit), "a lit letter keeps its own colour on any ground"
    glow = np.full((1, 1, 3), 0.2)
    out = composite(glow, g, "light")
    assert (out > g * 0.8).all() and not np.allclose(out, 0.2), "a faint glow lightens the ground"
    ray = np.full((1, 1, 3), 0.4)
    assert (composite(ray, g, "light") >= g - 1e-9).all(), "a grey ray never darkens the ground"
    print("ok")


def render(src, dst, ground, mode):
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", src, "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", f"{W}x{H}", "-"], stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                            "-r", "24", "-i", "-", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "16",
                            "-profile:v", "high", "-level", "4.1", "-vf", "scale=out_color_matrix=bt709:out_range=tv",
                            "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709",
                            "-color_trc", "bt709", "-color_range", "tv", "-movflags", "+faststart",
                            dst], stdin=subprocess.PIPE)
    g = np.array(ground) / 255.0
    size = W * H * 3
    while chunk := dec.stdout.read(size):
        if len(chunk) < size: break
        f = np.frombuffer(chunk, np.uint8).reshape(H, W, 3) / 255.0
        enc.stdin.write((composite(f, g, mode) * 255 + 0.5).astype(np.uint8).tobytes())
    enc.stdin.close(); dec.wait()
    if enc.wait() or dec.returncode: sys.exit(f"render failed: {dst}")


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]: check(); sys.exit()
    src_dir, out_dir = sys.argv[1:3]
    for name, (file, mode) in CLIPS.items():
        for skin, ground in SKINS.items():
            render(f"{src_dir}/{file}", f"{out_dir}/welcome-{name}-{skin}.mp4", ground, mode)
            print("wrote", name, skin)
