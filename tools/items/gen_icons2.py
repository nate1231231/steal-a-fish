"""Polished icons: beveled glossy frame, rarity glow + pattern + sparkle + vignette, lit model render,
vector gold stars, empty top-right badge slot and bottom mutation strip, transparent item-only export,
8 mutation badges.

python tools/items/gen_icons2.py                   -> all 65 icons + badges + contact sheet
python tools/items/gen_icons2.py fish_bangus ...   -> only those ids
python tools/items/gen_icons2.py --test            -> one icon per category into /tmp/icontest/
Outputs: items/icons/<id>.png (512 RGBA), items/icons/item_only/<id>.png, items/icons/badges/<id>_{512,128}.png
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

import gen_icons as OLD  # shop meshes (coins, crown, sack, chest)
import item_data as D
from icon_render import render_item
from meshlib import ObjMesh

ROOT = D.ROOT
OUT = os.path.join(ROOT, "items", "icons")
OUT_ITEM = os.path.join(OUT, "item_only")
OUT_BADGE = os.path.join(OUT, "badges")
MODELS = os.path.join(ROOT, "items", "models")
SIZE, SS = 512, 4
BIG = SIZE * SS
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# ---- layout at 512 px
MARGIN, RADIUS, BAND = 14, 70, 24                      # outer margin, corner radius, frame band width
INNER = MARGIN + BAND                                  # 38: inside edge of the frame band
BADGE_SLOT = (SIZE - INNER - 100, INNER + 4, SIZE - INNER, INNER + 104)   # 100 px square, top-right (kept empty)
STRIP = (INNER + 10, SIZE - INNER - 94, SIZE - INNER - 10, SIZE - INNER - 58)  # mutation tag strip (kept empty)
STAR_Y = SIZE - INNER - 28                            # star row centre, 28 px above the inner edge
ITEM_BOX = (INNER + 6, INNER + 10, SIZE - INNER - 6, STRIP[1] - 4)  # model lives here
ITEM_FILL = 0.70                                      # longest side = 70% of the frame interior

RARITY_THEME = {
    "Common": dict(glow=(190, 200, 215), frame=(125, 135, 150), light=(230, 236, 244), dark=(58, 64, 76)),
    "Rare": dict(glow=(80, 160, 255), frame=(45, 112, 220), light=(175, 212, 255), dark=(18, 48, 118)),
    "Epic": dict(glow=(185, 95, 255), frame=(132, 55, 218), light=(222, 182, 255), dark=(58, 18, 108)),
    "Legendary": dict(glow=(255, 155, 45), frame=(228, 122, 26), light=(255, 222, 152), dark=(118, 54, 10)),
    "Mythic": dict(glow=(255, 80, 120), frame=(205, 45, 95), light=(255, 205, 225), dark=(88, 14, 46)),
}

# camera per category: yaw, pitch, thin boost
VIEW = dict(Fish=(62, 20, 1.3), Net=(-38, 22, 1.2), Tank=(-35, 26, 0.6), Lock=(-32, 20, 0.9), Boost=(-35, 20, 0.8),
            BangkaSkin=(-50, 26, 0.8), Hat=(-35, 28, 0.6), GamePass=(-35, 24, 0.0), DevProduct=(-35, 24, 0.0))
VIEW_OVERRIDE = {
    "fish_alimasag": (-35, 44, 1.5), "fish_alimango": (-35, 44, 1.5),
    "fish_pusit": (55, 18, 1.2), "fish_pusit_higante": (55, 18, 1.2), "fish_hito": (62, 20, 1.6),
    "fish_bakunawa": (62, 20, 1.5), "fish_malasugi": (62, 18, 1.4), "fish_diwata": (62, 20, 1.2),
    "net_bamboo_rod": (-50, 18, 2.6), "net_fiberglass_rod": (-50, 18, 2.6), "net_steel_reel": (-50, 18, 2.2),
    "lock_laser_fence": (-28, 18, 1.4), "lock_chain_gate": (-25, 16, 1.0), "lock_alarm_bell": (-35, 18, 1.2),
    "tank_banyera": (-35, 32, 0.6), "tank_palaisdaan": (-35, 36, 0.6), "tank_ocean_dome": (-35, 22, 0.6),
    "hat_salakot": (-35, 34, 0.6), "hat_buri": (-35, 34, 0.6), "hat_bangus": (55, 24, 1.0),
    "boost_speed_boots": (-40, 22, 1.0), "gp_auto_net": (-35, 20, 0.8),
}
SHOP_LABEL = {"gp_2x_cash": ("2x", (255, 232, 100)), "gp_auto_net": ("AUTO", (130, 232, 255)), "gp_vip": ("VIP", (255, 218, 95))}
MUTATIONS = ["thunderstorm", "typhoon", "blood_moon", "aurora", "golden_tide", "rainbow_bloom", "solar_eclipse",
             "bakunawa_eclipse"]


def load_tex(name):
    return np.asarray(Image.open(os.path.join(ROOT, "items", "textures", name)).convert("RGB"), np.float32) / 255


def rounded_mask(size, box, radius):
    m = Image.new("L", (size, size))
    ImageDraw.Draw(m).rounded_rectangle(box, radius, fill=255)
    return m


def np_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


# ------------------------------------------------------------------ background + frame
def background(rarity, seed):
    rng = np.random.default_rng(seed)
    th = RARITY_THEME[rarity]
    glow = np.array(th["glow"], np.float32) / 255
    dark = np.array(th["dark"], np.float32) / 255
    yy, xx = (np.mgrid[0:SIZE, 0:SIZE] / SIZE).astype(np.float32)
    base = dark * 0.5 * (1 - yy[..., None] * 0.45) + np.array([0.05, 0.06, 0.09], np.float32)
    d = np.sqrt((xx - 0.5) ** 2 + ((yy - 0.47) * 1.1) ** 2)
    g = np.clip(1 - d / 0.6, 0, 1) ** 1.7
    if rarity == "Mythic":  # rainbow shimmer
        hue = (xx * 0.8 + yy * 0.45 + 0.08 * np.sin(yy * 11 + xx * 5) + rng.uniform(0, 1)) % 1
        h6 = hue * 6
        rc = np.stack([np.clip(np.abs(h6 - 3) - 1, 0, 1), np.clip(2 - np.abs(h6 - 2), 0, 1),
                       np.clip(2 - np.abs(h6 - 4), 0, 1)], -1) * 0.8 + 0.2
        shimmer = 0.85 + 0.15 * np.sin(xx * 46 + yy * 31 + rng.uniform(0, 6))
        img = base + rc * (g * shimmer)[..., None] * 0.95
        ray_col = np.array([1, 1, 1], np.float32)
    else:
        img = base + glow * g[..., None] * (0.6 if rarity == "Common" else 0.95)
        ray_col = glow
    ang = np.arctan2(yy - 0.47, xx - 0.5)
    rays = (0.5 + 0.5 * np.sin(ang * 14 + rng.uniform(0, 6))) ** 3
    img += ray_col * (rays * g * 0.10)[..., None]
    gx, gy = (xx * 22) % 1, (yy * 22 + (np.floor(xx * 22) % 2) * 0.5) % 1
    dots = np.clip(1 - np.sqrt((gx - 0.5) ** 2 + (gy - 0.5) ** 2) / 0.16, 0, 1)
    img += (dots * 0.045 * (1 - g * 0.6))[..., None]
    spark = np.zeros((SIZE, SIZE), np.float32)
    for _ in range(26):
        cx, cy, r = rng.uniform(0.12, 0.88), rng.uniform(0.12, 0.9), rng.uniform(0.004, 0.012)
        dd = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        spark += np.clip(1 - dd / r, 0, 1) ** 2 * rng.uniform(0.3, 1)
        if rng.random() < 0.5:
            spark += np.clip(1 - (np.abs(xx - cx) * 22 + np.abs(yy - cy) * 0.6) / r, 0, 1) ** 2 * 0.5
            spark += np.clip(1 - (np.abs(yy - cy) * 22 + np.abs(xx - cx) * 0.6) / r, 0, 1) ** 2 * 0.5
    img += np.clip(spark, 0, 1)[..., None] * 0.6
    v = np.clip(1 - np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2) / 0.72, 0, 1) ** 0.8
    img *= (0.55 + 0.45 * v)[..., None]
    bg = np_img(img).convert("RGBA")

    # frame band at 4x
    frame = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    m, rad, w = MARGIN * SS, RADIUS * SS, BAND * SS
    fc, lc = th["frame"], th["light"]
    band = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle((m, m, BIG - m, BIG - m), rad, outline=fc + (255,), width=w)
    grad = np.linspace(1.4, 0.7, BIG, dtype=np.float32)[:, None, None]
    ba = np.asarray(band).astype(np.float32)
    ba[..., :3] = np.clip(ba[..., :3] * grad, 0, 255)
    frame.alpha_composite(Image.fromarray(ba.astype(np.uint8), "RGBA"))
    dr = ImageDraw.Draw(frame)
    dr.rounded_rectangle((m, m, BIG - m, BIG - m), rad, outline=tuple(int(c * 0.42) for c in fc) + (255,), width=3 * SS)
    dr.rounded_rectangle((m + 3 * SS, m + 3 * SS, BIG - m - 3 * SS, BIG - m - 3 * SS), rad - 3 * SS,
                         outline=lc + (175,), width=3 * SS)
    dr.rounded_rectangle((m + w - 3 * SS, m + w - 3 * SS, BIG - m - w + 3 * SS, BIG - m - w + 3 * SS), rad - w + 3 * SS,
                         outline=tuple(int(c * 0.5) for c in fc) + (210,), width=3 * SS)
    dr.rounded_rectangle((m + w, m + w, BIG - m - w, BIG - m - w), rad - w, outline=lc + (80,), width=2 * SS)
    sweep = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(sweep).ellipse((m - BIG * 0.25, m - BIG * 0.5, BIG - m + BIG * 0.25, m + w * 2.4), fill=(255, 255, 255, 75))
    sweep_mask = Image.new("L", (BIG, BIG))
    ImageDraw.Draw(sweep_mask).rounded_rectangle((m, m, BIG - m, BIG - m), rad, outline=255, width=w)
    sweep.putalpha(ImageChops.multiply(sweep.getchannel("A"), sweep_mask))
    frame.alpha_composite(sweep)
    frame = frame.resize((SIZE, SIZE), Image.LANCZOS)

    inner = rounded_mask(SIZE, (INNER, INNER, SIZE - INNER, SIZE - INNER), RADIUS - BAND)
    shade = ImageChops.subtract(inner, inner.filter(ImageFilter.GaussianBlur(9)))
    sh = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh.putalpha(shade)
    bg.alpha_composite(sh)
    bg.alpha_composite(frame)
    outer = rounded_mask(SIZE, (MARGIN, MARGIN, SIZE - MARGIN, SIZE - MARGIN), RADIUS)
    bg.putalpha(ImageChops.multiply(bg.getchannel("A"), outer))
    drop = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    drop.putalpha(outer.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.6)))
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(drop, (0, 4))
    out.alpha_composite(bg)
    return out


# ------------------------------------------------------------------ stars
def star_points(cx, cy, r, inner=0.46):
    return [(cx + (r if k % 2 == 0 else r * inner) * math.sin(math.pi * k / 5),
             cy - (r if k % 2 == 0 else r * inner) * math.cos(math.pi * k / 5)) for k in range(10)]


def draw_stars(img, count, total=5):
    r, gap = 16, 42
    x0 = SIZE / 2 - (total - 1) * gap / 2
    layer = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    dr = ImageDraw.Draw(layer)
    for k in range(total):
        pts = [(x * SS, y * SS) for x, y in star_points(x0 + k * gap, STAR_Y + 2.5, r * 1.1)]
        dr.polygon(pts, fill=(0, 0, 0, 130))
    layer = layer.filter(ImageFilter.GaussianBlur(2.5 * SS))
    dr = ImageDraw.Draw(layer)
    for k in range(total):
        cx, cy = x0 + k * gap, STAR_Y
        filled = k < count
        base = (255, 198, 42) if filled else (74, 80, 96)
        edge = (168, 104, 8) if filled else (38, 42, 54)
        shade = (226, 150, 18) if filled else (58, 63, 78)
        light = (255, 242, 178) if filled else (124, 132, 150)
        dr.polygon([(x * SS, y * SS) for x, y in star_points(cx, cy, r)], fill=base + (255,),
                   outline=edge + (255,), width=int(1.5 * SS))
        dr.polygon([(x * SS, y * SS) for x, y in star_points(cx + 1.2, cy + 1.8, r * 0.7)], fill=shade + (255,))
        dr.polygon([(x * SS, y * SS) for x, y in star_points(cx - 1.4, cy - 2.0, r * 0.5)], fill=light + (255,))
        if filled:
            gx, gy = (cx - 4.2) * SS, (cy - 5.2) * SS
            dr.ellipse((gx - 2.3 * SS, gy - 2.3 * SS, gx + 2.3 * SS, gy + 2.3 * SS), fill=(255, 255, 255, 235))
    img.alpha_composite(layer.resize((SIZE, SIZE), Image.LANCZOS))


# ------------------------------------------------------------------ item layer
def item_layer(mesh, tex, view):
    yaw, pitch, thin = view
    rgb, alpha, shadow = render_item(mesh, tex, size=SIZE, ss=2, yaw=yaw, pitch=pitch, thin_boost=thin)
    img = Image.fromarray(np.dstack([(rgb * 255).astype(np.uint8), (alpha * 255).astype(np.uint8)]), "RGBA")
    sh = Image.fromarray((shadow * 255).astype(np.uint8), "L")
    bbox = img.getbbox()  # fit the MODEL only; the ground shadow is cropped with it but doesn't drive the scale
    img, sh = img.crop(bbox), sh.crop(bbox)
    bw, bh = ITEM_BOX[2] - ITEM_BOX[0], ITEM_BOX[3] - ITEM_BOX[1]
    aspect = max(img.width, img.height) / max(1, min(img.width, img.height))
    fill = ITEM_FILL if aspect < 1.8 else min(0.80, ITEM_FILL * (0.85 + 0.12 * aspect))  # long/flat items may span wider
    target = fill * (SIZE - 2 * INNER)
    sc = min(target / max(img.width, img.height), bw / img.width, bh / img.height)
    nw, nh = max(1, int(img.width * sc)), max(1, int(img.height * sc))
    img, sh = img.resize((nw, nh), Image.LANCZOS), sh.resize((nw, nh), Image.LANCZOS)
    cx, cy = (ITEM_BOX[0] + ITEM_BOX[2]) / 2, (ITEM_BOX[1] + ITEM_BOX[3]) / 2
    return img, sh, (int(cx - nw / 2), int(cy - nh / 2))


def shadow_layer(sh, pos):
    full = Image.new("L", (SIZE, SIZE))
    full.paste(sh, pos)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.putalpha(full.filter(ImageFilter.GaussianBlur(3)))
    return layer


def compose(item, img, sh, pos, bg):
    out = bg.copy()
    out.alpha_composite(shadow_layer(sh, pos))
    th = RARITY_THEME[item["rarity"]]
    halo = Image.new("RGBA", (SIZE, SIZE), th["glow"] + (0,))
    a = Image.new("L", (SIZE, SIZE))
    a.paste(img.getchannel("A"), pos)
    a = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.5))
    halo.putalpha(a)
    out.alpha_composite(halo)
    out.alpha_composite(img, pos)
    return out


def item_only(img, sh, pos):
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(shadow_layer(sh, pos))
    out.alpha_composite(img, pos)
    return out


def label(img, text, size, y, color, stroke=(32, 22, 12)):
    layer = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    dr = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT_BOLD, size * SS)
    w = dr.textlength(text, font=font) / SS
    x, yy = (SIZE / 2 - w / 2) * SS, y * SS
    dr.text((x + 3 * SS, yy + 5 * SS), text, font=font, fill=(0, 0, 0, 120), stroke_width=4 * SS, stroke_fill=(0, 0, 0, 120))
    layer = layer.filter(ImageFilter.GaussianBlur(2 * SS))
    dr = ImageDraw.Draw(layer)
    dr.text((x, yy), text, font=font, fill=color + (255,), stroke_width=4 * SS, stroke_fill=stroke + (255,))
    hl = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(hl).text((x, yy - 2 * SS), text, font=font, fill=(255, 255, 255, 110))
    hm = Image.new("L", (BIG, BIG))
    ImageDraw.Draw(hm).rectangle((0, 0, BIG, yy + size * SS * 0.45), fill=255)
    hl.putalpha(ImageChops.multiply(hl.getchannel("A"), hm))
    layer.alpha_composite(hl)
    img.alpha_composite(layer.resize((SIZE, SIZE), Image.LANCZOS))


# ------------------------------------------------------------------ mutation badges (vector glyphs)
def g_bolt(dr, S):
    pts = [(0.56, 0.16), (0.32, 0.55), (0.47, 0.55), (0.40, 0.86), (0.70, 0.44), (0.54, 0.44)]
    dr.polygon([(x * S, y * S) for x, y in pts], fill=(255, 242, 130, 255), outline=(125, 85, 0, 255), width=int(S * 0.014))


def g_spiral(dr, S):
    cx, cy = S * 0.5, S * 0.5
    for i in range(3):
        for t in range(0, 190, 5):
            ang = math.radians(i * 120 + t)
            r = S * (0.09 + 0.0017 * t)
            w = int(S * (0.028 + 0.00025 * (190 - t)))
            x, y = cx + r * math.cos(ang), cy + r * math.sin(ang)
            dr.ellipse((x - w, y - w, x + w, y + w), fill=(238, 255, 250, 255))
    dr.ellipse((cx - S * 0.07, cy - S * 0.07, cx + S * 0.07, cy + S * 0.07), fill=(255, 255, 255, 255))


def g_moon(dr, S):
    dr.ellipse((S * 0.22, S * 0.22, S * 0.78, S * 0.78), fill=(255, 92, 92, 255), outline=(112, 10, 22, 255), width=int(S * 0.012))
    for cx, cy, r in ((0.40, 0.40, 0.06), (0.58, 0.55, 0.045), (0.47, 0.64, 0.035)):
        dr.ellipse(((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S), fill=(205, 42, 52, 255))
    dr.ellipse((S * 0.30, S * 0.28, S * 0.46, S * 0.40), fill=(255, 172, 162, 160))


def g_aurora(dr, S):
    for i, c in enumerate(((80, 255, 170), (120, 220, 255), (190, 110, 255))):
        top = [(S * (0.18 + 0.64 * k / 20), S * (0.40 + i * 0.12 + 0.06 * math.sin(k * 0.9 + i))) for k in range(21)]
        bot = [(x, y + S * 0.09) for x, y in reversed(top)]
        dr.polygon(top + bot, fill=c + (235,))
    for x, y in ((0.3, 0.28), (0.5, 0.22), (0.7, 0.3), (0.62, 0.78), (0.36, 0.8)):
        dr.ellipse(((x - 0.016) * S, (y - 0.016) * S, (x + 0.016) * S, (y + 0.016) * S), fill=(255, 255, 255, 255))


def g_coin(dr, S):
    for dx, dy in ((0.07, 0.06), (0.035, 0.03), (0, 0)):
        dr.ellipse(((0.26 + dx) * S, (0.28 + dy) * S, (0.74 + dx) * S, (0.76 + dy) * S), fill=(255, 208, 62, 255),
                   outline=(152, 96, 10, 255), width=int(S * 0.012))
    dr.ellipse((S * 0.33, S * 0.35, S * 0.67, S * 0.69), outline=(202, 142, 22, 255), width=int(S * 0.02))
    dr.text((S * 0.5, S * 0.52), "P", font=ImageFont.truetype(FONT_BOLD, int(S * 0.22)), fill=(172, 112, 10, 255), anchor="mm")


def g_rainbow(dr, S):
    for i, c in enumerate(((255, 60, 60), (255, 160, 40), (255, 235, 60), (70, 220, 90), (60, 150, 255), (170, 80, 255))):
        r = S * (0.37 - i * 0.045)
        dr.arc((S * 0.5 - r, S * 0.64 - r, S * 0.5 + r, S * 0.64 + r), 200, 340, fill=c + (255,), width=int(S * 0.046))
    for x in (0.25, 0.75):
        dr.ellipse(((x - 0.085) * S, S * 0.62, (x + 0.085) * S, S * 0.74), fill=(255, 255, 255, 235))


def g_eclipse(dr, S):
    for k in range(12):
        a = math.radians(k * 30)
        dr.line((S * (0.5 + 0.33 * math.cos(a)), S * (0.5 + 0.33 * math.sin(a)), S * (0.5 + 0.44 * math.cos(a)),
                 S * (0.5 + 0.44 * math.sin(a))), fill=(255, 212, 92, 210), width=int(S * 0.022))
    dr.ellipse((S * 0.20, S * 0.20, S * 0.80, S * 0.80), fill=(255, 192, 62, 255))
    dr.ellipse((S * 0.25, S * 0.25, S * 0.75, S * 0.75), fill=(255, 232, 152, 255))
    dr.ellipse((S * 0.265, S * 0.265, S * 0.735, S * 0.735), fill=(26, 16, 36, 255))


def g_bakunawa(dr, S):
    dr.ellipse((S * 0.30, S * 0.16, S * 0.74, S * 0.60), fill=(232, 228, 255, 255), outline=(122, 102, 182, 255), width=int(S * 0.01))
    body = [(0.14, 0.82), (0.20, 0.60), (0.32, 0.48), (0.46, 0.44), (0.62, 0.50), (0.74, 0.66), (0.64, 0.72), (0.52, 0.60),
            (0.44, 0.60), (0.34, 0.66), (0.30, 0.84)]
    dr.polygon([(x * S, y * S) for x, y in body], fill=(62, 22, 112, 255), outline=(112, 242, 255, 255), width=int(S * 0.012))
    for x, y in ((0.36, 0.50), (0.44, 0.46), (0.52, 0.48), (0.60, 0.54)):
        dr.polygon([(x * S, y * S), ((x + 0.04) * S, y * S), ((x + 0.02) * S, (y - 0.06) * S)], fill=(232, 250, 255, 255))
    dr.ellipse((S * 0.54, S * 0.56, S * 0.60, S * 0.62), fill=(112, 242, 255, 255))
    for k in range(3):
        x = 0.24 + k * 0.1
        dr.polygon([(x * S, 0.64 * S), ((x + 0.05) * S, 0.66 * S), ((x + 0.01) * S, 0.76 * S)], fill=(255, 202, 72, 255))


BADGES = {
    "thunderstorm": ((60, 140, 240), (222, 242, 255), g_bolt), "typhoon": ((35, 172, 162), (202, 255, 246), g_spiral),
    "blood_moon": ((152, 22, 42), (255, 172, 172), g_moon), "aurora": ((30, 62, 112), (172, 255, 222), g_aurora),
    "golden_tide": ((226, 162, 32), (255, 246, 202), g_coin), "rainbow_bloom": ((242, 112, 192), (255, 242, 255), g_rainbow),
    "solar_eclipse": ((72, 46, 92), (255, 202, 92), g_eclipse), "bakunawa_eclipse": ((46, 16, 92), (112, 242, 255), g_bakunawa),
}


def badge(mutation_id, size):
    S = size * 4
    col, acc, draw = BADGES[mutation_id]
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = S * 0.06
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((m, m + S * 0.03, S - m, S - m + S * 0.03), fill=(0, 0, 0, 150))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(S * 0.02)))
    yy, xx = (np.mgrid[0:S, 0:S] / S).astype(np.float32)
    d = np.sqrt((xx - 0.42) ** 2 + (yy - 0.38) ** 2)
    c = np.array(col, np.float32) / 255
    k = np.clip(1 - d / 0.45, 0, 1)[..., None] ** 1.2
    disc = np.clip(c * 0.6 + 0.4, 0, 1) * k + c * (1 - k)
    k2 = np.clip((d - 0.3) / 0.25, 0, 1)[..., None]
    disc = disc * (1 - 0.5 * k2) + c * 0.45 * (0.5 * k2)
    disc_img = np_img(disc).convert("RGBA")
    mask = Image.new("L", (S, S))
    ImageDraw.Draw(mask).ellipse((m, m, S - m, S - m), fill=255)
    disc_img.putalpha(mask)
    img.alpha_composite(disc_img)
    dr = ImageDraw.Draw(img)
    dr.ellipse((m, m, S - m, S - m), outline=tuple(int(v * 0.5) for v in col) + (255,), width=int(S * 0.03))
    dr.ellipse((m + S * 0.03, m + S * 0.03, S - m - S * 0.03, S - m - S * 0.03), outline=acc + (150,), width=int(S * 0.012))
    draw(dr, S)
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse((S * 0.14, S * 0.08, S * 0.86, S * 0.5), fill=(255, 255, 255, 55))
    gloss.putalpha(ImageChops.multiply(gloss.getchannel("A"), mask))
    img.alpha_composite(gloss)
    return img.resize((size, size), Image.LANCZOS)


# ------------------------------------------------------------------ main
def build(item, cat, tex, seed):
    view = VIEW_OVERRIDE.get(item["id"], VIEW[cat])
    if cat in D.MODEL_CATEGORIES:
        mesh = ObjMesh(os.path.join(MODELS, item["id"] + ".obj"))
        t = tex["fish"] if cat == "Fish" else tex["props"]
    else:
        mesh, t = OLD.shop_mesh(item), tex["props"]
    img, sh, pos = item_layer(mesh, t, view)
    icon = compose(item, img, sh, pos, background(item["rarity"], seed))
    if item["id"] in SHOP_LABEL:
        text, color = SHOP_LABEL[item["id"]]
        label(icon, text, 88 if len(text) <= 2 else 66, INNER + 6, color)
    draw_stars(icon, D.RARITY_BY_NAME[item["rarity"]]["order"])
    return icon, item_only(img, sh, pos)


def contact_sheet(paths, out_path, cell=128, cols=9):
    rows = math.ceil(len(paths) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (44, 46, 54, 255))
    for k, p in enumerate(paths):
        sheet.alpha_composite(Image.open(p).convert("RGBA").resize((cell, cell), Image.LANCZOS), ((k % cols) * cell, (k // cols) * cell))
    sheet.save(out_path)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    test = "--test" in sys.argv
    tex = dict(fish=load_tex("fish_atlas.png"), props=load_tex("props_atlas.png"))
    items = list(D.all_items())
    if test:
        want = ["fish_bangus", "net_bamboo_rod", "tank_aquarium", "lock_guard_dog_statue", "boost_luck_potion",
                "hat_salakot", "dp_cash_large", "fish_alimasag"]
        items = [(c, it) for c, it in items if it["id"] in want]
        out_dir = "/tmp/icontest"
    else:
        if args:
            items = [(c, it) for c, it in items if it["id"] in args]
        out_dir = OUT
        os.makedirs(OUT_ITEM, exist_ok=True)
        os.makedirs(OUT_BADGE, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)
    index = {it["id"]: k for k, (_, it) in enumerate(D.all_items())}
    for cat, item in items:
        icon, only = build(item, cat, tex, seed=index[item["id"]] * 7 + 1)
        icon.save(os.path.join(out_dir, item["id"] + ".png"), optimize=True)
        if not test:
            only.save(os.path.join(OUT_ITEM, item["id"] + ".png"), optimize=True)
        print("icon", item["id"], flush=True)
    if test:
        paths = [os.path.join(out_dir, it["id"] + ".png") for _, it in items]
        contact_sheet(paths, "/tmp/icontest/contact_128.png")
        contact_sheet(paths, "/tmp/icontest/contact_512.png", cell=512, cols=4)
        return
    if not args:
        for mid in MUTATIONS:
            badge(mid, 512).save(os.path.join(OUT_BADGE, f"{mid}_512.png"), optimize=True)
            badge(mid, 128).save(os.path.join(OUT_BADGE, f"{mid}_128.png"), optimize=True)
        print("badges", len(MUTATIONS))
    paths = [os.path.join(OUT, it["id"] + ".png") for _, it in D.all_items()]
    paths += [os.path.join(OUT_BADGE, f"{mid}_128.png") for mid in MUTATIONS]
    contact_sheet(paths, os.path.join(OUT, "_contact_sheet.png"))


if __name__ == "__main__":
    main()
