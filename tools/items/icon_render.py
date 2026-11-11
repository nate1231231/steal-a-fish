"""Software renderer for item icons: numpy G-buffer rasterizer + deferred lighting.

Memory-safe: renders at `size * ss` with float32 buffers (default 1024 px when size=512, ss=2) and
downsamples; a second 2x comes from Pillow LANCZOS when the item layer is fitted into the frame, so the
effective supersampling is about 4x on edges. Everything is per-item, nothing is cached between items.

Pipeline:
  1. rasterize triangles into depth / normal / albedo buffers (back faces culled)
  2. thin-part fattening: sliver triangles (fins, sails, legs, barbels, rods) are rendered again, pushed
     outward along their normals and uncullled, so they stay visible at 128 px
  3. lighting: warm key, cool fill, rim, Blinn-Phong specular, hemisphere ambient, SSAO
  4. depth/normal edge detection -> thin subtle darker edge (no black outline)
  5. soft contact shadow below the object
"""
import math

import numpy as np

from meshlib import nrm, rot_x, rot_y

F = np.float32


def box_blur(img, radius):
    """Separable box blur via cumulative sums (2D or 3D array), radius in px."""
    r = int(radius)
    if r < 1:
        return img
    k = 2 * r + 1
    out = img.astype(F)
    for axis in (0, 1):
        pad = [(r, r) if i == axis else (0, 0) for i in range(out.ndim)]
        p = np.pad(out, pad, mode="edge")
        cs = np.cumsum(p, axis=axis, dtype=F)
        zero = np.zeros_like(np.take(cs, [0], axis=axis))
        cs = np.concatenate([zero, cs], axis=axis)
        n = cs.shape[axis]
        out = (np.take(cs, range(k, n), axis=axis) - np.take(cs, range(0, n - k), axis=axis)) / k
    return out


def edges(depth, normal, mask, size):
    d = np.where(mask, depth, np.nan).astype(F)
    e = np.zeros(depth.shape, F)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        a = np.roll(np.roll(d, dy, 0), dx, 1)
        diff = np.abs(d - a)
        diff = np.where(np.isnan(diff), 0, diff)
        e = np.maximum(e, np.clip(diff / F(0.02 * size) - 0.1, 0, 1))
        na = np.roll(np.roll(normal, dy, 0), dx, 1)
        dot = (normal * na).sum(-1)
        e = np.maximum(e, np.clip((0.55 - dot) * 1.6, 0, 1) * mask)
    return e * mask


def ssao(depth, mask, size, radius, samples=10):
    occ = np.zeros(depth.shape, F)
    for k in range(samples):
        a = 2 * math.pi * k / samples + 0.2
        for r in (radius * 0.4, radius):
            dy, dx = int(round(r * math.sin(a))), int(round(r * math.cos(a)))
            z = np.roll(np.roll(depth, dy, 0), dx, 1)
            m = np.roll(np.roll(mask, dy, 0), dx, 1)
            delta = z - depth
            occ += np.where(m & (delta > 0.004 * size) & (delta < 0.12 * size), F(1), F(0))
    occ /= samples * 2
    return np.clip(occ * 1.4, 0, 1) * mask


class GBuffer:
    def __init__(self, size):
        self.size = size
        self.depth = np.full((size, size), -1e9, F)
        self.normal = np.zeros((size, size, 3), F)
        self.albedo = np.zeros((size, size, 3), F)
        self.mask = np.zeros((size, size), bool)

    def raster(self, P, N, U, tex, sx, sy, z, cull=True):
        size = self.size
        th, tw = tex.shape[:2]
        for f in range(len(P)):
            x0, y0, x1, y1, x2, y2 = sx[f, 0], sy[f, 0], sx[f, 1], sy[f, 1], sx[f, 2], sy[f, 2]
            area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
            if abs(area) < 1e-9 or (cull and area >= 0):
                continue
            bx0, bx1 = int(max(min(x0, x1, x2), 0)), int(min(max(x0, x1, x2) + 1, size))
            by0, by1 = int(max(min(y0, y1, y2), 0)), int(min(max(y0, y1, y2) + 1, size))
            if bx0 >= bx1 or by0 >= by1:
                continue
            gy, gx = np.mgrid[by0:by1, bx0:bx1].astype(F) + F(0.5)
            w0 = ((x1 - gx) * (y2 - gy) - (x2 - gx) * (y1 - gy)) / area
            w1 = ((x2 - gx) * (y0 - gy) - (x0 - gx) * (y2 - gy)) / area
            w2 = 1 - w0 - w1
            m = (w0 >= -1e-5) & (w1 >= -1e-5) & (w2 >= -1e-5)
            if not m.any():
                continue
            zz = w0 * z[f, 0] + w1 * z[f, 1] + w2 * z[f, 2]
            sub = self.depth[by0:by1, bx0:bx1]
            m &= zz > sub
            if not m.any():
                continue
            nn = w0[..., None] * N[f, 0] + w1[..., None] * N[f, 1] + w2[..., None] * N[f, 2]
            if area > 0:
                nn = -nn
            nn /= np.maximum(np.linalg.norm(nn, axis=-1, keepdims=True), 1e-9)
            uu = w0 * U[f, 0, 0] + w1 * U[f, 1, 0] + w2 * U[f, 2, 0]
            vv = w0 * U[f, 0, 1] + w1 * U[f, 1, 1] + w2 * U[f, 2, 1]
            tx = np.clip((uu * tw).astype(int), 0, tw - 1)
            ty = np.clip(((1 - vv) * th).astype(int), 0, th - 1)
            sub[m] = zz[m]
            self.normal[by0:by1, bx0:bx1][m] = nn[m]
            self.albedo[by0:by1, bx0:bx1][m] = tex[ty, tx][m]
            self.mask[by0:by1, bx0:bx1][m] = True


def render_item(mesh, tex, size=512, ss=2, yaw=-35.0, pitch=22.0, thin_boost=1.0,
                key_dir=(-0.5, 0.8, 0.6), fill_dir=(0.8, 0.3, 0.5), rim_dir=(0.3, 0.6, -0.9), ortho_mix=0.4):
    """Returns (rgb HxWx3 float32 0..1, alpha HxW, shadow HxW) at `size`, object filling the frame."""
    S = size * ss
    tex = tex.astype(F)
    P, N, U = mesh.arrays()
    R = (rot_x(math.radians(pitch)) @ rot_y(math.radians(yaw))).astype(F)
    P = (P @ R.T).astype(F)
    N = (N @ R.T).astype(F)
    U = U.astype(F)
    # thin features: slivers / tiny triangles relative to the model size
    e1, e2 = P[:, 1] - P[:, 0], P[:, 2] - P[:, 0]
    area = 0.5 * np.linalg.norm(np.cross(e1, e2), axis=1)
    edge = np.maximum.reduce([np.linalg.norm(e1, axis=1), np.linalg.norm(e2, axis=1),
                              np.linalg.norm(P[:, 2] - P[:, 1], axis=1)])
    flat = P.reshape(-1, 3)
    ext = float((flat.max(0) - flat.min(0)).max())
    thin = ((area < 0.0035 * ext * ext) | (edge / np.maximum(np.sqrt(area), 1e-9) > 4.0)) & (edge < 0.55 * ext)

    lo, hi = flat.min(0), flat.max(0)
    P = P - (lo + hi) / 2
    cam_z = 2.4 * float(max(hi - lo))
    def project(Pp):
        persp = ortho_mix + (1 - ortho_mix) * cam_z / (cam_z - Pp[..., 2])
        return Pp[..., 0] * persp, Pp[..., 1] * persp
    px, py = project(P)
    pxy = np.stack([px.ravel(), py.ravel()], 1)
    lo2, hi2 = pxy.min(0), pxy.max(0)
    scale = 0.92 * S / float(max(hi2 - lo2))
    off = np.array([S / 2, S / 2], F) - scale * (lo2 + hi2) / 2 * np.array([1, -1], F)
    sx, sy = px * scale + off[0], -py * scale + off[1]

    gb = GBuffer(S)
    gb.raster(P, N, U, tex, sx, sy, P[..., 2])
    if thin.any() and thin_boost > 0:
        # Thicken thin parts in screen space: draw the sliver triangles (fins, legs, barbels, rods) into
        # their own G-buffer, dilate it by a few pixels and fill the pixels the main pass left empty.
        tg = GBuffer(S)
        tg.raster(P[thin], N[thin], U[thin], tex, sx[thin], sy[thin], P[thin][..., 2], cull=False)
        r = max(1, int(round(thin_boost * 0.004 * S)))
        src_y, src_x = np.nonzero(tg.mask)
        if len(src_y):
            dil = tg.mask.copy()
            dep, nor, albd = tg.depth.copy(), tg.normal.copy(), tg.albedo.copy()
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if dy * dy + dx * dx > r * r or (dy == 0 and dx == 0):
                        continue
                    yy = np.clip(src_y + dy, 0, S - 1)
                    xx = np.clip(src_x + dx, 0, S - 1)
                    new = ~dil[yy, xx]
                    dil[yy[new], xx[new]] = True
                    dep[yy[new], xx[new]] = tg.depth[src_y[new], src_x[new]] - F(0.002 * ext)
                    nor[yy[new], xx[new]] = tg.normal[src_y[new], src_x[new]]
                    albd[yy[new], xx[new]] = tg.albedo[src_y[new], src_x[new]]
            take = dil & (~gb.mask | (dep > gb.depth))
            gb.mask |= take
            gb.depth[take] = dep[take]
            gb.normal[take] = nor[take]
            gb.albedo[take] = albd[take]

    mask, n, alb = gb.mask, gb.normal, gb.albedo
    V = np.array([0, 0, 1], F)
    key, fill, rim = (nrm(key_dir).astype(F), nrm(fill_dir).astype(F), nrm(rim_dir).astype(F))
    ndl = np.clip(n @ key, 0, 1)
    wrap = np.clip((n @ key + 0.35) / 1.35, 0, 1)
    fill_t = np.clip(n @ fill, 0, 1)
    rim_t = np.clip(n @ rim, 0, 1) ** 2.2 * np.clip(1 - n[..., 2], 0, 1)
    hemi = 0.5 + 0.5 * n[..., 1]
    ao = 1 - 0.75 * box_blur(ssao(gb.depth, mask, S, radius=0.028 * S), ss * 1.5)
    ao = np.clip(ao, 0.25, 1)
    bright = alb.mean(-1)
    gloss = 0.35 + 0.45 * np.clip((bright - 0.45) * 2, 0, 1)
    spec = np.clip(n @ nrm(key + V).astype(F), 0, 1) ** 48 * gloss * 0.9 \
        + np.clip(n @ nrm(fill + V).astype(F), 0, 1) ** 24 * 0.18
    light = ((0.20 + 0.18 * hemi) * ao)[..., None] \
        + (0.95 * wrap * (0.55 + 0.45 * ndl) * ao)[..., None] * np.array([1.0, 0.95, 0.86], F) \
        + (0.32 * fill_t)[..., None] * np.array([0.75, 0.85, 1.0], F) \
        + (0.55 * rim_t)[..., None] * np.array([0.9, 0.95, 1.0], F)
    rgb = alb * light + spec[..., None] * np.array([1.0, 0.97, 0.9], F)
    e = np.clip(box_blur(edges(gb.depth, n, mask, S), ss * 0.5), 0, 1)
    rgb = np.clip(rgb * (1 - 0.35 * e)[..., None], 0, 1)

    def down(a):
        if a.ndim == 2:
            return a.reshape(size, ss, size, ss).mean((1, 3), dtype=F)
        return a.reshape(size, ss, size, ss, a.shape[-1]).mean((1, 3), dtype=F)
    alpha = down(mask.astype(F))
    color = down(rgb * mask[..., None])
    color = np.where(alpha[..., None] > 1e-4, color / np.maximum(alpha[..., None], 1e-4), 0)
    inner = box_blur(alpha, 1.2)
    band = np.clip((alpha - inner) * 2.5, 0, 0.5)
    color = color * (1 - 0.45 * band)[..., None]

    shadow = np.zeros((size, size), F)
    ys, xs = np.nonzero(alpha > 0.05)
    if len(ys):
        bottom = ys.max()
        yy = (bottom + (ys - bottom) * 0.22).astype(int)
        np.add.at(shadow, (np.clip(yy + int(0.03 * size), 0, size - 1), xs), alpha[ys, xs])
        shadow = np.clip(box_blur(np.clip(shadow, 0, 1), size * 0.02) * 0.9, 0, 0.55)
    return np.clip(color, 0, 1), np.clip(alpha, 0, 1), shadow
