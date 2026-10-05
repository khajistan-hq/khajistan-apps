#!/usr/bin/env python3
"""Render a generated pigeon flight (grey backdrop, ends empty) as HEVC-with-alpha in three
sizes. Usage: render_flight.py <src.mp4> <out_dir> <name>"""
import os, subprocess, sys, numpy as np, cv2
sys.path.insert(0, os.path.dirname(__file__))
from greykey import frames, probe, key

TIERS = {"2160": (3840, 2160), "1080": (1920, 1080), "720": (1280, 720)}
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
    small = [cv2.resize(f, (sw, sh), interpolation=cv2.INTER_AREA).astype(np.float32) for f in frames(src, w, h)]
    bs = np.median(np.stack(small[-4:]), axis=0)
    present = [i for i, f in enumerate(small) if (np.linalg.norm(f - bs, axis=2) > 25).sum() > 3]
    last = min(len(small), present[-1] + 3) if present else len(small)
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
        path = os.path.join(out_dir, f"{name}-{tier}.mov")
        encs[tier] = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
            "-s", f"{tw}x{th}", "-r", "24", "-i", "-", "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9",
            "-q:v", "75", "-tag:v", "hvc1", "-pix_fmt", "bgra", "-an", path], stdin=subprocess.PIPE)
    for i, C in enumerate(frames(src, w, h)):
        if i >= last: break
        P, a = key(C, B)
        if match is not None: P = match(P, a)
        if i % 20 == 0: print(f"  {name}: {i}/{last}", flush=True)
        # A flight that is still on the edge at its last frame fades over its last 6 frames.
        tail = last - 1 - i
        if tail < 6 and (a > 0.02).sum() > 50:
            fade = (tail + 1) / 7.0
            P, a = P * fade, a * fade
        rgba = np.dstack([P, a * 255])
        for tier, (tw, th) in tiers.items():
            img = rgba if (tw, th) == (w, h) else cv2.resize(rgba, (tw, th), interpolation=cv2.INTER_AREA)
            encs[tier].stdin.write(np.clip(img, 0, 255).astype(np.uint8).tobytes())
    for e in encs.values():
        e.stdin.close(); e.wait()
    print(f"{name}: {last} frames ({total} in source, empty tail trimmed), {w}x{h} -> {', '.join(tiers)}", flush=True)

if __name__ == "__main__":
    main(*sys.argv[1:4])
