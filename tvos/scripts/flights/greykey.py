#!/usr/bin/env python3
"""Lift a generated pigeon flight off its flat grey studio backdrop.

The clip ends on the empty backdrop (Kling end frame), so the last frames ARE the clean plate.
Per pixel: d = C - B. Where the bird is solid, F (its own colour) is known; it is spread into
the soft edges (push-pull), and alpha = (C-B).(F-B) / |F-B|^2, clamped: the exact unmixing of a
premultiplied blend over a known ground, so motion blur and feather tips come out as true
partial alpha. Output colour is premultiplied: P = C - (1-a) B.
"""
import subprocess, sys, numpy as np, cv2

def frames(path, w, h):
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    n = w * h * 3
    while (b := p.stdout.read(n)) and len(b) == n:
        yield np.frombuffer(b, np.uint8).reshape(h, w, 3)

def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", path], capture_output=True, text=True, check=True).stdout
    w, h = map(int, out.strip().split(","))
    return w, h

def pushpull(v, known):
    out = v.copy(); have = known.copy()
    for s in (3, 6, 12, 24, 48, 96):
        num = cv2.GaussianBlur(v * known[..., None], (0, 0), s); den = cv2.GaussianBlur(known, (0, 0), s)
        fill = (have < 0.5) & (den > 1e-4)
        out[fill] = num[fill] / den[fill][..., None]; have[fill] = 1
    return out

def backdropish(C, B, t=15.0, min_area=30):
    """Pixels that are the backdrop showing through: within t of the plate, in patches of at
    least min_area px (a lone near-grey pixel in a feather is the feather), and colourless as the
    backdrop is: a plate guessed under a wing that fills the frame can sit near the wing's own
    brown, and those feathers must stay solid (Loop and Swerve's closing wing, 2026-10-07)."""
    C = C.astype(np.float32)
    near = ((np.linalg.norm(C - B, axis=2) < t) & (C.max(axis=2) - C.min(axis=2) < 12)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(near, connectivity=8)
    big = st[:, cv2.CC_STAT_AREA] >= min_area
    big[0] = False
    return big[lab]

def key(C, B, solid_t=38.0, noise_t=7.0):
    C = C.astype(np.float32); D = C - B
    d = np.linalg.norm(D, axis=2)
    raw = (d > solid_t).astype(np.uint8)
    solid = cv2.morphologyEx(raw, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    # holes inside the bird (a feather that happens to be near the grey) are bird
    inv = 1 - solid
    n, lab, st, _ = cv2.connectedComponentsWithStats(inv, 8)
    H, W = solid.shape
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if not (x == 0 or y == 0 or x + w >= W or y + h >= H) and area < 0.002 * W * H:
            solid[lab == i] = 1
    # ...but backdrop seen between the feathers or between the wings is not (2026-10-07: the
    # closing and the hole fill made those gaps opaque grey, the "grey flecks between the
    # feathers"). Pixels made solid only by the fill keep their unmixed alpha where they are
    # backdrop; a pale feather near the grey differs from it by more than 15 and stays solid.
    solid[(raw == 0) & backdropish(C, B)] = 0
    solidf = solid.astype(np.float32)
    # F is a smooth colour field; spread it at a quarter of the size and bring it back up.
    q = (C.shape[1] // 4, C.shape[0] // 4)
    sq = cv2.resize(solidf, q, interpolation=cv2.INTER_AREA)
    Fq = pushpull(cv2.resize(C * solidf[..., None], q, interpolation=cv2.INTER_AREA) / np.maximum(sq, 1e-3)[..., None] * (sq > 0.5)[..., None], (sq > 0.5).astype(np.float32))
    F = cv2.resize(Fq, (C.shape[1], C.shape[0]), interpolation=cv2.INTER_LINEAR)
    F = np.where(solid[..., None] > 0, C, F)
    FB = F - B
    a = np.einsum("ijk,ijk->ij", D, FB) / np.maximum(np.einsum("ijk,ijk->ij", FB, FB), 25.0)
    a = np.clip(a, 0, 1)
    a = np.where(d < noise_t, 0, a)
    # The generator draws a soft shadow of the bird on the backdrop: grey made darker, with
    # no colour, while the bird is warm brown. Colourless change away from the bird's body is
    # backdrop. Near the body (feather edges, blur) it is kept.
    chroma = np.linalg.norm(D - D.mean(axis=2, keepdims=True), axis=2)
    # Up to the body's edge too: a soft feather edge is a blend of warm brown and grey and keeps
    # a share of the brown's colour; a shadow has none. Only the solid body itself is exempt.
    core = cv2.erode(solid, np.ones((5, 5), np.uint8)) > 0
    shadow = (~core) & (chroma < np.maximum(6.0, 0.28 * d))
    a = np.where(shadow, 0, a)
    a = np.maximum(a, solidf * (cv2.erode(solid, np.ones((3, 3), np.uint8)) > 0))
    # The generator rings a thin bright halo round the bird (edge sharpening). Pull the matte in
    # by CHOKE px at 4K (scaled for smaller sources) with a soft edge; feather tips lose nothing
    # visible, the halo goes.
    k = max(1, round(3 * C.shape[1] / 3840))
    a = np.minimum(a, cv2.GaussianBlur(cv2.erode(a, np.ones((2 * k + 1, 2 * k + 1), np.uint8)), (0, 0), k * 0.6))
    # drop shapes with no solid bird in them (noise, compression blobs)
    m = (a > 0.03).astype(np.uint8)
    n, lab = cv2.connectedComponents(m, connectivity=8)
    if n > 1:
        cnt = np.bincount(lab[solid > 0].ravel(), minlength=n); keep = cnt >= 200; keep[0] = False
        a = np.where(keep[lab], a, 0)
    P = np.clip(C - (1 - a[..., None]) * B, 0, 255)
    P = np.minimum(P, a[..., None] * 255)
    return P, a

if __name__ == "__main__":
    src, out_png_dir = sys.argv[1], sys.argv[2]
    w, h = probe(src)
    fr = list(frames(src, w, h))
    B = np.median(np.stack(fr[-4:]).astype(np.float32), axis=0)
    print("plate mean", B.reshape(-1, 3).mean(0).round(1), "plate std", B.reshape(-1, 3).std(0).round(2), "frames", len(fr))
    for i in [int(x) for x in sys.argv[3:]]:
        P, a = key(fr[i], B)
        rgba = np.dstack([P, a * 255]).astype(np.uint8)
        cv2.imwrite(f"{out_png_dir}/k{i:03d}.png", cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA))
