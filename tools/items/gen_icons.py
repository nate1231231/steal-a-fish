"""Phase 4: 512x512 icons for every item (transparent background, rarity-colored frame, star count).

python tools/items/gen_icons.py
Model icons are rendered from the exported OBJ files + atlases, so they show exactly what ships.
Gamepass / dev-product icons use small in-memory meshes (coins, crown, sack, chest) from the props atlas.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import gen_props as GP
import item_data as D
from meshlib import Mesh, ObjMesh, box, frustum, lathe, render, rot_y, slab

ROOT = D.ROOT
OUT = os.path.join(ROOT, "items", "icons")
MODELS = os.path.join(ROOT, "items", "models")
BIG = 1024  # draw at 2x then downsample for anti-aliasing
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
S = GP.S

VIEW = dict(Fish=(70, 15), Net=(145, 18), Tank=(148, 24), Lock=(152, 18), Boost=(148, 18), BangkaSkin=(125, 24),
            Hat=(148, 26), GamePass=(150, 22), DevProduct=(150, 24))
VIEW_OVERRIDE = {"fish_alimasag": (180, 42), "fish_alimango": (180, 42)}


def load_tex(name):
    return np.asarray(Image.open(os.path.join(ROOT, "items", "textures", name)).convert("RGB"), float) / 255


def model_image(mesh, tex, yaw, pitch):
    rgb, a = render(mesh, tex, size=BIG, yaw=yaw, pitch=pitch, fit=.96)
    img = Image.fromarray(np.dstack([rgb * 255, a * 255]).astype(np.uint8), "RGBA")
    return img.crop(img.getbbox())


def outlined(img, px=12, color=(18, 18, 26)):
    pad = px + 2
    canvas = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad))
    canvas.paste(img, (pad, pad))
    a = canvas.getchannel("A").filter(ImageFilter.MaxFilter(2 * (px // 2) + 1))
    a = a.filter(ImageFilter.MaxFilter(2 * (px // 2) + 1))
    out = Image.new("RGBA", canvas.size, color + (0,))
    out.putalpha(a)
    out.alpha_composite(canvas)
    return out


def star(cx, cy, r):
    return [(cx + (r if k % 2 == 0 else r * .45) * math.sin(math.pi * k / 5),
             cy - (r if k % 2 == 0 else r * .45) * math.cos(math.pi * k / 5)) for k in range(10)]


def frame(rarity):
    r = D.RARITY_BY_NAME[rarity]
    col = np.array(r["color"], float)
    img = Image.new("RGBA", (BIG, BIG))
    m, rad = 40, 150
    # inner glow (semi-transparent so the icon sits on any UI background)
    yy, xx = np.mgrid[0:BIG, 0:BIG]
    d = np.sqrt((xx - BIG / 2) ** 2 + (yy - BIG * .45) ** 2) / (BIG * .62)
    glow = np.zeros((BIG, BIG, 4))
    glow[..., :3] = col * (1 - .35 * np.clip(d, 0, 1))[..., None] + 255 * .25 * np.clip(1 - d, 0, 1)[..., None]
    glow[..., 3] = 255 * (.62 - .3 * np.clip(d, 0, 1))
    mask = Image.new("L", (BIG, BIG))
    ImageDraw.Draw(mask).rounded_rectangle((m, m, BIG - m, BIG - m), rad, fill=255)
    g = Image.fromarray(np.clip(glow, 0, 255).astype(np.uint8), "RGBA")
    img.paste(g, (0, 0), mask)
    dr = ImageDraw.Draw(img)
    dark = tuple(int(c * .45) for c in col) + (255,)
    light = tuple(int(min(255, c * 1.25 + 40)) for c in col) + (255,)
    dr.rounded_rectangle((m - 10, m - 10, BIG - m + 10, BIG - m + 10), rad + 10, outline=dark, width=14)
    dr.rounded_rectangle((m, m, BIG - m, BIG - m), rad, outline=tuple(int(c) for c in col) + (255,), width=30)
    dr.rounded_rectangle((m + 24, m + 24, BIG - m - 24, BIG - m - 24), rad - 24, outline=light, width=6)
    return img, dark


def stars(img, n, dark):
    dr = ImageDraw.Draw(img)
    r, gap = 34, 76
    x0 = BIG / 2 - (n - 1) * gap / 2
    for k in range(n):
        pts = star(x0 + k * gap, BIG - 52, r)
        dr.polygon(pts, fill=(255, 225, 90, 255), outline=(40, 30, 10, 255), width=7)


def text(img, s, size=190, pos=None, fill=(255, 255, 255)):
    try:
        font = ImageFont.truetype(FONT, size)
    except OSError:
        font = ImageFont.load_default(size=size)
    dr = ImageDraw.Draw(img)
    w = dr.textlength(s, font=font)
    x, y = pos or (BIG / 2 - w / 2, 70)
    dr.text((x, y), s, font=font, fill=fill + (255,), stroke_width=14, stroke_fill=(20, 20, 28, 255))


def compose(item, rarity, model, label=None, label_pos=None, label_size=190):
    img, dark = frame(rarity)
    box_w = BIG - 2 * 120
    sc = min(box_w / model.width, (box_w - 20) / model.height)
    mdl = outlined(model.resize((max(1, int(model.width * sc)), max(1, int(model.height * sc))), Image.LANCZOS))
    img.alpha_composite(mdl, (int(BIG / 2 - mdl.width / 2), int(BIG * .49 - mdl.height / 2)))
    if label:
        text(img, label, label_size, label_pos)
    stars(img, D.RARITY_BY_NAME[rarity]["order"], dark)
    img = img.resize((512, 512), Image.LANCZOS)
    img.save(os.path.join(OUT, item["id"] + ".png"), optimize=True)
    return img


# ------------------------------------------------------------------ shop meshes (icons only, not exported)
def coin(m, c, tilt=0.0, r=.5):
    c = np.asarray(c, float)
    ax = np.array([math.sin(tilt), math.cos(tilt), 0]) * .07
    frustum(m.part(), c - ax, c + ax, r, r, 14, S("gold"))
    frustum(m.part(), c + ax, c + ax * 1.3, r * .7, r * .7, 14, S("gold_dark"))


def coin_pile(m, n, ox=0.0, oz=0.0):
    for k in range(n):
        coin(m, (ox + .04 * math.sin(k * 2.1), .07 + k * .15, oz + .04 * math.cos(k * 1.7)))


def sack(m, s=1.0, ox=0.0):
    lathe(m.part(smooth=True), [(0, 0), (.9 * s, .1 * s), (1.1 * s, .7 * s), (.8 * s, 1.35 * s), (.3 * s, 1.6 * s),
                                (.35 * s, 1.95 * s), (.55 * s, 2.15 * s), (0, 2.1 * s)], 12, S("cork"), center=(ox, 0, 0))
    GP.ring(m, (ox, 1.62 * s, 0), (0, 1, 0), .32 * s, .06 * s, S("red"), n=10, segs=4)
    box(m.part(), (ox, .85 * s, -1.0 * s), (.5 * s, .5 * s, .06), S("gold"))


def shop_mesh(item):
    m = Mesh(item["id"])
    i = item["id"]
    if i == "gp_2x_cash":
        coin_pile(m, 6, -.6, .2)
        coin_pile(m, 4, .55, -.1)
        coin_pile(m, 2, 0, -.9)
        coin(m, (.2, .95, .3), tilt=.9)
    elif i == "gp_auto_net":
        return ObjMesh(os.path.join(MODELS, "boost_auto_net.obj"))
    elif i == "gp_vip":
        lathe(m.part(), [(1.0, 0), (1.1, 0), (1.1, .55), (1.0, .55), (1.0, 0)], 16, S("gold"))
        for k in range(5):
            a = 2 * math.pi * k / 5 + math.pi / 2
            p = np.array([1.05 * math.cos(a), .5, 1.05 * math.sin(a)])
            frustum(m.part(), p, p + [0, .9, 0], .3, 0, 5, S("gold"))
            GP.sphere(m.part(), p + [0, .95, 0], .1, S("white"), segs=6, rings=3)
            GP.sphere(m.part(), p * [1.06, 1, 1.06] + [0, -.22, 0], .12, S("red" if k % 2 else "blue"), segs=6, rings=3)
    elif i == "dp_cash_small":
        sack(m, .8)
        coin_pile(m, 3, 1.1, -.3)
    elif i == "dp_cash_medium":
        sack(m, 1.1)
        coin_pile(m, 5, 1.5, -.4)
        coin_pile(m, 3, -1.4, -.5)
    elif i == "dp_cash_large":
        box(m.part(), (0, .6, 0), (2.6, 1.2, 1.7), GP.PL("planks", (1, 0, 0), (0, -1, 0), (-1.3, 1.3), (-1.2, 0)))
        frustum(m.part(), (-1.3, 1.2, 0), (1.3, 1.2, 0), .85, .85, 10, S("wood_dark"))
        for x in (-1.0, 1.0):
            box(m.part(), (x, .6, 0), (.18, 1.26, 1.76), S("gold"))
            frustum(m.part(), (x - .09, 1.2, 0), (x + .09, 1.2, 0), .9, .9, 10, S("gold"))
        box(m.part(), (0, 1.15, -.9), (.36, .44, .1), S("gold"))
        for k, (x, z) in enumerate(((-.5, -1.4), (.4, -1.5), (1.4, -1.1), (-1.5, -1.0))):
            coin_pile(m, 2 + k % 3, x, z)
    return m.finalize()


def main():
    os.makedirs(OUT, exist_ok=True)
    tex = dict(fish=load_tex("fish_atlas.png"), props=load_tex("props_atlas.png"))
    sheet = Image.new("RGBA", (10 * 128, 7 * 128), (52, 56, 66, 255))
    k = 0
    for cat, item in D.all_items():
        yaw, pitch = VIEW_OVERRIDE.get(item["id"], VIEW[cat])
        label, lpos, lsize = None, None, 190
        if cat in D.MODEL_CATEGORIES:
            mesh = ObjMesh(os.path.join(MODELS, item["id"] + ".obj"))
            t = tex["fish"] if cat == "Fish" else tex["props"]
        else:
            mesh, t = shop_mesh(item), tex["props"]
            label = {"gp_2x_cash": "2x", "gp_auto_net": "AUTO", "gp_vip": "VIP"}.get(item["id"])
            if item["id"] == "gp_auto_net":
                lsize = 150
        img = compose(item, item["rarity"], model_image(mesh, t, yaw, pitch), label, lpos, lsize)
        sheet.alpha_composite(img.resize((128, 128), Image.LANCZOS), ((k % 10) * 128, (k // 10) * 128))
        k += 1
    sheet.save("/tmp/icons_sheet.png")
    print(f"{k} icons written to {OUT}")


if __name__ == "__main__":
    main()
