#!/usr/bin/env python3
"""Render a generated pigeon flight (grey backdrop, ends empty) onto each skin's ground, as
ordinary opaque video: H.264 at 1080 and, from a 4K source, HEVC at 2160. Usage:
render_flight.py <src.mp4> <out_dir> <name>  ->  flight-<name>-<skin>-<tier>.mp4

Opaque, not HEVC with alpha (2026-10-05): the Apple TV HD has no hardware for HEVC with
alpha, decodes it in software, and measured on the owner's box delivered 37-99 of 90-116
frames per flight while a channel tuned, the bird a 720p file stretched to 1080. Both
H.264 1080 and HEVC 2160 decode in hardware where they are played."""
import os, subprocess, sys, numpy as np, cv2
sys.path.insert(0, os.path.dirname(__file__))
from greykey import frames, probe, key

TIERS = {"2160": (3840, 2160), "1080": (1920, 1080)}
OVERLAY_TIERS = {"1080": (1920, 1080), "720": (1280, 720)}
# Kept in step with Skin.groundHex in KhajistanTV/Core/Sky.swift.
SKINS = {"day": (0xF3, 0xFB, 0x04), "grove": (0x18, 0x64, 0x09), "smut": (0xC1, 0x1B, 0x6B)}
CODEC = {
    "1080": ["-c:v", "libx264", "-preset", "slow", "-crf", "12", "-profile:v", "high", "-level", "4.2"],
    "2160": ["-c:v", "libx265", "-preset", "medium", "-crf", "14", "-tag:v", "hvc1", "-x265-params", "log-level=error"],
}
# A 1080p source gets no 2160 file: an enlargement adds no detail, and the app falls back to
# the largest size a flight has.

def matcher(name):
    """Lab mean/std transfer from this clip's bird to the reference bird (the Kling flights),
    so a Seedance flight wears the same plumage. Contrast gain capped at 1.5."""
    import json
    try:
        c = json.load(open(os.path.join(os.path.dirname(__file__), "colour.json")))
    except FileNotFoundError:
        return None
    if name not in c: return None
    rm, rs = np.array(c["ref"]["mean"]), np.array(c["ref"]["std"])
    tm, ts = np.array(c[name]["mean"]), np.array(c[name]["std"])
    gain = np.minimum(rs / ts, 1.5)
    def apply(P, a):
        F = P / np.maximum(a[..., None], 1e-3) / 255.0
        lab = cv2.cvtColor(F.astype(np.float32), cv2.COLOR_RGB2LAB)
        lab = (lab - tm) * gain + rm
        F2 = np.clip(cv2.cvtColor(lab.astype(np.float32), cv2.COLOR_LAB2RGB), 0, 1)
        return F2 * 255.0 * a[..., None]
    return apply

def frame_plate(C):
    """The backdrop under one frame, for a cover flight. Seedance relights its grey as the bird
    pulls back from the lens, so one plate for the whole flight drew grey arcs where the
    vignette moved (2026-10-05). The backdrop is smooth and colourless and the bird is warm,
    so each frame's own colourless pixels are spread under the bird by normalised blur."""
    h, w = C.shape[:2]
    s = cv2.resize(C, (w // 16, h // 16), interpolation=cv2.INTER_AREA).astype(np.float32)
    c = np.linalg.norm(s - s.mean(axis=2, keepdims=True), axis=2)
    lum = s.mean(axis=2)
    m = c < 14
    if m.sum() < 20: return None
    # The cream head and pale breast are colourless too, and brighter than the backdrop. A
    # vignette darkens the corners (Loop) and a lit floor brightens the bottom (Roller), so a
    # region is refused only when it is both bright and small: the head is a patch, the floor
    # a band (2026-10-05).
    ref = np.median(lum[m])
    n, labels, stats, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8), connectivity=8)
    keep = np.zeros(n, bool)
    for i in range(1, n):
        region = labels == i
        keep[i] = lum[region].mean() - ref < 35 or stats[i, cv2.CC_STAT_AREA] > 0.05 * m.size
    m = keep[labels].astype(np.float32)
    if m.sum() < 20: return None
    k = (0, 0)
    sig = max(s.shape) / 8
    num = cv2.GaussianBlur(s * m[..., None], k, sig)
    den = cv2.GaussianBlur(m, k, sig)[..., None]
    fill = num / np.maximum(den, 1e-3)
    s = np.where(m[..., None] > 0, s, fill)
    return cv2.resize(cv2.GaussianBlur(s, k, 1.0), (w, h), interpolation=cv2.INTER_CUBIC)

def main(src, out_dir, name, ending=None):
    match = matcher(name)
    w, h = probe(src)
    # Pass 1, small: the plate (the last frames, empty by construction) and where the bird ends.
    sw, sh = w // 8, h // 8
    small = [cv2.resize(f, (sw, sh), interpolation=cv2.INTER_AREA).astype(np.float32) for f in frames(src, w, h)]
    bs = np.median(np.stack(small[-4:]), axis=0)
    present = [i for i, f in enumerate(small) if (np.linalg.norm(f - bs, axis=2) > 25).sum() > 3]
    last = min(len(small), present[-1] + 3) if present else len(small)
    # Every frame plays at the speed it was generated (owner, 2026-10-06: "the speed is
    # unrealistic, it needs to be more like the original"). Retiming an opening or a soft
    # stretch sped the wingbeats up with it, and that read as fake. Only the end is cut: the
    # clip stops where a bird already off the screen stops moving, rather than leaving a speck.
    d = [float(np.abs(small[i] - small[i - 1]).mean()) for i in range(1, last)]
    pace = float(np.median(d)) if d else 0
    keep = list(range(last))
    moving = [k for k, x in enumerate(d) if x >= 0.12 * pace]
    if moving: keep = [k for k in keep if k <= moving[-1] + 2]
    # A bird still on screen at the last frame never left: it fades over the last 6 frames. A
    # sliver at the edge as it leaves does not count — fading on that turned Across's closing
    # wing, half the screen, into a ghost (2026-10-05).
    stuck = float((np.linalg.norm(small[keep[-1]] - bs, axis=2) > 25).mean()) > 0.01
    if ending == "covered":
        # The flight ends on the wing filling the screen and the channel cuts in behind it:
        # nothing is trimmed and nothing fades (render_flight.py <src> <out> <name> covered).
        keep, stuck = list(range(len(small))), False
    total = len(small); del small
    # The plate. Two candidates, each wrong somewhere: the last frames (wrong where a flight
    # has not left by its end) and each pixel's median over the flight (wrong where the bird
    # sits in one place for most of it). The backdrop is colourless and the bird is warm
    # brown, so per pixel the candidate closer to neutral grey is the backdrop.
    step = max(1, total // 48)
    picks, lasts = [], []
    for i, f in enumerate(frames(src, w, h)):
        if i % step == 0: picks.append(f.copy())
        if i >= total - 4: lasts.append(f.copy())
    med = np.median(np.stack(picks), axis=0).astype(np.float32)
    end = np.median(np.stack(lasts), axis=0).astype(np.float32)
    def chroma(c): return np.linalg.norm(c - c.mean(axis=2, keepdims=True), axis=2)
    B = np.where((chroma(end) <= chroma(med))[..., None], end, med)
    del picks, lasts
    encs = {}
    # KJ_OVERLAY=1: the bird alone, HEVC with alpha (premultiplied), to fly over the live picture
    # while the channel cuts behind it (owner, 2026-10-06: "hard cut ... and the pigeon
    # transition on it"); plus flight-<name>.json with its length and the frame where the bird
    # covers the most of the screen, which is where the app cuts.
    overlay = os.environ.get("KJ_OVERLAY") in ("1", "2")
    # KJ_OVERLAY=2: the same bird as two ordinary H.264 videos the Apple TV HD decodes in
    # hardware — flight-<name>-rgb-1080.mp4, its colour carried past its edge so a soft matte
    # leaves no fringe, and flight-<name>-matte-540.mp4, its alpha as luma, full range. The app
    # composites the pair on the GPU (HEVC with alpha is software-decoded there and dropped a
    # third to two-thirds of its frames while a channel tuned, measured 2026-10-06).
    pair = os.environ.get("KJ_OVERLAY") == "2"
    if pair:
        tiers = {"1080": (1920, 1080)}
        base = ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-r", "24"]
        h264 = ["-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level", "4.2", "-movflags", "+faststart", "-an"]
        encs["1080", "rgb"] = subprocess.Popen(base + ["-pix_fmt", "rgb24", "-s", "1920x1080", "-i", "-", *h264, "-crf", "14",
            "-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
            os.path.join(out_dir, f"flight-{name}-rgb-1080.mp4")], stdin=subprocess.PIPE)
        encs["1080", "matte"] = subprocess.Popen(base + ["-pix_fmt", "gray", "-s", "960x540", "-i", "-", *h264, "-crf", "10",
            "-pix_fmt", "yuvj420p", "-color_range", "pc", os.path.join(out_dir, f"flight-{name}-matte-540.mp4")], stdin=subprocess.PIPE)
    for tier, (tw, th) in ({} if pair else tiers).items():
        if overlay:
            path = os.path.join(out_dir, f"flight-{name}-alpha-{tier}.mov")
            encs[tier, "alpha"] = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
                "-s", f"{tw}x{th}", "-r", "24", "-i", "-", "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9",
                "-q:v", "75", "-tag:v", "hvc1", "-pix_fmt", "bgra", "-an", path], stdin=subprocess.PIPE)
            continue
        for skin in SKINS:
            path = os.path.join(out_dir, f"flight-{name}-{skin}-{tier}.mp4")
            encs[tier, skin] = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                "-s", f"{tw}x{th}", "-r", "24", "-i", "-", *CODEC[tier], "-pix_fmt", "yuv420p",
                "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
                "-movflags", "+faststart", "-an", path], stdin=subprocess.PIPE)
    grounds = {} if overlay else {k: np.array(v, np.float32) for k, v in SKINS.items()}
    order = {k: n for n, k in enumerate(keep)}
    cover = []
    for i, C in enumerate(frames(src, w, h)):
        if i > keep[-1]: break
        if i not in order: continue
        # A flight that ends on the wing has no empty frames to read the backdrop from, so each
        # frame's own backdrop is used.
        Bf = frame_plate(C) if ending == "covered" else None
        P, a = key(C, B if Bf is None else Bf)
        if ending == "covered":
            # Near the lens the wing's pale feathers read as backdrop and let the picture through
            # (2026-10-06). Backdrop always reaches the frame's edge; a hole enclosed by the bird
            # is feathers, so it is filled solid.
            solid = (a > 0.5).astype(np.uint8)
            outside = solid.copy()
            mask = np.zeros((h + 2, w + 2), np.uint8)
            for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] + [(x, 0) for x in range(0, w, 64)] + [(x, h - 1) for x in range(0, w, 64)] + [(0, y) for y in range(0, h, 64)] + [(w - 1, y) for y in range(0, h, 64)]:
                if outside[y, x] == 0: cv2.floodFill(outside, mask, (x, y), 2)
            # The bird's inside, a few pixels in from its edge, is solid; the edge keeps its softness.
            inner = cv2.erode((outside != 2).astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
            a = np.where(inner, 1.0, a).astype(np.float32)
            P = np.where(inner[..., None], C.astype(np.float32), P)
        if match is not None: P = match(P, a)
        if i % 20 == 0: print(f"  {name}: {i}/{last}", flush=True)
        # A flight that is still on the edge at its last frame fades over its last 6 frames.
        tail = len(keep) - 1 - order[i]
        if stuck and tail < 6:
            fade = (tail + 1) / 7.0
            P, a = P * fade, a * fade
        cover.append(float(a.mean()))
        for tier, (tw, th) in tiers.items():
            if (tw, th) == (w, h): Pt, at = P, a
            else:
                Pt = cv2.resize(P.astype(np.float32), (tw, th), interpolation=cv2.INTER_AREA)
                at = cv2.resize(a.astype(np.float32), (tw, th), interpolation=cv2.INTER_AREA)
            if pair:
                # Colour with the bird's own colour spread past its edge (normalised blur of the
                # premultiplied picture), so where the matte is soft the edge is still the bird.
                spread_p = cv2.GaussianBlur(Pt.astype(np.float32), (0, 0), 6)
                spread_a = cv2.GaussianBlur(at.astype(np.float32), (0, 0), 6)[..., None]
                inside = Pt / np.maximum(at[..., None], 1e-3)
                outside = spread_p / np.maximum(spread_a, 1e-3)
                rgb = np.where(at[..., None] > 0.5, inside, np.where(spread_a > 0.002, outside, 0))
                encs["1080", "rgb"].stdin.write(np.clip(rgb + 0.5, 0, 255).astype(np.uint8).tobytes())
                matte = cv2.resize(at.astype(np.float32), (960, 540), interpolation=cv2.INTER_AREA)
                encs["1080", "matte"].stdin.write(np.clip(matte * 255 + 0.5, 0, 255).astype(np.uint8).tobytes())
                continue
            if overlay:
                rgba = np.dstack([Pt, at * 255])
                encs[tier, "alpha"].stdin.write(np.clip(rgba + 0.5, 0, 255).astype(np.uint8).tobytes())
            for skin, g in grounds.items():
                # P is premultiplied: the ground shows through by what the bird leaves uncovered.
                img = Pt + g * (1 - at[..., None])
                encs[tier, skin].stdin.write(np.clip(img + 0.5, 0, 255).astype(np.uint8).tobytes())
    for e in encs.values():
        e.stdin.close(); e.wait()
    if overlay:
        import json
        # The last frame within a tenth of the most the bird covers: a flight that opens and
        # closes on the wing cuts at the closing wing, which the new channel has had time to reach.
        top = max(cover)
        peak = max(i for i, c in enumerate(cover) if c >= 0.9 * top)
        # Every stretch where the bird covers at least half the screen: a ready channel cuts
        # inside one (FlightChoice.shouldCut), not only at the last.
        covered, start = [], None
        for i, c in enumerate(cover + [0.0]):
            if c >= 0.5 and start is None:
                start = i
            elif c < 0.5 and start is not None:
                covered.append([round(start / 24, 2), round((i - 1) / 24, 2)])
                start = None
        json.dump({"length": len(cover) / 24, "cut": peak / 24, "cutCover": round(cover[peak], 3),
                   "covered": covered},
                  open(os.path.join(out_dir, f"flight-{name}.json"), "w"))
        print(f"{name}: cut at {peak / 24:.2f}s, bird covers {cover[peak] * 100:.0f}% there", flush=True)
    print(f"{name}: {len(keep)} frames of {total} (source {keep[0]}-{keep[-1]}, {total - len(keep)} trimmed at the end), {w}x{h} -> {', '.join(tiers)}", flush=True)

if __name__ == "__main__":
    main(*sys.argv[1:5])
