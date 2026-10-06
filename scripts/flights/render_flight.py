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

def main(src, out_dir, name):
    match = matcher(name)
    w, h = probe(src)
    # Pass 1, small: the plate (the last frames, empty by construction) and where the bird ends.
    sw, sh = w // 8, h // 8
    small, sharp = [], []
    for f in frames(src, w, h):
        small.append(cv2.resize(f, (sw, sh), interpolation=cv2.INTER_AREA).astype(np.float32))
        # How sharp the bird is: variance of the Laplacian over a quarter-size grey frame,
        # read where the frame is not the flat backdrop.
        q = cv2.cvtColor(cv2.resize(f, (w // 4, h // 4), interpolation=cv2.INTER_AREA), cv2.COLOR_RGB2GRAY)
        bird = np.abs(q.astype(np.int16) - int(np.median(q[:8, :8]))) > 20
        sharp.append(float(cv2.Laplacian(q, cv2.CV_64F)[bird].var()) if bird.sum() > 400 else None)
    bs = np.median(np.stack(small[-4:]), axis=0)
    present = [i for i, f in enumerate(small) if (np.linalg.norm(f - bs, axis=2) > 25).sum() > 3]
    last = min(len(small), present[-1] + 3) if present else len(small)
    # A generated clip eases in from its start frame: the bird glides nearly still, or sits
    # frozen, before it flies (measured 2026-10-05: Approach crawled for two seconds, Rise held
    # one pose for 16 frames). Where the bird is on screen at frame 0, the opening is retimed
    # by dropping frames until it moves at half its median pace, at most three times faster;
    # from there every frame plays. At the other end the clip stops where a bird already off
    # the screen stops moving, rather than leaving a speck at the edge.
    d = [float(np.abs(small[i] - small[i - 1]).mean()) for i in range(1, last)]
    pace = float(np.median(d)) if d else 0
    keep = list(range(last))
    if d and (np.linalg.norm(small[0] - bs, axis=2) > 25).mean() > 0.02:
        keep, acc, i = [0], 0.0, 1
        while i < last and d[i - 1] < 0.5 * pace:
            acc += d[i - 1]
            if acc >= 0.5 * pace or i - keep[-1] >= 3: keep.append(i); acc = 0.0
            i += 1
        keep += range(i, last)
    # Where the bird goes soft — out of focus near the lens (Kling Approach, 2026-10-05: sharpness
    # fell forty-fold for 1.3 s) or smeared in a fast tumble (Seedance Roller: 2 s) — the clip
    # plays at three times speed. A real pigeon crosses a lens in a fifth of a second and a
    # roller's somersault is that quick, so the soft stretch is brief rather than lingering.
    known = [x for x in sharp[:last] if x is not None]
    floor = 0.2 * float(np.median(known)) if known else 0
    run, quick = 0, []
    for k in keep:
        run = run + 1 if sharp[k] is not None and sharp[k] < floor else 0
        if run == 0 or run % 3 == 1: quick.append(k)
    keep = quick
    moving = [k for k, x in enumerate(d) if x >= 0.12 * pace]
    if moving: keep = [k for k in keep if k <= moving[-1] + 2]
    # A bird still on screen at the last frame never left: it fades over the last 6 frames. A
    # sliver at the edge as it leaves does not count — fading on that turned Across's closing
    # wing, half the screen, into a ghost (2026-10-05).
    stuck = float((np.linalg.norm(small[keep[-1]] - bs, axis=2) > 25).mean()) > 0.01
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
    tiers = {t: s for t, s in TIERS.items() if s[0] <= w}
    for tier, (tw, th) in tiers.items():
        for skin in SKINS:
            path = os.path.join(out_dir, f"flight-{name}-{skin}-{tier}.mp4")
            encs[tier, skin] = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                "-s", f"{tw}x{th}", "-r", "24", "-i", "-", *CODEC[tier], "-pix_fmt", "yuv420p",
                "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
                "-movflags", "+faststart", "-an", path], stdin=subprocess.PIPE)
    grounds = {k: np.array(v, np.float32) for k, v in SKINS.items()}
    order = {k: n for n, k in enumerate(keep)}
    for i, C in enumerate(frames(src, w, h)):
        if i > keep[-1]: break
        if i not in order: continue
        P, a = key(C, B)
        if match is not None: P = match(P, a)
        if i % 20 == 0: print(f"  {name}: {i}/{last}", flush=True)
        # A flight that is still on the edge at its last frame fades over its last 6 frames.
        tail = len(keep) - 1 - order[i]
        if stuck and tail < 6:
            fade = (tail + 1) / 7.0
            P, a = P * fade, a * fade
        for tier, (tw, th) in tiers.items():
            if (tw, th) == (w, h): Pt, at = P, a
            else:
                Pt = cv2.resize(P.astype(np.float32), (tw, th), interpolation=cv2.INTER_AREA)
                at = cv2.resize(a.astype(np.float32), (tw, th), interpolation=cv2.INTER_AREA)
            for skin, g in grounds.items():
                # P is premultiplied: the ground shows through by what the bird leaves uncovered.
                img = Pt + g * (1 - at[..., None])
                encs[tier, skin].stdin.write(np.clip(img + 0.5, 0, 255).astype(np.uint8).tobytes())
    for e in encs.values():
        e.stdin.close(); e.wait()
    print(f"{name}: {len(keep)} frames of {total} (source {keep[0]}-{keep[-1]}, {keep[-1] + 1 - len(keep)} dropped to quicken the opening and any soft stretch), {w}x{h} -> {', '.join(tiers)}", flush=True)

if __name__ == "__main__":
    main(*sys.argv[1:4])
