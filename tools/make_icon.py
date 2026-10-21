#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# US-16x08 Panel: an unofficial control panel for the TASCAM US-16x08.
# Not affiliated with TASCAM / TEAC Corporation, the Linux kernel or ALSA
# maintainers, or the GNU Project.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version. It is distributed WITHOUT ANY WARRANTY. See the file COPYING.
"""Renders the app icon: a brushed-metal bezel around black "bio-cell" panels, an homage to the cell
pattern on the original panel's side areas (the pattern here is our own, not a copy).

macOS template: 1024x1024 canvas, 824x824 squircle body centred (100 px margin), soft drop shadow.
Needs numpy, scipy and Pillow. Writes Resources/AppIcon*.png, AppIcon.iconset/ and AppIcon.icns.
"""
import io, os, struct, sys
import numpy as np
from scipy import ndimage as ndi
from PIL import Image

def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)

def poisson(rng, k, n, hero, hero_r, min_d, margin):
    pts = [hero]
    for _ in range(20000):
        p = rng.uniform(margin, n - margin, 2)
        if np.hypot(*(p - hero)) < hero_r: continue
        if all(np.hypot(*(p - q)) >= min_d for q in pts):
            pts.append(p)
            if len(pts) >= k: break
    return np.array(pts)

def render_body(n, detail=True, led=True, seed=7, k=13):
    """Returns (rgb float array n*n*3, alpha n*n) for the icon body at n pixels square."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    # --- squircle silhouette (superellipse, exponent 5 approximates Apple's continuous corner) ---
    u = (xx - (n - 1) / 2) / (n / 2); v = (yy - (n - 1) / 2) / (n / 2)
    q = (np.abs(u) ** 5 + np.abs(v) ** 5) ** 0.2
    gy, gx = np.gradient(q)
    dist_in = (1 - q) / np.maximum(np.hypot(gx, gy), 1e-6)          # px to the silhouette edge
    plate = np.clip(dist_in + 0.5, 0, 1)
    # --- bezel ---
    bw = n * (0.056 if detail else 0.075)
    t = np.clip(dist_in / bw, 0, 1)
    in_bezel = (dist_in > 0) & (dist_in < bw)
    h_bezel = np.where(in_bezel, np.sqrt(np.clip(1 - (2 * t - 1) ** 2, 0, 1)), 0)
    bezel_a = np.clip(bw - dist_in + 0.5, 0, 1) * plate
    # --- voronoi web ---
    hero = np.array([n * 0.46, n * 0.47])
    kk = k if detail else 7
    seeds = poisson(rng, kk, n, hero, n * (0.24 if detail else 0.28), n * (0.17 if detail else 0.3), bw * 1.4)
    allp = [seeds] + [np.c_[-seeds[:, 0], seeds[:, 1]], np.c_[2 * n - seeds[:, 0], seeds[:, 1]],
                      np.c_[seeds[:, 0], -seeds[:, 1]], np.c_[seeds[:, 0], 2 * n - seeds[:, 1]]]
    allp = np.vstack(allp)
    big = np.float32(1e9)
    d1 = np.full((n, n), big, np.float32); d2 = d1.copy(); idx = np.zeros((n, n), np.int32)
    for i, (px, py) in enumerate(allp):
        d = np.hypot(xx - px, yy - py).astype(np.float32)
        d2 = np.minimum(d2, np.maximum(d1, d))
        idx = np.where(d < d1, i, idx)
        d1 = np.minimum(d1, d)
    edge = (d2 - d1) / 2
    w = n * (0.0155 if detail else 0.034)                             # half width of a web strand
    r = n * (0.024 if detail else 0.04)                               # corner radius of the cells
    cell0 = edge > w
    eroded = ndi.distance_transform_edt(cell0) > r                    # opening = erode, then dilate:
    dt2 = ndi.distance_transform_edt(~eroded)                         # rounds every convex cell corner
    interior = smooth(r - dt2, -0.7, 0.7).astype(np.float32)
    web = 1 - interior
    # One height map for strands AND bezel: blur the combined metal shape so every edge gets the same
    # chamfer, then add a gentle hump across the bezel so it reads as a rounded frame.
    metal_a = np.maximum(web, bezel_a) * plate
    H = ndi.gaussian_filter(metal_a, w * 0.55) + 0.30 * h_bezel
    # --- lighting (light from the upper left) ---
    gyh, gxh = np.gradient(ndi.gaussian_filter(H, 0.8))
    z = w * 1.3
    nx, ny, nz = -gxh * z, -gyh * z, np.ones_like(H)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz); nx, ny, nz = nx / ln, ny / ln, nz / ln
    L = np.array([-0.55, -0.62, 0.56]); L = L / np.linalg.norm(L)
    diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    hv = L + np.array([0, 0, 1.0]); hv = hv / np.linalg.norm(hv)
    spec = np.clip(nx * hv[0] + ny * hv[1] + nz * hv[2], 0, 1) ** 38
    streak = ndi.gaussian_filter(rng.normal(size=(n, n)).astype(np.float32), (0.5, n * 0.03))
    streak = streak / max(np.abs(streak).max(), 1e-6)
    grain = rng.normal(size=(n, n)).astype(np.float32)
    metal = (0.80 + 0.06 * streak * (1 if detail else 0.3)) * (0.46 + 0.72 * diff) + 0.62 * spec
    metal_rgb = np.stack([metal * 0.97, metal * 0.985, metal * 1.0], -1)
    # --- cells: near black, fine grain, occluded and shadowed by the web ---
    ao = ndi.gaussian_filter(metal_a, n * 0.035)
    sh = ndi.gaussian_filter(np.roll(np.roll(metal_a, int(n * 0.007), 0), int(n * 0.006), 1), n * 0.008)
    cell = (0.050 + (0.010 * grain if detail else 0)) * (1 - 0.75 * ao) * (1 - 0.7 * sh)
    cell += 0.030 * smooth(1 - (u + 0.55) ** 2 - (v + 0.6) ** 2 * 0.8, 0, 1)     # faint sheen, upper left
    cell_rgb = np.stack([cell, cell, cell * 1.04], -1)
    rgb = metal_rgb * metal_a[..., None] + cell_rgb * (1 - metal_a[..., None])
    # --- LED meter ladder in the biggest cell ---
    if led:
        inner = (interior > 0.5) & (dist_in > bw * 1.05)
        cells_ids = np.where(inner, idx, -1)
        ids, counts = np.unique(cells_ids[cells_ids >= 0], return_counts=True)
        cid = ids[np.argmax(counts)]
        mask = cells_ids == cid
        dt = ndi.distance_transform_edt(mask)
        cy, cx = np.unravel_index(np.argmax(dt), dt.shape)
        rad = dt.max()
        segs = 14 if detail else 8
        seg_h = rad * (0.092 if detail else 0.17); gap = seg_h * 0.40
        total = segs * seg_h + (segs - 1) * gap
        seg_w = rad * (0.62 if detail else 0.8)
        lit = int(segs * 0.72)
        glow = np.zeros((n, n), np.float32); col = np.zeros((n, n, 3), np.float32); dim = np.zeros((n, n, 3), np.float32)
        top = cy - total / 2
        for s in range(segs):                       # s = 0 at the bottom
            y1 = top + total - (s + 1) * seg_h - s * gap; y0 = y1 + seg_h
            frac = s / (segs - 1)
            c = np.array([0.20, 0.85, 0.40]) if frac < 0.66 else (np.array([0.97, 0.80, 0.18]) if frac < 0.85 else np.array([0.95, 0.27, 0.22]))
            r = (yy >= y1) & (yy <= y0) & (np.abs(xx - cx) <= seg_w / 2)
            r = ndi.gaussian_filter(r.astype(np.float32), 0.9)
            if s < lit:
                col += r[..., None] * c; glow += r
            else:
                dim += r[..., None] * c * 0.16
        halo = ndi.gaussian_filter(glow, n * 0.012)
        rgb = rgb + dim * 1.0 + col * 1.0 + halo[..., None] * np.array([0.10, 0.22, 0.12]) * 0.9
        rgb = np.where((glow[..., None] > 0.05), np.maximum(rgb, col), rgb)
    return np.clip(rgb, 0, 1), plate

def compose(size, detail, led, seed):
    """Full icon at `size` px with the macOS margin and shadow."""
    body = max(8, round(size * 824 / 1024))
    ss = 2 if size >= 128 else 4
    rgb, a = render_body(body * ss, detail, led, seed)
    img = np.dstack([rgb, a])
    im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGBA').resize((body, body), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    m = (size - body) // 2
    # soft shadow in the margin, as in Apple's template
    alpha = np.array(im.split()[3], np.float32) / 255
    sh = np.zeros((size, size), np.float32)
    off = int(round(size * 0.0098))
    sh[m + off:m + off + body, m:m + body] = alpha
    sh = ndi.gaussian_filter(sh, size * 0.0125) * 0.50
    shadow = Image.fromarray((np.dstack([np.zeros((size, size, 3)), sh]) * 255 + 0.5).astype(np.uint8), 'RGBA')
    out = Image.alpha_composite(out, shadow)
    out.alpha_composite(im, (m, m))
    return out

def png_bytes(im):
    b = io.BytesIO(); im.save(b, 'PNG', optimize=True); return b.getvalue()

if __name__ == '__main__':
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources')
    os.makedirs(root, exist_ok=True)
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    only_preview = '--preview' in sys.argv
    if only_preview:
        compose(1024, True, False, seed).save(os.path.join('/tmp', f'icon_preview_{seed}.png'))
        sys.exit(0)
    sizes = {s: compose(s, s >= 128, False, seed) for s in (16, 32, 64, 128, 256, 512, 1024)}
    sizes[1024].save(os.path.join(root, 'AppIcon-1024.png'))
    iconset = os.path.join(root, 'AppIcon.iconset'); os.makedirs(iconset, exist_ok=True)
    names = {'icon_16x16.png': 16, 'icon_16x16@2x.png': 32, 'icon_32x32.png': 32, 'icon_32x32@2x.png': 64,
             'icon_128x128.png': 128, 'icon_128x128@2x.png': 256, 'icon_256x256.png': 256, 'icon_256x256@2x.png': 512,
             'icon_512x512.png': 512, 'icon_512x512@2x.png': 1024}
    for name, s in names.items(): sizes[s].save(os.path.join(iconset, name))
    # .icns assembled directly (PNG payloads), so no iconutil is needed
    types = [('icp4', 16), ('icp5', 32), ('icp6', 64), ('ic07', 128), ('ic08', 256), ('ic09', 512), ('ic10', 1024),
             ('ic11', 32), ('ic12', 64), ('ic13', 256), ('ic14', 512)]
    body = b''.join(t.encode() + struct.pack('>I', 8 + len(d)) + d for t, d in ((t, png_bytes(sizes[s])) for t, s in types))
    with open(os.path.join(root, 'AppIcon.icns'), 'wb') as f:
        f.write(b'icns' + struct.pack('>I', 8 + len(body)) + body)
    print('wrote icon set and .icns to', os.path.normpath(root))
