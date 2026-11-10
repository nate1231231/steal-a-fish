"""Phase 3: nets/rods, tanks, locks, boosts, bangka skins, hats + props_atlas.png.

python tools/items/gen_props.py
Atlas: rows 0-511 = 32 px flat color swatches; rows 512-1023 = 128 px pattern tiles.
Recolor variants (net tiers, bangka skins) reuse the same builder and only change swatches.
"""
import math
import os

import numpy as np
from PIL import Image

import item_data as D
from meshlib import (Mesh, _ring_basis, box, convex, frustum, lathe, loft, merge_report, nrm, render, rot_y, save,
                     slab, tube, uv_planar, uv_point, uv_swatch)

OUT = os.path.join(D.ROOT, "items", "models")
TEX = os.path.join(D.ROOT, "items", "textures")
rng = np.random.default_rng(7)

# ------------------------------------------------------------------ atlas
PALETTE = dict(
    wood=(150, 100, 60), wood_dark=(100, 65, 40), bamboo=(205, 190, 110), bamboo_dark=(150, 140, 70),
    rubber=(40, 40, 45), cork=(190, 150, 100), steel=(170, 175, 185), steel_dark=(80, 85, 95),
    chrome=(220, 225, 232), gold=(242, 190, 50), gold_dark=(190, 135, 30), brass=(205, 160, 70),
    crystal=(150, 230, 255), crystal_dark=(80, 170, 230), white=(245, 245, 245), red=(220, 40, 40),
    red_dark=(150, 25, 30), orange=(250, 140, 40), yellow=(250, 210, 40), green=(60, 170, 80),
    green_dark=(30, 110, 60), teal=(30, 180, 170), blue=(40, 110, 220), navy=(30, 45, 90), purple=(140, 70, 200),
    pink=(250, 130, 170), black=(25, 25, 30), sand=(230, 210, 160), stone=(140, 140, 135),
    stone_dark=(95, 95, 92), plastic_blue=(40, 140, 230), plastic_red=(225, 60, 50), glass=(175, 225, 240),
    liquid_green=(60, 210, 90), liquid_purple=(170, 80, 230), laser=(255, 45, 45), marble=(235, 235, 230),
    khaki=(190, 170, 120), straw=(225, 200, 130), knit_red=(200, 50, 50), knit_cream=(240, 230, 210),
    fiber_yellow=(245, 215, 60), coral_pink=(255, 110, 140), coral_orange=(255, 150, 60), seaweed=(50, 160, 90),
    silver=(200, 205, 212), lily=(70, 160, 70), lotus=(255, 170, 200), skin_tan=(225, 180, 140),
)
for s in D.BANGKA_SKINS:
    for part, c in s["colors"].items():
        PALETTE[f"{s['id']}_{part}"] = tuple(c)


def _noise(seed, blur=3):
    r = np.random.default_rng(seed).random((128, 128))
    for _ in range(blur):
        r = (r + np.roll(r, 1, 0) + np.roll(r, 1, 1) + np.roll(r, -1, 0) + np.roll(r, -1, 1)) / 5
    return (r - r.min()) / (np.ptp(r) + 1e-9)


def c3(rgb):
    return np.array(rgb, float) / 255


Y, X = np.mgrid[0:128, 0:128] / 128.0


def fill(rgb):
    return np.ones((128, 128, 3)) * c3(rgb)


def p_net(cord, bg):
    img = fill(bg)
    px, py = X * 128, Y * 128
    m = ((px + py) % 16 < 2.6) | ((px - py) % 16 < 2.6)
    img[m] = c3(cord)
    return img


def p_planks(a, b):
    row = np.floor(Y * 4)
    img = fill(a) * (0.9 + 0.1 * ((row % 2)[..., None])) + 0.06 * np.sin(X * 50 + _noise(1) * 6)[..., None]
    img[(Y * 4) % 1 < .05] = c3(b)
    return img


def p_bamboo():
    img = fill(PALETTE["bamboo"]) * (0.92 + 0.08 * np.sin(X * 40)[..., None])
    img[(Y * 3) % 1 < .05] = c3(PALETTE["bamboo_dark"])
    return img


def p_water():
    img = fill((55, 145, 210)) * (0.85 + 0.25 * _noise(2)[..., None])
    hl = np.sin(X * 25 + np.sin(Y * 13) * 2) * np.sin(Y * 21 + X * 5) > .6
    img[hl] = c3((150, 215, 245))
    return img


def p_ocean():
    g = Y[..., None]
    img = c3((70, 170, 225)) * (1 - g) + c3((15, 55, 115)) * g
    for k in range(9):
        x0 = rng.uniform(0, 1)
        m = (np.abs(X - x0 - .03 * np.sin(Y * 18 + k)) < .018) & (Y > rng.uniform(.45, .7))
        img[m] = c3(PALETTE["seaweed"]) * rng.uniform(.8, 1.1)
    for _ in range(14):
        cx, cy, r = rng.uniform(0, 1), rng.uniform(0, .8), rng.uniform(.01, .025)
        d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
        img[(d < r) & (d > r * .6)] = c3((200, 235, 250))
    return img


def p_coral():
    g = Y[..., None]
    img = c3((40, 190, 200)) * (1 - g) + c3((20, 80, 150)) * g
    for _ in range(40):
        cx, cy, r = rng.uniform(0, 1), rng.uniform(.35, 1), rng.uniform(.03, .08)
        col = [PALETTE["coral_pink"], PALETTE["coral_orange"], PALETTE["purple"], PALETTE["yellow"]][rng.integers(4)]
        img[(X - cx) ** 2 + ((Y - cy) * 1.4) ** 2 < r * r] = c3(col)
    return img


def p_speckle(base, amt=.12, seed=3):
    img = fill(base) * (1 - amt + 2 * amt * np.random.default_rng(seed).random((128, 128)))[..., None]
    return img


def p_stone():
    pts = rng.random((22, 2))
    d = np.stack([np.sqrt((X - p[0]) ** 2 + (Y - p[1]) ** 2) for p in pts])
    s = np.sort(d, 0)
    idx = np.argmin(d, 0)
    shade = (0.8 + 0.3 * (idx % 5) / 4)[..., None]
    img = fill(PALETTE["stone"]) * shade
    img[(s[1] - s[0]) < .015] = c3(PALETTE["stone_dark"]) * .8
    return img


def p_weave(base):
    cell = (np.floor(X * 12) + np.floor(Y * 12)) % 2
    fx, fy = (X * 12) % 1, (Y * 12) % 1
    shade = np.where(cell == 0, .85 + .25 * np.sin(fx * np.pi), .85 + .25 * np.sin(fy * np.pi))
    return fill(base) * shade[..., None]


def p_knit(base):
    v = np.abs(((X * 16) % 1) - .5) * 2
    row = (Y * 16 + v * .5) % 1
    return fill(base) * (0.8 + 0.25 * np.sin(row * np.pi))[..., None]


def p_gold():
    img = fill(PALETTE["gold"]) * (0.85 + 0.25 * _noise(4)[..., None])
    img[np.random.default_rng(5).random((128, 128)) > .992] = 1.0
    return img


def p_metal(base):
    st = np.random.default_rng(6).random(128)
    return fill(base) * (0.9 + 0.12 * st[None, :, None].transpose(1, 0, 2))


def p_marble():
    img = fill(PALETTE["marble"])
    vein = np.abs(np.sin(X * 8 + Y * 3 + _noise(8) * 6)) < .06
    img[vein] = c3((170, 170, 175))
    return img


PATTERNS = dict(
    net_rope=p_net((215, 185, 130), (95, 70, 45)), net_green=p_net((90, 210, 110), (25, 70, 40)),
    net_blue=p_net((110, 180, 255), (25, 45, 95)), net_crystal=p_net((210, 250, 255), (60, 130, 190)),
    net_gold=p_net((255, 220, 90), (130, 85, 20)), planks=p_planks(PALETTE["wood"], PALETTE["wood_dark"]),
    bamboo=p_bamboo(), water=p_water(), ocean=p_ocean(), coral=p_coral(), sand=p_speckle(PALETTE["sand"]),
    stone=p_stone(), weave=p_weave(PALETTE["straw"]), weave_khaki=p_weave(PALETTE["khaki"]),
    knit_red=p_knit(PALETTE["knit_red"]), knit_cream=p_knit(PALETTE["knit_cream"]), gold=p_gold(),
    metal=p_metal(PALETTE["steel"]), marble=p_marble(),
)


class Atlas:
    def __init__(self):
        self.img = np.zeros((1024, 1024, 3))
        self.sw, self.pt = {}, {}
        for name, rgb in PALETTE.items():
            i = len(self.sw)
            x0, y0 = (i % 32) * 32, (i // 32) * 32
            self.img[y0:y0 + 32, x0:x0 + 32] = c3(rgb)
            self.sw[name] = (x0, y0, x0 + 32, y0 + 32)
        for name, arr in PATTERNS.items():
            i = len(self.pt)
            x0, y0 = (i % 8) * 128, 512 + (i // 8) * 128
            self.img[y0:y0 + 128, x0:x0 + 128] = np.clip(arr, 0, 1)
            self.pt[name] = (x0 + 6, y0 + 6, x0 + 122, y0 + 122)


A = Atlas()


def S(name):
    return uv_swatch(A.sw[name])


def PL(name, axis_u, axis_v, bu, bv):
    return uv_planar(A.pt[name], axis_u, axis_v, bu, bv)


def PT(name, fn):
    return uv_point(A.pt[name], fn)


# ------------------------------------------------------------------ shared builders
def sphere(part, c, r, uv, segs=8, rings=4, sy=1.0):
    prof = [(abs(r * math.cos(a)) if 0 < k < rings else 0.0, r * math.sin(a) * sy)
            for k, a in enumerate(np.linspace(-math.pi / 2, math.pi / 2, rings + 1))]
    return lathe(part, prof, segs, uv, center=c)


def circle(center, axis, R, n=16):
    a, b = _ring_basis(axis)
    return [np.asarray(center, float) + R * (math.cos(2 * math.pi * k / n) * a + math.sin(2 * math.pi * k / n) * b)
            for k in range(n)]


def ring(m, center, axis, R, r, uv, n=16, segs=6):
    tube(m.part(), circle(center, axis, R, n), r, segs, uv, closed=True)


def merge(dst, src, M=None, t=(0, 0, 0), s=1.0):
    src.apply(M, t, s)
    dst.parts.extend(src.parts)


NET_STYLE = {
    "net_basic": dict(frame="wood", handle="wood", grip="rubber", net="net_rope", R=1.0, L=3.4),
    "net_pukot": dict(frame="green_dark", handle="bamboo", grip="rubber", net="net_green", R=1.1, L=3.6),
    "net_sapyaw": dict(frame="blue", handle="steel", grip="navy", net="net_blue", R=1.25, L=3.8),
    "net_diamond": dict(frame="crystal_dark", handle="chrome", grip="purple", net="net_crystal", R=1.35, L=4.0,
                        gems="crystal"),
    "net_golden_trawl": dict(frame="gold", handle="gold_dark", grip="red_dark", net="net_gold", R=1.6, L=4.0,
                             floats=True, gems="red"),
    "net_bamboo_rod": dict(rod="bamboo", grip="cork", reel=None, nodes=True),
    "net_fiberglass_rod": dict(rod="fiber_yellow", grip="navy", reel="steel", reel2="steel_dark"),
    "net_steel_reel": dict(rod="steel_dark", grip="red_dark", reel="chrome", reel2="red", big=True),
}


def hand_net(m, st):
    R, L = st["R"], st["L"]
    frustum(m.part(), (0, 0, 0), (0, L, 0), .13, .1, 6, S(st["handle"]))
    frustum(m.part(), (0, .02, 0), (0, 1.0, 0), .165, .155, 6, S(st["grip"]))
    cy = L + R
    ring(m, (0, cy, 0), (0, 0, 1), R, .075 * (1.3 if st.get("floats") else 1), S(st["frame"]), n=16, segs=6)
    bl = 2.0 * R
    zs, rs, dr = [0, .3, .55, .78, .92], [.95, .88, .72, .5, .28], [0, -.1, -.28, -.48, -.62]
    rings = [[(r * R * math.cos(2 * math.pi * j / 12), cy + r * R * math.sin(2 * math.pi * j / 12) + d * R, z * bl)
              for j in range(12)] for z, r, d in zip(zs, rs, dr)]
    uv = PT(st["net"], lambda p: (abs(math.atan2(p[1] - cy, p[0])) / math.pi, p[2] / bl))
    tip = (0, cy - .78 * R, 1.02 * bl)
    loft(m.part(), rings, uv, end_tip=tip, cap_start=False)
    inner = [[(x * .96, cy + (y - cy) * .96, z) for x, y, z in r] for r in rings]
    loft(m.part(), inner, uv, end_tip=(0, tip[1] + .03, tip[2] - .03), cap_start=False, flip=True)
    if st.get("floats"):
        for k in range(8):
            a = 2 * math.pi * (k + .5) / 8
            sphere(m.part(), (R * 1.08 * math.cos(a), cy + R * 1.08 * math.sin(a), 0), .17,
                   S("red" if k % 2 else "white"), segs=6, rings=4)
    if st.get("gems"):
        frustum(m.part(), (0, cy + R + .05, 0), (0, cy + R + .45, 0), .16, 0, 4, S(st["gems"]))
        frustum(m.part(), (0, cy + R + .05, 0), (0, cy + R - .15, 0), .16, 0, 4, S(st["gems"]))


def rod(m, st):
    big = 1.3 if st.get("big") else 1.0
    base, tip = np.zeros(3), np.array([0, 6.2, -2.4])
    d = nrm(tip)
    frustum(m.part(), base, tip, .11 * big, .035, 6, S(st["rod"]))
    frustum(m.part(), base, d * 1.4, .17 * big, .15 * big, 6, S(st["grip"]))
    frustum(m.part(), d * 1.4, d * 1.5, .19 * big, .12, 6, S("steel_dark"))
    if st.get("nodes"):
        for t in (2.2, 3.4, 4.5, 5.5):
            p = d * t
            ring(m, p, d, .085 - .008 * t, .028, S("bamboo_dark"), n=8, segs=4)
        sp = d * 1.75 + np.array([0, -.05, .22])
        frustum(m.part(), sp + [-.12, 0, 0], sp + [.12, 0, 0], .2, .2, 8, S("wood_dark"))
    else:
        rp = d * 1.75 + np.array([0, -.08, .38 * big])
        box(m.part(), (d * 1.75 + rp) / 2, (.1, .1, .4 * big), S(st["reel2"]))
        frustum(m.part(), rp + [-.2 * big, 0, 0], rp + [.2 * big, 0, 0], .32 * big, .32 * big, 10, S(st["reel"]))
        frustum(m.part(), rp + [-.22 * big, 0, 0], rp + [-.2 * big, 0, 0], .36 * big, .36 * big, 10, S(st["reel2"]))
        box(m.part(), rp + [.3 * big, .2, 0], (.16, .45, .1), S(st["reel2"]))
        frustum(m.part(), rp + [.3 * big, .4, 0], rp + [.5 * big, .4, 0], .07, .07, 5, S("black"))
        for t in (3.0, 4.3, 5.6):
            ring(m, d * t + np.array([0, -.12, .05]), np.array([0, .4, 1]), .07, .02, S("chrome"), n=8, segs=4)
    bob = tip + np.array([0, -2.3, 0])
    tube(m.part(), [tip, bob + [0, .2, 0]], .018, 3, S("white"))
    lathe(m.part(), [(0, -.22), (.16, -.16), (.22, 0)], 8, S("white"), center=bob)
    lathe(m.part(), [(.22, 0), (.16, .16), (0, .22)], 8, S("red"), center=bob)
    tube(m.part(), [bob - [0, .2, 0], bob - [0, .55, 0], bob - [0, .62, .12], bob - [0, .5, .18]], .025, 4,
         S("steel"))


# ------------------------------------------------------------------ tanks
def tank_frame(m, W, Dp, Hc, Ht, frame, back, glass_side=True, cabinet="planks"):
    box(m.part(), (0, Hc / 2, 0), (W + .2, Hc, Dp + .2),
        PL(cabinet, (1, 0, 0), (0, -1, 0), (-W / 2, W / 2), (-Hc, 0)) if cabinet == "planks" else S(cabinet))
    y0 = Hc
    box(m.part(), (0, y0 + .15, 0), (W - .2, .3, Dp - .2), PL("sand", (1, 0, 0), (0, 0, 1), (-W / 2, W / 2), (-Dp / 2, Dp / 2)))
    box(m.part(), (0, y0 + Ht / 2, Dp / 2 - .15), (W - .2, Ht, .2),
        PL(back, (1, 0, 0), (0, -1, 0), (-W / 2, W / 2), (-(y0 + Ht), -y0)))
    if glass_side:
        for s in (-1, 1):
            box(m.part(), (s * (W / 2 - .12), y0 + Ht / 2, 0), (.12, Ht, Dp - .2), S("glass"))
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(m.part(), (sx * W / 2, y0 + Ht / 2 + .1, sz * Dp / 2), (.3, Ht + .3, .3), S(frame))
        box(m.part(), (sx * W / 2, y0 + Ht + .2, 0), (.3, .3, Dp + .3), S(frame))
    for sz in (-1, 1):
        box(m.part(), (0, y0 + Ht + .2, sz * Dp / 2), (W + .3, .3, .3), S(frame))
    box(m.part(), (0, y0 + .2, -Dp / 2), (W + .3, .4, .3), S(frame))


def seaweed(m, x, z, y0, h, k=0):
    pts = []
    for i in range(6):
        t = i / 5
        pts.append((x + .25 * math.sin(t * 5 + k) - .12 * (1 - t), y0 + t * h, z))
    for i in range(5, -1, -1):
        t = i / 5
        pts.append((x + .25 * math.sin(t * 5 + k) + .12 * (1 - t) + .02, y0 + t * h, z))
    pts[5] = (pts[5][0] - .03, pts[5][1], z)
    slab(m.part(), pts[:6] + pts[7:], .05, S("seaweed"))


def build_tank(t):
    m = Mesh(t["id"])
    if t["id"] == "tank_balde":
        lathe(m.part(smooth=True), [(0, 0), (.95, 0), (1.2, 2.4), (1.32, 2.45), (1.32, 2.56), (1.16, 2.56),
                                    (1.06, 2.2), (1.02, 2.0)], 16, S("plastic_blue"))
        lathe(m.part(), [(1.02, 2.0), (0, 2.0)], 16, PL("water", (1, 0, 0), (0, 0, 1), (-1, 1), (-1, 1)))
        path = [(1.3 * math.cos(a), 2.5 + 1.1 * math.sin(a), 0) for a in np.linspace(0, math.pi, 10)]
        tube(m.part(), path, .05, 5, S("steel"))
        box(m.part(), (0, 3.6, 0), (.6, .14, .14), S("black"))
    elif t["id"] == "tank_banyera":
        lathe(m.part(smooth=True), [(0, 0), (2.2, 0), (2.6, 1.4), (2.75, 1.5), (2.75, 1.62), (2.55, 1.62),
                                    (2.45, 1.3), (2.4, 1.2)], 18, S("plastic_red"), scale_xz=(1.5, 1.0))
        lathe(m.part(), [(2.4, 1.2), (0, 1.2)], 18, PL("water", (1, 0, 0), (0, 0, 1), (-3.6, 3.6), (-2.4, 2.4)),
              scale_xz=(1.5, 1.0))
        for s in (-1, 1):
            box(m.part(), (s * 4.25, 1.45, 0), (.35, .2, 1.4), S("plastic_red"))
    elif t["id"] == "tank_aquarium":
        tank_frame(m, 8, 4, 2.0, 4.2, "black", "ocean")
        seaweed(m, -2.6, 1.2, 2.3, 2.6)
        seaweed(m, -2.1, 1.0, 2.3, 1.8, 2)
        seaweed(m, 2.8, 1.1, 2.3, 2.2, 1)
        frustum(m.part(), (1.6, 2.3, .8), (1.7, 3.0, .9), .7, .25, 5, S("stone"))
    elif t["id"] == "tank_coral_reef":
        tank_frame(m, 10, 5, 2.2, 5.0, "teal", "coral", cabinet="navy")
        y0 = 2.5
        for k, (x, z) in enumerate([(-3.5, 1.4), (3.2, 1.2), (-1.0, 1.7)]):
            col = ["coral_pink", "coral_orange", "purple"][k]
            base = np.array([x, y0, z])
            tube(m.part(), [base, base + [0, 1.2, 0], base + [-.5, 2.2, 0]], [.2, .16, .08], 5, S(col))
            tube(m.part(), [base + [0, 1.0, 0], base + [.6, 1.8, 0]], [.14, .07], 5, S(col))
            tube(m.part(), [base + [0, .6, 0], base + [-.5, 1.1, -.2]], [.12, .06], 5, S(col))
        sphere(m.part(), (1.6, y0, .9), .8, S("coral_orange"), segs=8, rings=4, sy=.7)
        slab(m.part(), [(.6, y0, 1.9), (-.4, y0 + 1.6, 1.9), (.2, y0 + 2.6, 1.9), (1.4, y0 + 2.4, 1.9), (1.6, y0 + 1.2, 1.9)],
             .06, S("purple"))
        for x in (3.6, 3.9, 3.3):
            frustum(m.part(), (x, y0, -.6 + x - 3.6), (x, y0 + .9 + x - 3.3, -.6 + x - 3.6), .18, .14, 6, S("yellow"))
        star = [((.55 if k % 2 == 0 else .22) * math.cos(math.pi * k / 5), y0 + .05,
                 (.55 if k % 2 == 0 else .22) * math.sin(math.pi * k / 5) - 1.2) for k in range(10)]
        slab(m.part(), [(x - 2.0, y, z) for x, y, z in star], .1, S("orange"))
    elif t["id"] == "tank_palaisdaan":
        lathe(m.part(), [(4.2, 0), (5.0, 0), (5.0, .9), (4.2, .9), (4.2, 0)], 10,
              PL("stone", (1, 0, 0), (0, 0, 1), (-5, 5), (-5, 5)), phase=math.pi / 10)
        lathe(m.part(), [(4.25, .55), (0, .55)], 10, PL("water", (1, 0, 0), (0, 0, 1), (-4.2, 4.2), (-4.2, 4.2)),
              phase=math.pi / 10)
        for k in range(10):
            a = 2 * math.pi * k / 10 + math.pi / 10
            if k in (2, 3):
                continue
            frustum(m.part(), (4.6 * math.cos(a), .9, 4.6 * math.sin(a)), (4.6 * math.cos(a), 2.0 + .3 * (k % 2), 4.6 * math.sin(a)),
                    .16, .14, 6, PT("bamboo", lambda p: (.5, (2.3 - p[1]) / 1.5)))
        for x, z, r in ((-2, 1.5, .7), (1.8, -1.6, .6), (2.4, 2.0, .5)):
            frustum(m.part(), (x, .55, z), (x, .62, z), r, r, 8, S("lily"))
        frustum(m.part(), (-2, .62, 1.5), (-2, 1.0, 1.5), .25, 0, 5, S("lotus"))
    elif t["id"] == "tank_ocean_dome":
        R = 6.5
        lathe(m.part(), [(0, 0), (6.9, 0), (6.9, 1.0), (6.6, 1.3), (0, 1.3)], 20, PL("marble", (1, 0, 0), (0, 0, 1),
                                                                                    (-7, 7), (-7, 7)))
        ring(m, (0, 1.3, 0), (0, 1, 0), 6.6, .14, S("gold"), n=20, segs=5)
        lathe(m.part(), [(6.45, 1.32), (0, 1.32)], 20, PL("sand", (1, 0, 0), (0, 0, 1), (-6.5, 6.5), (-6.5, 6.5)))
        for k in range(7):
            a = math.radians(25 + k * 130 / 6)
            M = rot_y(-a + math.pi / 2)
            box(m.part(), (6.0 * math.cos(a), 1.3 + 2.2, 6.0 * math.sin(a)), (1.75, 4.4, .2),
                PL("ocean", (1, 0, 0), (0, -1, 0), (-7, 7), (-5.7, -1.3)), M)
        for k in range(8):
            ph = 2 * math.pi * k / 8 + math.pi / 8
            path = [(R * math.cos(e) * math.cos(ph), 1.3 + R * math.sin(e), R * math.cos(e) * math.sin(ph))
                    for e in np.linspace(0, math.radians(84), 7)]
            tube(m.part(), path, .13, 5, S("gold"))
        ring(m, (0, 1.3 + R * math.sin(math.radians(42)), 0), (0, 1, 0), R * math.cos(math.radians(42)), .1,
             S("gold"), n=20, segs=4)
        sphere(m.part(), (0, 1.3 + R + .2, 0), .7, S("white"), segs=8, rings=5)
        frustum(m.part(), (0, 1.3 + R - .6, 0), (0, 1.3 + R - .1, 0), .9, .5, 8, S("gold"))
    return m.finalize()


# ------------------------------------------------------------------ locks
def padlock(m, c=(0, 0, 0), s=1.0, body="brass", shackle="steel"):
    c = np.asarray(c, float)
    box(m.part(), c + np.array([0, .65, 0]) * s, np.array([1.6, 1.3, .7]) * s, S(body))
    box(m.part(), c + np.array([0, .65, 0]) * s, np.array([1.4, 1.1, .8]) * s, S(body))
    path = [c + np.array([.42 * math.cos(a), 1.3 + .1 + .5 * max(math.sin(a), 0) + (0 if a in (0, math.pi) else .3), 0]) * s
            for a in np.linspace(0, math.pi, 9)]
    path = [c + np.array([.42, 1.2, 0]) * s] + path + [c + np.array([-.42, 1.2, 0]) * s]
    tube(m.part(), path, .11 * s, 6, S(shackle))
    box(m.part(), c + np.array([0, .75, -.41]) * s, np.array([.2, .2, .04]) * s, S("black"))
    box(m.part(), c + np.array([0, .55, -.41]) * s, np.array([.08, .3, .04]) * s, S("black"))


def build_lock(l):
    m = Mesh(l["id"])
    i = l["id"]
    if i == "lock_padlock":
        padlock(m, s=1.3)
    elif i == "lock_chain_gate":
        for s in (-1, 1):
            box(m.part(), (s * 4.3, 3.0, 0), (.8, 6.0, .8), PL("metal", (0, 1, 0), (0, 0, 1), (0, 6), (-.4, .4)))
            frustum(m.part(), (s * 4.3, 6.0, 0), (s * 4.3, 6.7, 0), .62, 0, 4, S("steel_dark"), phase=math.pi / 4)
        box(m.part(), (0, 5.6, 0), (8.0, .35, .35), S("steel_dark"))
        for y in (1.4, 2.8, 4.2):
            for k in range(10):
                x = -3.55 + k * .79
                pts = [(x + .42 * math.cos(a) * (1 if abs(math.cos(a)) < .99 else 1), .2 * math.sin(a), 0)
                       for a in np.linspace(0, 2 * math.pi, 8, endpoint=False)]
                if k % 2 == 0:
                    pts = [(px, y + py, 0) for px, py, _ in pts]
                else:
                    pts = [(px, y, py) for px, py, _ in pts]
                tube(m.part(), pts, .07, 4, S("steel"), closed=True)
        padlock(m, (0, 1.6, -.45), .55, body="red", shackle="steel")
    elif i == "lock_laser_fence":
        for s in (-1, 1):
            box(m.part(), (s * 5, .15, 0), (1.3, .3, 1.3), S("steel_dark"))
            frustum(m.part(), (s * 5, .3, 0), (s * 5, 6.0, 0), .38, .32, 8, S("steel_dark"))
            sphere(m.part(), (s * 5, 6.0, 0), .42, S("laser"), segs=8, rings=4)
            for y in (1.2, 2.4, 3.6, 4.8):
                box(m.part(), (s * 4.62, y, 0), (.3, .3, .3), S("red_dark"))
        for y in (1.2, 2.4, 3.6, 4.8):
            box(m.part(), (0, y, 0), (9.0, .1, .1), S("laser"))
    elif i == "lock_alarm_bell":
        box(m.part(), (0, .15, 0), (1.4, .3, 1.4), S("red_dark"))
        frustum(m.part(), (0, .3, 0), (0, 4.8, 0), .16, .12, 6, S("steel_dark"))
        box(m.part(), (0, 4.6, -.6), (.16, .16, 1.4), S("steel_dark"))
        sphere(m.part(), (0, 4.95, 0), .25, S("laser"), segs=6, rings=4)
        bc = (0, 3.0, -1.15)
        lathe(m.part(smooth=True), [(0, 0), (.85, 0), (.8, .12), (.62, .55), (.52, 1.05), (.36, 1.3), (0, 1.36)], 12,
              S("gold"), center=bc)
        sphere(m.part(), (0, 2.85, -1.15), .16, S("gold_dark"), segs=6, rings=3)
        ring(m, (0, 4.45, -1.15), (1, 0, 0), .14, .05, S("steel_dark"), n=8, segs=4)
    elif i == "lock_guard_dog_statue":
        box(m.part(), (0, .5, 0), (2.6, 1.0, 3.8), PL("marble", (1, 0, 0), (0, 0, 1), (-1.3, 1.3), (-1.9, 1.9)))
        box(m.part(), (0, 1.1, 0), (2.8, .2, 4.0), S("stone_dark"))
        y0 = 1.2
        G = S("gold")
        rings_ = []
        for z, wx, wy in ((-1.0, .3, .36), (-.55, .4, .45), (0, .38, .42), (.5, .36, .4), (.95, .26, .3)):
            rings_.append([(wx * math.cos(2 * math.pi * j / 8), y0 + 1.45 + wy * math.sin(2 * math.pi * j / 8), z)
                           for j in range(8)])
        loft(m.part(), rings_, G)
        frustum(m.part(), (0, y0 + 1.6, -.8), (0, y0 + 2.25, -1.1), .27, .21, 6, G)
        box(m.part(), (0, y0 + 2.4, -1.2), (.64, .56, .62), G)
        box(m.part(), (0, y0 + 2.25, -1.62), (.38, .3, .45), G)
        box(m.part(), (0, y0 + 2.36, -1.86), (.16, .12, .06), S("black"))
        for s in (-1, 1):
            slab(m.part(), [(s * .2, y0 + 2.66, -1.05), (s * .3, y0 + 2.66, -1.3), (s * .3, y0 + 3.1, -1.15)], .08, G)
            box(m.part(), (s * .17, y0 + 2.5, -1.52), (.09, .09, .04), S("black"))
            for z in (-.62, .62):
                frustum(m.part(), (s * .22, y0 + 1.3, z), (s * .22, y0 + .08, z), .15, .12, 6, G)
                box(m.part(), (s * .22, y0 + .06, z - .06), (.28, .12, .36), G)
        tube(m.part(), [(0, y0 + 1.55, .9), (0, y0 + 1.9, 1.18), (0, y0 + 2.3, 1.12), (0, y0 + 2.5, .9)],
             [.1, .08, .06, .03], 5, G)
        tube(m.part(), circle((0, y0 + 1.95, -.93), (0, .65, -.3), .26, 10), .06, 4, S("red"), closed=True)
    return m.finalize()


# ------------------------------------------------------------------ boosts
def bottle(m, liquid, glass, round_=False):
    if round_:
        lathe(m.part(smooth=True), [(0, 0), (.5, .05), (.82, .45), (.86, .75)], 12, S(liquid))
        lathe(m.part(smooth=True), [(.86, .75), (.75, 1.15), (.4, 1.45), (.24, 1.55), (.24, 2.0), (0, 2.0)], 12,
              S(glass))
    else:
        lathe(m.part(smooth=True), [(0, 0), (.62, 0), (.72, .12), (.75, 1.0)], 12, S(liquid))
        lathe(m.part(smooth=True), [(.75, 1.0), (.72, 1.25), (.32, 1.5), (.26, 1.95), (0, 1.95)], 12, S(glass))
    frustum(m.part(), (0, 1.9, 0), (0, 2.35, 0), .27, .31, 6, S("cork"))


def boot(m, x, s):
    box(m.part(), (x, .08, -.15), (.72, .16, 1.35), S("white"))
    box(m.part(), (x, .4, -.05), (.64, .5, 1.05), S("red"))
    box(m.part(), (x, .33, -.66), (.6, .36, .3), S("red"))
    box(m.part(), (x, 1.0, .22), (.64, .9, .62), S("red"))
    box(m.part(), (x, 1.5, .22), (.72, .16, .72), S("white"))
    xs = x + s * .33
    bolt = [(.05, 1.35), (.3, 1.35), (.12, 1.02), (.32, 1.02), (-.12, .5), (.0, .88), (-.2, .88)]
    slab(m.part(), [(xs, y, z) for z, y in bolt], .03, S("yellow"))
    wing = [(1.15, .4), (1.75, .95), (1.62, .75), (1.7, .55), (1.5, .45), (1.52, .3)]
    slab(m.part(), [(x + s * .36, y, z) for y, z in wing], .03, S("white"))


def build_boost(b):
    m = Mesh(b["id"])
    if b["id"] == "boost_speed_boots":
        boot(m, -.45, -1)
        boot(m, .45, 1)
    elif b["id"] == "boost_cash_potion":
        bottle(m, "liquid_green", "glass")
        box(m.part(), (0, .65, -.72), (.8, .5, .08), S("gold"))
        box(m.part(), (0, .65, -.77), (.12, .36, .04), S("green_dark"))
    elif b["id"] == "boost_luck_potion":
        bottle(m, "liquid_purple", "glass", round_=True)
        for k in range(4):
            a = math.pi / 2 * k + math.pi / 4
            cx, cy = .17 * math.cos(a), .75 + .17 * math.sin(a)
            slab(m.part(), [(cx + .15 * math.cos(t), cy + .15 * math.sin(t), -.88) for t in
                            np.linspace(0, 2 * math.pi, 7, endpoint=False)], .04, S("green"))
    elif b["id"] == "boost_auto_net":
        box(m.part(), (0, .25, 0), (1.7, .5, 1.7), S("steel_dark"))
        for s in (-1, 1):
            box(m.part(), (s * .95, .25, 0), (.25, .45, 1.8), S("black"))
        box(m.part(), (0, 1.05, 0), (1.1, 1.1, 1.1), S("orange"))
        box(m.part(), (0, 1.2, -.56), (.8, .3, .04), S("black"))
        box(m.part(), (0, 1.2, -.59), (.6, .1, .04), S("crystal"))
        frustum(m.part(), (0, 1.6, 0), (0, 2.3, 0), .05, .03, 4, S("steel"))
        sphere(m.part(), (0, 2.35, 0), .1, S("laser"), segs=6, rings=3)
        gear = []
        for k in range(24):
            a = 2 * math.pi * k / 24
            r = .42 if (k // 2) % 2 == 0 else .32
            gear.append((.57, 1.05 + r * math.sin(a), r * math.cos(a)))
        slab(m.part(), gear, .06, S("gold"))
        tube(m.part(), [(-.55, 1.1, 0), (-.9, 1.6, 0), (-.9, 2.1, 0)], .07, 5, S("steel"))
        mini = Mesh("tmp")
        hand_net(mini, dict(frame="orange", handle="steel", grip="black", net="net_green", R=1.0, L=2.0))
        merge(m, mini, rot_y(math.pi), (-.9, 1.85, 0), .32)
    return m.finalize()


# ------------------------------------------------------------------ cosmetics
def build_bangka(sk):
    m = Mesh(sk["id"])
    col = lambda part: S(f"{sk['id']}_{part}")  # noqa: E731
    L, W, h = 16.0, 1.05, 1.1

    def hull_uv(pts):
        n = nrm(np.cross(pts[1] - pts[0], pts[2] - pts[0]))
        yc = pts[:, 1].mean() / h
        if n[1] > .8:
            return col("deck")(pts)
        return col("trim")(pts) if yc > .8 else col("stripe")(pts) if yc > .58 else col("hull")(pts)
    rings = []
    for z in np.linspace(-.9, .9, 11) * L / 2:
        u = z / (L / 2)
        w = W * (1 - u * u) ** .55
        hg = h + .45 * u ** 4
        pts = [(w, hg), (.97 * w, .75 * h), (.88 * w, .5 * h), (.6 * w, .15 * h), (0, 0),
               (-.6 * w, .15 * h), (-.88 * w, .5 * h), (-.97 * w, .75 * h), (-w, hg), (0, hg + .03)]
        rings.append([(x, y, z) for x, y in pts])
    loft(m.part(), rings, hull_uv, start_tip=(0, h * 1.9, -L / 2 * 1.04), end_tip=(0, h * 1.5, L / 2 * 1.0))
    for s in (-1, 1):
        path = [(s * 4.3, .45, z) for z in np.linspace(-6.8, 6.8, 6)]
        tube(m.part(), path, [0, .2, .26, .26, .2, 0], 6, col("outrigger"))
        for z in (-3.2, 3.2):
            xs = np.linspace(0, 4.3, 5)
            pts = [(s * x, .55 + .75 * math.sqrt(max(1 - (x / 4.4) ** 2, 0)) + .05, z) for x in xs]
            tube(m.part(), pts, .11, 5, S("bamboo"))
    frustum(m.part(), (0, .9, -1.2), (0, 6.2, -1.2), .11, .07, 6, S("wood_dark"))
    slab(m.part(), [(0, 1.7, -1.05), (0, 6.0, -1.05), (0, 1.9, 3.2)], .05, col("sail"))
    tube(m.part(), [(0, 1.65, -1.1), (0, 1.75, 3.3)], .06, 5, S("wood_dark"))
    return m.finalize()


def build_hat(hat):
    m = Mesh(hat["id"])
    st = hat["style"]
    if st == "salakot":
        lathe(m.part(), [(0, .12), (1.55, 0), (1.6, .05), (.3, .78), (.12, .82), (.1, .98), (0, 1.0)], 12,
              PL("weave", (1, 0, 0), (0, 0, 1), (-1.6, 1.6), (-1.6, 1.6)))
        ring(m, (0, .04, 0), (0, 1, 0), 1.58, .045, S("wood_dark"), n=12, segs=4)
    elif st == "bucket":
        lathe(m.part(smooth=True), [(0, .3), (.98, .12), (1.02, .16), (.68, .32), (.63, .85), (.55, .96), (0, .98)], 14,
              S("khaki"))
        ring(m, (0, .38, 0), (0, 1, 0), .66, .05, S("green_dark"), n=14, segs=4)
    elif st == "beanie":
        lathe(m.part(), [(0, 0), (.68, 0), (.7, .28), (.66, .3)], 12, PT("knit_cream", lambda p: (
            abs(math.atan2(p[2], p[0])) / math.pi, 1 - p[1] / .3)))
        lathe(m.part(smooth=True), [(.66, .3), (.62, .6), (.42, .86), (0, .95)], 12,
              PT("knit_red", lambda p: (abs(math.atan2(p[2], p[0])) / math.pi, 1 - (p[1] - .3) / .65)))
        sphere(m.part(smooth=True), (0, 1.05, 0), .17, S("knit_cream"), segs=8, rings=4)
    elif st == "buri":
        lathe(m.part(), [(0, .1), (1.5, 0), (1.52, .05), (.7, .12), (.65, .55), (.45, .7), (0, .72)], 14,
              PL("weave", (1, 0, 0), (0, 0, 1), (-1.5, 1.5), (-1.5, 1.5)))
        ring(m, (0, .2, 0), (0, 1, 0), .69, .06, S("red"), n=14, segs=4)
    elif st == "captain":
        lathe(m.part(), [(0, 0), (.62, 0), (.62, .35)], 14, S("navy"))
        lathe(m.part(smooth=True), [(.62, .35), (.78, .5), (.77, .6), (0, .62)], 14, S("white"))
        visor = [(.55 * math.cos(a), .02 + .05 * math.sin(a), -.55 * math.sin(a) - .05) for a in np.linspace(.15, math.pi - .15, 9)]
        slab(m.part(), visor + [(-.4, .06, -.35), (.4, .06, -.35)], .04, S("black"))
        box(m.part(), (0, .25, -.62), (.3, .2, .04), S("gold"))
        ring(m, (0, .37, 0), (0, 1, 0), .63, .03, S("gold"), n=14, segs=4)
    elif st == "bangus":
        lathe(m.part(), [(.62, 0), (.66, 0), (.66, .3), (.62, .3), (.62, 0)], 14, S("navy"))
        H, Lb = .32, 1.9
        rings_ = []
        for t in (.04, .12, .25, .42, .6, .76, .88, .97):
            hh = H * math.sin(math.pi * min(t * 1.1, .97)) ** .7 + .03
            ww = hh * .6
            rings_.append([(ww * math.sin(2 * math.pi * j / 10), .3 + H + hh * math.cos(2 * math.pi * j / 10),
                            -Lb / 2 + t * Lb) for j in range(10)])

        def fish_uv(pts):
            n = nrm(np.cross(pts[1] - pts[0], pts[2] - pts[0]))
            return S("silver")(pts) if n[1] < .2 else S("steel_dark")(pts)
        loft(m.part(smooth=True), rings_, fish_uv, start_tip=(0, .3 + H - .02, -Lb / 2 - .02))
        zt = -Lb / 2 + .97 * Lb
        slab(m.part(), [(0, .3 + H + .05, zt), (0, .3 + H + .5, zt + .45), (0, .3 + H, zt + .25),
                        (0, .3 + H - .45, zt + .45), (0, .3 + H - .05, zt)], .04, S("steel"))
        slab(m.part(), [(0, .3 + 2 * H - .02, -.2), (0, .3 + 2 * H + .3, -.05), (0, .3 + 2 * H - .02, .25)], .04,
             S("steel"))
        for s in (-1, 1):
            box(m.part(), (s * .1, .3 + H + .08, -Lb / 2 + .16), (.04, .1, .1), S("black"))
    return m.finalize()


# ------------------------------------------------------------------ main
def main():
    report, built = {}, []
    for n in D.NETS:
        m = Mesh(n["id"])
        st = NET_STYLE[n["id"]]
        (rod if n["style"] == "rod" else hand_net)(m, st)
        built.append(m.finalize())
    built += [build_tank(t) for t in D.TANKS]
    built += [build_lock(l) for l in D.LOCKS]
    built += [build_boost(b) for b in D.BOOSTS]
    built += [build_bangka(s) for s in D.BANGKA_SKINS]
    built += [build_hat(h) for h in D.HATS]
    for m in built:
        n = save(m, OUT, f"prop | atlas props_atlas.png", report)
        print(f"{m.name:24s} {n:5d} tris size {[round(s, 2) for s in m.size()]} inverted {report[m.name]['invertedParts']}")
    Image.fromarray((np.clip(A.img, 0, 1) * 255).astype(np.uint8), "RGB").save(
        os.path.join(TEX, "props_atlas.png"), optimize=True)
    merge_report(os.path.join(OUT, "_model_report.json"), report)
    sheet = Image.new("RGB", (7 * 180, 5 * 180), (40, 44, 52))
    for i, m in enumerate(built):
        rgb, a = render(m, A.img, size=180, yaw=145, pitch=22, fit=.85)
        sheet.paste(Image.fromarray((rgb * 255).astype(np.uint8)), ((i % 7) * 180, (i // 7) * 180),
                    Image.fromarray((a * 255).astype(np.uint8)))
    sheet.save("/tmp/props_preview.png")


if __name__ == "__main__":
    main()
