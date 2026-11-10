"""Tiny mesh toolkit: primitives with explicit outward winding, OBJ export, and a numpy rasterizer.

Conventions (shared by every generator):
  * units = studs, Y-up, front = -Z (Roblox LookVector), pivot at base after finalize()
  * triangles are CCW when seen from outside (Roblox culls back faces, so winding matters)
  * UVs: OBJ standard (v = 0 at the bottom of the image); atlas rects are given in pixels
"""
import json
import math
import os

import numpy as np

ATLAS = 1024


def nrm(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


# ------------------------------------------------------------------ UV helpers
def _px_to_uv(px, py, size=ATLAS):
    return (px / size, 1.0 - py / size)


def uv_swatch(rect, size=ATLAS):
    """Flat color: map every face to a small triangle inside a pixel rect (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    tri = np.array([_px_to_uv(x0 + .25 * w, y0 + .7 * h, size), _px_to_uv(x0 + .75 * w, y0 + .7 * h, size),
                    _px_to_uv(x0 + .5 * w, y0 + .3 * h, size)])
    return lambda pts: tri


def uv_point(rect, fn, size=ATLAS):
    """Per-vertex projection: fn(p) -> (a, b) in 0..1, placed inside rect (a = right, b = down)."""
    x0, y0, x1, y1 = rect

    def f(pts):
        out = []
        for p in pts:
            a, b = fn(p)
            a, b = min(max(a, 0.0), 1.0), min(max(b, 0.0), 1.0)
            out.append(_px_to_uv(x0 + a * (x1 - x0), y0 + b * (y1 - y0), size))
        return np.array(out)
    return f


def uv_planar(rect, axis_u, axis_v, bounds_u, bounds_v, size=ATLAS):
    au, av = nrm(axis_u), nrm(axis_v)
    return uv_point(rect, lambda p: ((np.dot(p, au) - bounds_u[0]) / (bounds_u[1] - bounds_u[0]),
                                     (np.dot(p, av) - bounds_v[0]) / (bounds_v[1] - bounds_v[0])), size)


# ------------------------------------------------------------------ geometry containers
class Part:
    def __init__(self, smooth=False):
        self.v, self.f, self.uv, self.smooth = [], [], [], smooth

    def add(self, p):
        self.v.append(np.asarray(p, float))
        return len(self.v) - 1

    def tri(self, i, j, k, outward, uvfn):
        a, b, c = self.v[i], self.v[j], self.v[k]
        n = np.cross(b - a, c - a)
        if np.linalg.norm(n) < 1e-10:
            return
        if np.dot(n, outward) < 0:
            j, k = k, j
        self.f.append((i, j, k))
        self.uv.append(np.asarray(uvfn(np.array([self.v[i], self.v[j], self.v[k]])), float))


class Mesh:
    def __init__(self, name):
        self.name, self.parts = name, []

    def part(self, smooth=False):
        p = Part(smooth)
        self.parts.append(p)
        return p

    def tris(self):
        return sum(len(p.f) for p in self.parts)

    def all_verts(self):
        return np.array([v for p in self.parts for v in p.v])

    def apply(self, M=None, t=(0, 0, 0), s=1.0):
        M = np.eye(3) if M is None else np.asarray(M)
        for p in self.parts:
            p.v = [M @ (v * s) + np.asarray(t, float) for v in p.v]
        return self

    def finalize(self, target_extent=None, axes=(0, 1, 2)):
        """Optional uniform scale so max extent over `axes` == target, then pivot at base."""
        V = self.all_verts()
        if target_extent:
            ext = (V.max(0) - V.min(0))[list(axes)].max()
            self.apply(s=target_extent / ext)
            V = self.all_verts()
        lo, hi = V.min(0), V.max(0)
        self.apply(t=(-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2))
        return self

    def size(self):
        V = self.all_verts()
        return (V.max(0) - V.min(0)).tolist()

    def signed_volumes(self):
        out = []
        for p in self.parts:
            vol = 0.0
            for (i, j, k) in p.f:
                vol += np.dot(p.v[i], np.cross(p.v[j], p.v[k])) / 6
            out.append(vol)
        return out

    def arrays(self):
        """(F,3,3) positions, (F,3,3) normals, (F,3,2) uvs for rendering/export."""
        P, N, U = [], [], []
        for p in self.parts:
            if not p.f:
                continue
            V = np.array(p.v)
            F = np.array(p.f)
            fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
            if p.smooth:
                vn = np.zeros_like(V)
                for c in range(3):
                    np.add.at(vn, F[:, c], fn)
                vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
                N.append(vn[F])
            else:
                fnn = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
                N.append(np.repeat(fnn[:, None, :], 3, axis=1))
            P.append(V[F])
            U.append(np.array(p.uv))
        return np.concatenate(P), np.concatenate(N), np.concatenate(U)

    def write_obj(self, path, comment=""):
        P, N, U = self.arrays()
        vi, ti, ni = {}, {}, {}
        vl, tl, nl, fl = [], [], [], []

        def idx(table, lst, key):
            if key not in table:
                table[key] = len(lst) + 1
                lst.append(key)
            return table[key]
        for f in range(len(P)):
            corner = []
            for c in range(3):
                a = idx(vi, vl, tuple(np.round(P[f, c], 4)))
                b = idx(ti, tl, tuple(np.round(U[f, c], 5)))
                n = idx(ni, nl, tuple(np.round(N[f, c], 3)))
                corner.append(f"{a}/{b}/{n}")
            fl.append("f " + " ".join(corner))
        with open(path, "w") as fh:
            fh.write(f"# Steal a Fish item mesh: {self.name}\n# {comment}\n# triangles: {len(P)} | units: studs "
                     f"(1 stud = 0.28 m) | Y-up | front -Z | pivot at base\n")
            fh.write(f"o {self.name}\n")
            fh.writelines(f"v {x:.4f} {y:.4f} {z:.4f}\n" for x, y, z in vl)
            fh.writelines(f"vt {u:.5f} {v:.5f}\n" for u, v in tl)
            fh.writelines(f"vn {x:.3f} {y:.3f} {z:.3f}\n" for x, y, z in nl)
            fh.write("s off\n")
            fh.write("\n".join(fl) + "\n")
        return len(P)


# ------------------------------------------------------------------ primitives
def _ring_basis(axis):
    axis = nrm(axis)
    ref = np.array([0, 1, 0]) if abs(axis[1]) < 0.9 else np.array([1, 0, 0])
    a = nrm(np.cross(axis, ref))
    return a, np.cross(axis, a)


def loft(part, rings, uvfn, start_tip=None, end_tip=None, cap_start=True, cap_end=True, flip=False):
    """Rings: list of (M,3) arrays with equal M. Faces orient away from each ring's centroid (star-shaped).
    flip=True orients faces inward (inner wall of an open bag)."""
    sg = -1.0 if flip else 1.0
    R = [np.asarray(r, float) for r in rings]
    M = len(R[0])
    C = [r.mean(0) for r in R]
    ids = [[part.add(p) for p in r] for r in R]
    for i in range(len(R) - 1):
        ref = (C[i] + C[i + 1]) / 2
        for j in range(M):
            a, b, c, d = ids[i][j], ids[i][(j + 1) % M], ids[i + 1][(j + 1) % M], ids[i + 1][j]
            for tri in ((a, b, c), (a, c, d)):
                cen = sum(part.v[t] for t in tri) / 3
                part.tri(*tri, sg * (cen - ref), uvfn)
    for tip, ring, cen, other, cap in ((start_tip, 0, C[0], C[min(1, len(C) - 1)], cap_start),
                                       (end_tip, -1, C[-1], C[max(len(C) - 2, 0)], cap_end)):
        if tip is not None:
            t = part.add(tip)
            for j in range(M):
                a, b = ids[ring][j], ids[ring][(j + 1) % M]
                cen3 = (part.v[a] + part.v[b] + part.v[t]) / 3
                part.tri(t, a, b, sg * (cen3 - cen + (np.asarray(tip) - cen) * 0.5), uvfn)
        elif cap:
            out = nrm(cen - other) if np.linalg.norm(cen - other) > 1e-9 else np.array([0, 1, 0])
            t = part.add(cen)
            for j in range(M):
                part.tri(t, ids[ring][j], ids[ring][(j + 1) % M], sg * out, uvfn)
    return part


def lathe(part, profile, segs, uvfn, center=(0, 0, 0), phase=0.0, scale_xz=(1.0, 1.0)):
    """Revolve (r, y) profile around +Y. Walk the profile CCW around the solid's cross-section
    (r to the right, y up) so the right-hand side of each segment is outside."""
    cx, cy, cz = center
    th = [phase + 2 * math.pi * j / segs for j in range(segs)]
    ids = []
    for r, y in profile:
        ids.append([part.add((cx + r * math.cos(t) * scale_xz[0], cy + y, cz + r * math.sin(t) * scale_xz[1]))
                    for t in th])
    for k in range(len(profile) - 1):
        (r0, y0), (r1, y1) = profile[k], profile[k + 1]
        nr, ny = (y1 - y0), -(r1 - r0)
        for j in range(segs):
            tm = phase + 2 * math.pi * (j + .5) / segs
            out = np.array([nr * math.cos(tm), ny, nr * math.sin(tm)])
            a, b, c, d = ids[k][j], ids[k][(j + 1) % segs], ids[k + 1][(j + 1) % segs], ids[k + 1][j]
            part.tri(a, b, c, out, uvfn)
            part.tri(a, c, d, out, uvfn)
    return part


def convex(part, pts, faces, uvfn):
    """Convex solid from points + polygon faces (index lists); orientation from the centroid."""
    ids = [part.add(p) for p in pts]
    cen = np.mean(np.asarray(pts, float), axis=0)
    for poly in faces:
        for k in range(1, len(poly) - 1):
            tri = (ids[poly[0]], ids[poly[k]], ids[poly[k + 1]])
            fc = sum(part.v[t] for t in tri) / 3
            part.tri(*tri, fc - cen, uvfn)
    return part


def box(part, center, size, uvfn, M=None):
    cx, cy, cz = center
    sx, sy, sz = [s / 2 for s in size]
    M = np.eye(3) if M is None else M
    pts = [np.asarray(center) + M @ np.array([x, y, z]) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    faces = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
    return convex(part, pts, faces, uvfn)


def frustum(part, p0, p1, r0, r1, segs, uvfn, phase=0.0):
    """Cylinder / cone between two points (convex). r1 = 0 makes a cone."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    a, b = _ring_basis(p1 - p0)
    ring = lambda c, r: [c + r * (math.cos(phase + 2 * math.pi * j / segs) * a +  # noqa: E731
                                  math.sin(phase + 2 * math.pi * j / segs) * b) for j in range(segs)]
    if r1 <= 1e-6:
        pts = ring(p0, r0) + [p1]
        faces = [list(range(segs))] + [(j, (j + 1) % segs, segs) for j in range(segs)]
    else:
        pts = ring(p0, r0) + ring(p1, r1)
        faces = [list(range(segs)), list(range(segs, 2 * segs))] + \
                [(j, (j + 1) % segs, segs + (j + 1) % segs, segs + j) for j in range(segs)]
    return convex(part, pts, faces, uvfn)


def tube(part, path, radius, segs, uvfn, closed=False, caps=True):
    """Sweep a circle along a polyline (parallel-transport frames). radius: float or per-point list."""
    P = [np.asarray(p, float) for p in path]
    n = len(P)
    rad = radius if isinstance(radius, (list, tuple, np.ndarray)) else [radius] * n
    T = []
    for i in range(n):
        if closed:
            T.append(nrm(P[(i + 1) % n] - P[i - 1]))
        else:
            T.append(nrm(P[min(i + 1, n - 1)] - P[max(i - 1, 0)]))
    a, _ = _ring_basis(T[0])
    frames = []
    for i in range(n):
        a = nrm(a - np.dot(a, T[i]) * T[i])
        frames.append((a, np.cross(T[i], a)))
    rings = [[P[i] + rad[i] * (math.cos(2 * math.pi * j / segs) * frames[i][0] +
                               math.sin(2 * math.pi * j / segs) * frames[i][1]) for j in range(segs)]
             for i in range(n)]
    ids = [[part.add(p) for p in r] for r in rings]
    last = n if closed else n - 1
    for i in range(last):
        i2 = (i + 1) % n
        for j in range(segs):
            q = (ids[i][j], ids[i][(j + 1) % segs], ids[i2][(j + 1) % segs], ids[i2][j])
            for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                cen = sum(part.v[t] for t in tri) / 3
                d = P[i2] - P[i]
                tpar = np.clip(np.dot(cen - P[i], d) / max(np.dot(d, d), 1e-12), 0, 1)
                part.tri(*tri, cen - (P[i] + tpar * d), uvfn)
    if not closed and caps:
        for i, out in ((0, -T[0]), (n - 1, T[-1])):
            if rad[i] < 1e-6:
                continue
            c = part.add(P[i])
            for j in range(segs):
                part.tri(c, ids[i][j], ids[i][(j + 1) % segs], out, uvfn)
    return part


def _tri2d(pts):
    """Ear clipping. pts: (n,2). Returns index triples."""
    n = len(pts)
    idx = list(range(n))
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    if area < 0:
        idx.reverse()
    out = []
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])  # noqa: E731
    guard = 0
    while len(idx) > 3 and guard < 500:
        guard += 1
        for k in range(len(idx)):
            a, b, c = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            if cross(pts[a], pts[b], pts[c]) <= 1e-12:
                continue
            if any(cross(pts[a], pts[b], pts[p]) > 0 and cross(pts[b], pts[c], pts[p]) > 0 and
                   cross(pts[c], pts[a], pts[p]) > 0 for p in idx if p not in (a, b, c)):
                continue
            out.append((a, b, c))
            idx.pop(k)
            break
        else:
            out.append((idx[-1], idx[0], idx[1]))
            idx.pop(0)
    out.append(tuple(idx))
    return out


def slab(part, poly, thickness, uvfn):
    """Thicken a planar 3D polygon (fins, sails, plates). Works for concave outlines."""
    P = np.asarray(poly, float)
    n = len(P)
    N = np.zeros(3)
    for i in range(n):  # Newell normal follows the vertex order
        a, b = P[i], P[(i + 1) % n]
        N += np.array([(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])])
    N = nrm(N)
    c = P.mean(0)
    e1 = nrm(P[1] - P[0] - np.dot(P[1] - P[0], N) * N)
    e2 = np.cross(N, e1)
    p2 = [(np.dot(p - c, e1), np.dot(p - c, e2)) for p in P]
    h = thickness / 2
    F = [part.add(p + N * h) for p in P]
    B = [part.add(p - N * h) for p in P]
    for (a, b, cc) in _tri2d(p2):
        part.tri(F[a], F[b], F[cc], N, uvfn)
        part.tri(B[a], B[b], B[cc], -N, uvfn)
    for i in range(n):
        j = (i + 1) % n
        out = np.cross(P[j] - P[i], N)
        part.tri(F[i], F[j], B[j], out, uvfn)
        part.tri(F[i], B[j], B[i], out, uvfn)
    return part


# ------------------------------------------------------------------ reporting
def save(mesh, out_dir, comment, report):
    os.makedirs(out_dir, exist_ok=True)
    vols = mesh.signed_volumes()
    bad = [i for i, v in enumerate(vols) if v < -1e-9]
    n = mesh.write_obj(os.path.join(out_dir, mesh.name + ".obj"), comment)
    report[mesh.name] = dict(tris=n, size=[round(s, 3) for s in mesh.size()], invertedParts=bad)
    assert n <= 5000, f"{mesh.name} has {n} triangles"
    return n


def merge_report(path, new):
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(new)
    with open(path, "w") as fh:
        json.dump(dict(sorted(old.items())), fh, indent=1)


# ------------------------------------------------------------------ OBJ loading (icons render the exported files)
class ObjMesh:
    def __init__(self, path):
        v, vt, vn, self.f = [], [], [], []
        for ln in open(path):
            t = ln.split()
            if not t:
                continue
            if t[0] == "v":
                v.append([float(x) for x in t[1:4]])
            elif t[0] == "vt":
                vt.append([float(x) for x in t[1:3]])
            elif t[0] == "vn":
                vn.append([float(x) for x in t[1:4]])
            elif t[0] == "f":
                self.f.append([[int(i) - 1 for i in c.split("/")] for c in t[1:4]])
        F = np.array(self.f)
        self._a = (np.array(v)[F[..., 0]], np.array(vn)[F[..., 2]], np.array(vt)[F[..., 1]])

    def arrays(self):
        return self._a


# ------------------------------------------------------------------ rasterizer (icons / previews)
def render(mesh, tex, size=512, yaw=-35.0, pitch=18.0, fit=0.8, light=(-0.45, 0.75, 0.6), extra_rot=None):
    """Returns float RGB (size,size,3) 0..1 and alpha (size,size). Back faces are culled like Roblox."""
    P, N, U = mesh.arrays()
    R = rot_x(math.radians(pitch)) @ rot_y(math.radians(yaw))
    if extra_rot is not None:
        R = R @ extra_rot
    P = P @ R.T
    N = N @ R.T
    xy = P[..., :2]
    lo, hi = xy.reshape(-1, 2).min(0), xy.reshape(-1, 2).max(0)
    s = fit * size / max(hi - lo)
    off = np.array([size / 2, size / 2]) - s * (lo + hi) / 2 * np.array([1, -1])
    sx = P[..., 0] * s + off[0]
    sy = -P[..., 1] * s + off[1]
    z = P[..., 2]
    img = np.zeros((size, size, 3))
    zb = np.full((size, size), -1e9)
    L = nrm(light)
    th, tw = tex.shape[:2]
    for f in range(len(P)):
        x0, y0, x1, y1, x2, y2 = sx[f, 0], sy[f, 0], sx[f, 1], sy[f, 1], sx[f, 2], sy[f, 2]
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if area >= -1e-9:  # screen y points down, so front faces have negative area
            continue
        bx0, bx1 = int(max(min(x0, x1, x2), 0)), int(min(max(x0, x1, x2) + 1, size))
        by0, by1 = int(max(min(y0, y1, y2), 0)), int(min(max(y0, y1, y2) + 1, size))
        if bx0 >= bx1 or by0 >= by1:
            continue
        gy, gx = np.mgrid[by0:by1, bx0:bx1] + 0.5
        w0 = ((x1 - gx) * (y2 - gy) - (x2 - gx) * (y1 - gy)) / area
        w1 = ((x2 - gx) * (y0 - gy) - (x0 - gx) * (y2 - gy)) / area
        w2 = 1 - w0 - w1
        m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not m.any():
            continue
        zz = w0 * z[f, 0] + w1 * z[f, 1] + w2 * z[f, 2]
        sub = zb[by0:by1, bx0:bx1]
        m &= zz > sub
        if not m.any():
            continue
        nn = w0[..., None] * N[f, 0] + w1[..., None] * N[f, 1] + w2[..., None] * N[f, 2]
        nn /= np.maximum(np.linalg.norm(nn, axis=-1, keepdims=True), 1e-9)
        uu = w0 * U[f, 0, 0] + w1 * U[f, 1, 0] + w2 * U[f, 2, 0]
        vv = w0 * U[f, 0, 1] + w1 * U[f, 1, 1] + w2 * U[f, 2, 1]
        tx = np.clip((uu * tw).astype(int), 0, tw - 1)
        ty = np.clip(((1 - vv) * th).astype(int), 0, th - 1)
        col = tex[ty, tx]
        dif = np.clip(nn @ L, 0, 1)
        shade = 0.5 + 0.62 * dif + 0.12 * nn[..., 1] + 0.18 * np.clip(1 - nn[..., 2], 0, 1) ** 3
        c = np.clip(col * shade[..., None], 0, 1)
        sub[m] = zz[m]
        reg = img[by0:by1, bx0:bx1]
        reg[m] = c[m]
    alpha = (zb > -1e9).astype(float)
    return img, alpha
