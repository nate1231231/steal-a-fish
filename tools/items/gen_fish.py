"""Phase 2: fish meshes (5 shared body variants) + fish_atlas.png.

python tools/items/gen_fish.py
Atlas: 1024x1024, 4 x 8 cells of 256x128 px, one cell per species (FishData.order - 1).
  cell body rect  (2,2)-(254,110): side projection (u = nose->tail, v = top->bottom); crabs: top view
  cell strip row  y 114-126: fin | belly | dark | accent sub-swatches
"""
import math
import os

import numpy as np
from PIL import Image

import item_data as D
from meshlib import Mesh, frustum, loft, merge_report, render, save, slab, tube, uv_point, uv_swatch

OUT = os.path.join(D.ROOT, "items", "models")
TEX = os.path.join(D.ROOT, "items", "textures")
CW, CH, COLS = 256, 128, 4
BODY = (2, 2, 254, 110)
STRIP = dict(fin=(2, 114, 158, 126), belly=(162, 114, 190, 126), dark=(194, 114, 222, 126),
             accent=(226, 114, 254, 126))
THICK = 0.014  # fin thickness relative to body length

VARIANTS = {
    "slender": dict(T=[0, .05, .15, .3, .5, .7, .85, .95, 1], top=[.18, .5, .82, 1, .95, .68, .36, .2, .17],
                    bot=[.18, .48, .8, 1, .9, .6, .3, .18, .15], wid=[.15, .45, .8, .95, .85, .55, .3, .15, .12],
                    wf=.55, tail="forked", tl=.27, span=.95, eyeT=.075, eyeR=.03),
    "deep": dict(T=[0, .06, .18, .35, .55, .75, .88, .96, 1], top=[.2, .58, .92, 1, .95, .62, .3, .17, .15],
                 bot=[.2, .52, .86, 1, .9, .55, .25, .15, .14], wid=[.15, .45, .8, .92, .8, .5, .25, .12, .1],
                 wf=.36, tail="forked", tl=.3, span=.8, eyeT=.09, eyeR=.035),
    "tuna": dict(T=[0, .06, .2, .4, .6, .78, .9, .97, 1], top=[.16, .52, .88, 1, .9, .55, .22, .1, .08],
                 bot=[.16, .5, .85, 1, .85, .5, .2, .1, .08], wid=[.15, .5, .85, 1, .85, .5, .24, .14, .14],
                 wf=.72, tail="crescent", tl=.3, span=1.3, eyeT=.08, eyeR=.03),
}
RING_T = [.03, .07, .12, .19, .27, .36, .46, .56, .66, .75, .83, .9, .95, 1.0]


def cell_rect(idx, r):
    x0, y0 = (idx % COLS) * CW, (idx // COLS) * CH
    return (x0 + r[0], y0 + r[1], x0 + r[2], y0 + r[3])


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ texture painting
def paint(atlas, idx, fish, geo):
    v = fish["visual"]
    rng = np.random.default_rng(sum(map(ord, fish["id"])))
    back, belly, fin, acc = (np.array(v[k], float) / 255 for k in ("back", "belly", "fin", "accent"))
    tips = np.array(v.get("tips", np.array(v["back"]) * 0.4), float) / 255
    x0, y0, x1, y1 = cell_rect(idx, (0, 0, 256, 112))
    bh, bw = y1 - y0, x1 - x0
    S, T = np.mgrid[0:bh, 0:bw].astype(float)
    T = (T - 2 + .5) / 252
    S = (S - 2 + .5) / 108
    Lb, H2 = geo["Lb"], geo["H2"]  # mesh units covered by the body rect horizontally / vertically

    def ell(t0, s0, r, soft=0.3):
        d = np.sqrt(((T - t0) / (r / Lb)) ** 2 + ((S - s0) / (r / H2)) ** 2)
        return np.clip((1 - d) / soft, 0, 1)

    k = smoothstep(.36, .7, S)[..., None]
    col = back * (1 - k) + belly * k
    if geo["variant"] == "crab":
        rad = np.sqrt(((T - .5) / .5) ** 2 + ((S - .55) / .5) ** 2)
        col = back * (1.15 - 0.3 * np.clip(rad, 0, 1))[..., None]
        col = col * (1 - smoothstep(.12, .0, S)[..., None] * 0.45)

    def blend(mask, color, a=1.0):
        nonlocal col
        m = (np.clip(mask, 0, 1) * a)[..., None]
        col = col * (1 - m) + np.asarray(color) * m

    body_t = smoothstep(.12, .2, T)
    p = v["pattern"]
    if p == "hstripe":
        blend((1 - np.abs(S - .44) / .055) * body_t, acc, .85)
    elif p == "spotrow":
        for t in np.linspace(.25, .85, 8):
            blend(ell(t, .34, .016 * Lb), acc, .9)
    elif p == "gillspot":
        blend(ell(.22, .32, .03 * Lb), acc, .9)
        blend((1 - np.abs(S - .5) / .02) * body_t, back * .7, .5)
    elif p == "wavy":
        blend(((np.sin(T * 2 * np.pi * 9 + np.sin(S * 2 * np.pi * 3) * 2) > .55) * (S < .42)) * body_t, acc, .7)
    elif p == "vbars":
        blend(((np.sin(T * 2 * np.pi * 8) > .35) * smoothstep(.75, .55, S)) * body_t, acc, .6)
    elif p in ("mottled", "spots", "crabspots"):
        n, r0, r1, a = dict(mottled=(40, .025, .05, .45), spots=(55, .01, .02, .9), crabspots=(70, .012, .03, .85))[p]
        for _ in range(n):
            blend(ell(rng.uniform(.1, .97), rng.uniform(.08, .9), rng.uniform(r0, r1) * Lb), acc, a)
    elif p == "scales":
        sz = .045 * Lb
        u, w = T * Lb / sz, S * H2 / sz
        u = u + .5 * (np.floor(w) % 2)
        d = np.sqrt((u - np.floor(u) - .5) ** 2 + (w - np.floor(w)) ** 2)
        blend(((d > .42) & (d < .52)) * body_t * smoothstep(.05, .2, S), acc, .45)
    elif p == "hlines":
        for s0 in (.42, .52, .62, .72):
            blend((1 - np.abs(S - s0) / .018) * body_t, acc, .85)
    elif p == "iridescent":
        h = np.clip(T, 0, 1)[..., None]
        top = back * (1 - h) + fin * h
        col = top * (1 - k) + (belly * .5 + acc * .5) * k
        for _ in range(60):
            blend(ell(rng.uniform(.05, 1), rng.uniform(.05, .95), rng.uniform(.004, .009) * Lb, .6), [1, 1, 1], .95)
    elif p == "dragon":
        sz = .04 * Lb
        u, w = T * Lb / sz, S * H2 / sz
        u = u + .5 * (np.floor(w) % 2)
        d = np.sqrt((u - np.floor(u) - .5) ** 2 + (w - np.floor(w)) ** 2)
        blend(((d > .4) & (d < .5)) * smoothstep(.6, .4, S), back * 1.8, .6)
        for t in np.linspace(.15, .95, 14):
            blend(ell(t, .5, .012 * Lb, .5), acc, 1)
    if geo["variant"] in ("slender", "deep", "tuna"):
        tg = geo["gillT"]
        curve = tg - .035 * (1 - ((S - .5) / .3) ** 2)
        blend((1 - np.abs(T - curve) / .007) * smoothstep(.2, .3, S) * smoothstep(.8, .7, S), back * .45, .5)
    if geo.get("eyeT") is not None:
        et, es, er = geo["eyeT"], geo["eyeS"], geo["eyeR"] * Lb
        iris = acc if fish["rarity"] == "Mythic" else np.array([.96, .9, .7])
        blend(ell(et, es, er * 1.15), [.08, .08, .1], 1)
        blend(ell(et, es, er), iris, 1)
        blend(ell(et, es, er * .55), [.03, .03, .05], 1)
        blend(ell(et - .25 * er / Lb, es - .3 * er / H2, er * .22, .5), [1, 1, 1], 1)
    col = col + rng.normal(0, .012, col.shape)
    atlas[y0:y1, x0:x1] = np.clip(col, 0, 1)
    # strip sub-swatches
    sx0, sy0 = (idx % COLS) * CW, (idx // COLS) * CH
    atlas[sy0 + 112:sy0 + 128, sx0:sx0 + 160] = fin
    ray = (np.arange(160) % 6 < 2)
    atlas[sy0 + 112:sy0 + 128, sx0:sx0 + 160][:, ray] *= .82
    atlas[sy0 + 122:sy0 + 128, sx0:sx0 + 160] = np.clip(fin * 1.15 + .05, 0, 1)
    atlas[sy0 + 112:sy0 + 128, sx0 + 160:sx0 + 192] = belly
    atlas[sy0 + 112:sy0 + 128, sx0 + 192:sx0 + 224] = tips
    atlas[sy0 + 112:sy0 + 128, sx0 + 224:sx0 + 256] = acc


# ------------------------------------------------------------------ meshes
def tail_poly(kind, TL, S, p):
    pts = dict(
        forked=[(0, p), (TL, S), (.5 * TL, 0), (TL, -S), (0, -p)],
        crescent=[(0, p), (.8 * TL, 1.15 * S), (.5 * TL, .5 * S), (.32 * TL, 0), (.5 * TL, -.5 * S),
                  (.8 * TL, -1.15 * S), (0, -p)],
        round=[(0, p), (.5 * TL, .8 * S), (TL, .5 * S), (1.1 * TL, 0), (TL, -.5 * S), (.5 * TL, -.8 * S), (0, -p)],
        square=[(0, p), (TL, .85 * S), (.94 * TL, 0), (TL, -.85 * S), (0, -p)],
        shark=[(0, p), (1.2 * TL, 1.35 * S), (.95 * TL, .95 * S), (.4 * TL, .05 * S), (.7 * TL, -.65 * S),
               (.25 * TL, -.35 * S), (0, -p)],
        veil=[(0, p), (1.5 * TL, 1.7 * S), (2.0 * TL, .9 * S), (1.6 * TL, 0), (2.0 * TL, -.9 * S),
              (1.5 * TL, -1.7 * S), (0, -p)],
        long=[(0, p), (.9 * TL, .9 * S), (1.5 * TL, .35 * S), (1.25 * TL, 0), (1.5 * TL, -.35 * S),
              (.9 * TL, -.9 * S), (0, -p)],
    )
    return pts[kind]


def build_fish(f, idx):
    v = f["visual"]
    var = VARIANTS[v["variant"]]
    Lb = 1.0
    H = Lb / (2 * v["ratio"])
    W = H * var["wf"]
    Tc = var["T"]
    top = lambda t: np.interp(t, Tc, var["top"]) * H  # noqa: E731
    bot = lambda t: np.interp(t, Tc, var["bot"]) * H  # noqa: E731
    wid = lambda t: np.interp(t, Tc, var["wid"]) * W  # noqa: E731
    m = Mesh(f["id"])
    body_uv = uv_point(cell_rect(idx, BODY), lambda p: (p[2] / Lb, (H - p[1]) / (2 * H)))
    sw = {k: cell_rect(idx, r) for k, r in STRIP.items()}
    fin_uv = uv_point(sw["fin"], lambda p: (p[2] / (Lb * 1.4), min(abs(p[1]) / (1.6 * H), 1)))
    dark_uv, acc_uv = uv_swatch(sw["dark"]), uv_swatch(sw["accent"])
    th = THICK * Lb
    segs = 12
    rings = []
    for t in RING_T:
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            ca, sa = math.cos(a), math.sin(a)
            ring.append((wid(t) * sa, (top(t) if ca > 0 else bot(t)) * ca, t * Lb))
        rings.append(ring)
    loft(m.part(smooth=True), rings, body_uv, start_tip=(0, -.12 * H, 0))
    # tail
    tail = v.get("tail", var["tail"])
    TL = var["tl"] * Lb * (1.3 if tail in ("veil", "long") else 1)
    pz, py = Lb * .985, 0.0
    poly = [(0, py + y, pz + z) for z, y in tail_poly(tail, TL, var["span"] * H, top(1) * .9)]
    slab(m.part(), poly, th, fin_uv)
    # dorsal
    dorsal = v.get("dorsal", "crest" if v.get("crest") else ("long" if v.get("longFins") else "normal"))
    yt = lambda t: top(t) - .04 * H  # noqa: E731
    z = lambda t: t * Lb  # noqa: E731
    if dorsal == "normal":
        a, b, h = (.25, .78, .38) if v["variant"] == "deep" else (.34, .58, .45)
        pts = [(z(a), yt(a)), (z(a + .05), yt(a) + h * H), (z(b - .04), yt(b) + .55 * h * H), (z(b), yt(b))]
        slab(m.part(), [(0, y, zz) for zz, y in pts], th, fin_uv)
        if v["variant"] == "tuna":
            slab(m.part(), [(0, yt(.6), z(.6)), (0, yt(.62) + .5 * H, z(.66)), (0, yt(.7), z(.7))], th, fin_uv)
    elif dorsal == "shark":
        slab(m.part(), [(0, yt(.34), z(.34)), (0, yt(.4) + .95 * H, z(.47)), (0, yt(.5), z(.5))], th, fin_uv)
    elif dorsal == "sail":
        pts = [(z(.12), yt(.12)), (z(.16), yt(.16) + 1.15 * H), (z(.3), yt(.3) + .9 * H),
               (z(.55), yt(.55) + .35 * H), (z(.62), yt(.62))]
        slab(m.part(), [(0, y, zz) for zz, y in pts], th, fin_uv)
    elif dorsal == "long":
        pts = [(z(.2), yt(.2)), (z(.3), yt(.3) + .85 * H), (z(.75), yt(.75) + 1.1 * H), (z(1.15), top(1) + .5 * H),
               (z(.92), yt(.92))]
        slab(m.part(), [(0, y, zz) for zz, y in pts], th, fin_uv)
    elif dorsal == "crest":
        pts = [(z(.1), yt(.1))]
        for t in np.linspace(.12, .86, 9):
            pts += [(z(t), yt(t) + .55 * H), (z(t + .04), yt(t + .04) + .12 * H)]
        pts.append((z(.92), yt(.92)))
        slab(m.part(), [(0, y, zz) for zz, y in pts], th, fin_uv)
    # anal fin
    yb = lambda t: -bot(t) + .04 * H  # noqa: E731
    if v.get("longFins"):
        a, b, h = .45, .95, .9
    elif v["variant"] == "deep":
        a, b, h = .6, .8, .38
    elif v["variant"] == "tuna":
        a, b, h = .6, .68, .5
    else:
        a, b, h = .6, .74, .3
    slab(m.part(), [(0, yb(a), z(a)), (0, yb(a + .04) - h * H, z(a + .06)), (0, yb(b) - .3 * h * H, z(b)),
                    (0, yb(b), z(b))], th, fin_uv)
    # pectoral fins (left/right)
    pt = .24
    pl = 1.8 if v.get("longFins") else 1.0
    for s in (-1, 1):
        x0 = s * wid(pt) * .92
        slab(m.part(), [(x0, -.1 * H, z(pt)), (x0, -.32 * H, z(pt + .03)),
                        (x0 + s * .45 * W * pl, -.55 * H * pl, z(pt + .16 * pl))], th, fin_uv)
    if v.get("finlets"):
        for t in np.linspace(.73, .94, 5):
            for sign, yf in ((1, top), (-1, lambda q: -bot(q))):
                slab(m.part(), [(0, yf(t) - sign * .02 * H, z(t)), (0, yf(t + .02) - sign * .02 * H, z(t + .02)),
                                (0, yf(t + .03) + sign * .2 * H, z(t + .035))], th * .8, fin_uv)
    if v.get("bill"):
        frustum(m.part(), (0, -.05 * H, .03 * Lb), (0, .02 * H, -.42 * Lb), .07 * H * 1.2, 0, 6, dark_uv)
    if v.get("whiskers"):
        for s in (-1, 1):
            st = np.array([s * .25 * W, -.15 * H, .02 * Lb])
            path = [st + np.array([s * .1 * q, -.25 * q * q, .3 * q]) * Lb * (1.6 if v.get("horns") else 1)
                    for q in np.linspace(0, 1, 5)]
            tube(m.part(), path, list(np.linspace(.012, .004, 5) * Lb), 4,
                 acc_uv if v.get("horns") else dark_uv)
    if v.get("horns"):
        for s in (-1, 1):
            frustum(m.part(), (s * .35 * W, top(.12) * .85, .12 * Lb), (s * .8 * W, top(.12) + .9 * H, .3 * Lb),
                    .025 * Lb, 0, 5, uv_swatch(sw["fin"]))
    geo = dict(variant=v["variant"], Lb=Lb, H2=2 * H, gillT=.2 if v["variant"] != "deep" else .23,
               eyeT=var["eyeT"], eyeS=.4, eyeR=var["eyeR"])
    m.finalize(D.FISH_BASE_LENGTH, axes=(2,))
    return m, geo


def build_squid(f, idx):
    m = Mesh(f["id"])
    Lm, R = 1.0, .13
    Tc = [0, .08, .3, .55, .72, .77, .82, .88, .92]
    Rc = [0, .35, .8, .9, .72, .5, .68, .62, .5]
    rad = lambda t: np.interp(t, Tc, Rc) * R  # noqa: E731
    body_uv = uv_point(cell_rect(idx, BODY), lambda p: (p[2] / (.92 * Lm), (R - p[1]) / (2 * R)))
    sw = {k: cell_rect(idx, r) for k, r in STRIP.items()}
    fin_uv = uv_point(sw["fin"], lambda p: (p[2] / (2 * Lm), .5))
    segs = 10
    rings = [[(rad(t) * math.sin(2 * math.pi * j / segs), rad(t) * math.cos(2 * math.pi * j / segs), t * Lm)
              for j in range(segs)] for t in [.02, .06, .12, .2, .3, .42, .55, .65, .72, .77, .82, .88, .92]]
    loft(m.part(smooth=True), rings, body_uv, start_tip=(0, 0, 0))
    for s in (-1, 1):
        slab(m.part(), [(s * rad(.05) * .5, 0, .03), (s * (rad(.2) + .17), 0, .16), (s * rad(.34) * .8, 0, .34)],
             .012, fin_uv)
    ze = .92 * Lm
    re = rad(.92)
    for k in range(10):
        ph = 2 * math.pi * k / 8 if k < 8 else (math.pi * .25 if k == 8 else math.pi * .75) + math.pi
        long_ = k >= 8
        L = .75 if long_ else .45
        c, s_ = math.cos(ph), math.sin(ph)
        st = np.array([c * re * .7, s_ * re * .7, ze - .01])
        path = [st + np.array([c * .25 * q * L, s_ * .25 * q * L - .12 * q * q * L, q * L]) for q in np.linspace(0, 1, 5)]
        radii = [.02, .016, .011, .014, .006] if long_ else [.024, .018, .012, .008, .003]
        tube(m.part(), path, radii, 5, fin_uv)
    geo = dict(variant="squid", Lb=.92 * Lm, H2=2 * R, eyeT=.83, eyeS=.42, eyeR=.045)
    m.finalize(D.FISH_BASE_LENGTH, axes=(2,))
    return m, geo


def build_crab(f, idx):
    v = f["visual"]
    m = Mesh(f["id"])
    spiny = f["id"] == "fish_alimasag"
    A, B, ht, hb = .5, (.3 if spiny else .36), .16, .07
    big = 1.0 if spiny else 1.35
    xr = A * 1.45
    sw = {k: cell_rect(idx, r) for k, r in STRIP.items()}
    top_uv = uv_point(cell_rect(idx, BODY), lambda p: ((p[0] + xr) / (2 * xr), (p[2] + B) / (2 * B)))
    belly_uv = uv_swatch(sw["belly"])

    def shell_uv(pts):
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        return belly_uv(pts) if n[1] < 0 else top_uv(pts)
    segs = 18
    rings = []
    for el in (-60, -25, 0, 30, 60):
        a = math.radians(el)
        y = (ht if el > 0 else hb) * math.sin(a)
        ring = []
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            k = 1.0
            if spiny and abs(math.cos(ph)) > .97:
                k = 1.42
            ring.append((A * k * math.cos(ph) * math.cos(a), y, B * math.sin(ph) * math.cos(a)))
        rings.append(ring)
    loft(m.part(smooth=False), rings, shell_uv, start_tip=(0, -hb, 0), end_tip=(0, ht, 0))
    leg_uv, dark_uv = uv_point(sw["fin"], lambda p: (abs(p[0]) / 1.2, .5)), uv_swatch(sw["dark"])
    for s in (-1, 1):
        for zi, zk in enumerate((-.12, .02, .16, .28)):
            st = np.array([s * A * .8, 0, zk * 1.0])
            knee = np.array([s * (A + .2), .1, zk * 1.3 + .04])
            foot = np.array([s * (A + .34), -.17, zk * 1.5 + .06])
            if zi == 3 and spiny:  # swimming paddle
                tube(m.part(), [st, knee], [.04, .03], 5, leg_uv)
                d = knee + np.array([s * .16, -.02, .1])
                slab(m.part(), [knee, knee + np.array([s * .1, .03, -.02]), d, knee + np.array([s * .06, -.03, .1])],
                     .015, leg_uv)
                continue
            tube(m.part(), [st, knee, foot], [.045, .035, .02], 5, leg_uv)
            frustum(m.part(), foot, foot + np.array([s * .02, -.05, .02]), .012, 0, 4, dark_uv)
        # claw arm + palm + fingers
        sh = np.array([s * A * .62, .0, -B * .7])
        el = np.array([s * (A * .85), .06, -B - .14 * big])
        tube(m.part(), [sh, el], [.04 * big, .035 * big], 6, leg_uv)
        palm_end = el + np.array([-s * .08, .02, -.24]) * big
        frustum(m.part(), el, palm_end, .07 * big, .06 * big, 6, leg_uv)
        frustum(m.part(), palm_end + np.array([0, .025, 0]) * big, palm_end + np.array([s * .07, .03, -.18]) * big,
                .035 * big, 0, 5, dark_uv)
        frustum(m.part(), palm_end - np.array([0, .025, 0]) * big, palm_end + np.array([s * .1, -.02, -.15]) * big,
                .03 * big, 0, 5, dark_uv)
        tube(m.part(), [np.array([s * .07, ht * .4, -B * .85]), np.array([s * .09, ht + .06, -B * .98])],
             .014, 4, dark_uv)
    m.finalize(D.FISH_BASE_LENGTH, axes=(0, 2))
    return m, dict(variant="crab", Lb=2 * xr, H2=2 * B)


def main():
    atlas = np.full((1024, 1024, 3), .5)
    report = {}
    previews = []
    for i, f in enumerate(D.FISH):
        build = dict(squid=build_squid, crab=build_crab).get(f["visual"]["variant"], build_fish)
        m, geo = build(f, i)
        paint(atlas, i, f, geo)
        n = save(m, OUT, f"fish | {f['name']} | body variant {f['visual']['variant']} | atlas cell {i}", report)
        previews.append(m)
        print(f"{f['id']:24s} {n:5d} tris  size {[round(s, 2) for s in m.size()]}  inverted {report[f['id']]['invertedParts']}")
    img = Image.fromarray((atlas * 255).astype(np.uint8), "RGB")
    img.save(os.path.join(TEX, "fish_atlas.png"), optimize=True)
    merge_report(os.path.join(OUT, "_model_report.json"), report)
    # one contact sheet for a visual sanity check (not committed)
    sheet = Image.new("RGB", (6 * 200, 4 * 120), (40, 44, 52))
    for i, m in enumerate(previews):
        rgb, a = render(m, atlas, size=200, yaw=70, pitch=15, fit=.9)
        tile = Image.fromarray((rgb * 255).astype(np.uint8)).crop((0, 40, 200, 160))
        sheet.paste(tile, ((i % 6) * 200, (i // 6) * 120), Image.fromarray((a[40:160] * 255).astype(np.uint8)))
    sheet.save("/tmp/fish_preview.png")


if __name__ == "__main__":
    main()
