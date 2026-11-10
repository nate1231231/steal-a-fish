"""Fill the <!-- AUTO:name --> ... <!-- /AUTO:name --> sections of ITEMS_MANIFEST.md.

python tools/items/manifest_tables.py
"""
import glob
import json
import os
import re

import item_data as D

MAN = os.path.join(D.ROOT, "ITEMS_MANIFEST.md")


def tri_count(path):
    with open(path) as fh:
        return sum(1 for ln in fh if ln.startswith("f "))


def fmt(n):
    return f"{n:,}"


def sec_ids():
    rows = ["| # | Category | Item ID | Name | Rarity | Key stats | Price |", "|---|---|---|---|---|---|---|"]
    i = 0
    for cat, it in D.all_items():
        i += 1
        if cat == "Fish":
            stats = (f"{it['cashPerSecond']}/s, sell {fmt(it['sellValue'])}, {it['weightKg'][0]}-{it['weightKg'][1]} kg, "
                     f"{it['catchChance']}% base, size x{it['sizeScale']}, body `{it['bodyVariant']}`")
            price = "-"
        elif cat == "Net":
            stats, price = f"tier {it['tier']}, speed x{it['catchSpeed']}, luck +{it['luck']}", fmt(it["price"])
        elif cat == "Tank":
            stats, price = f"tier {it['tier']}, {it['capacity']} slots, income x{it['incomeMultiplier']}", fmt(it["price"])
        elif cat == "Lock":
            stats, price = f"difficulty {it['stealDifficulty']}, +{it['extraStealSeconds']}s steal", fmt(it["price"])
        elif cat == "Boost":
            stats = f"{it['durationSeconds']}s, {', '.join(f'{k}={v}' for k, v in it['effect'].items())}"
            price = f"{it['priceSecondsOfIncome']}s of income (min {fmt(it['minPrice'])})"
        elif cat in ("BangkaSkin", "Hat"):
            stats, price = "cosmetic", fmt(it["price"])
        elif cat == "GamePass":
            stats, price = f"gamePassId {it['gamePassId']} (placeholder)", f"R$ {it['robux']}"
        else:
            stats = f"productId {it['productId']} (placeholder), {it['cashSecondsOfIncome']}s income"
            price = f"R$ {it['robux']}"
        rows.append(f"| {i} | {cat} | `{it['id']}` | {it['name']} | {it['rarity']} | {stats} | {price} |")
    return "\n".join(rows)


def sec_models():
    files = sorted(glob.glob(os.path.join(D.ROOT, "items", "models", "*.obj")))
    if not files:
        return "_Pending (phase 2/3)._"
    rows = ["| File | Triangles | Bounds X x Y x Z (studs) |", "|---|---|---|"]
    total = 0
    rep = {}
    rp = os.path.join(D.ROOT, "items", "models", "_model_report.json")
    if os.path.exists(rp):
        rep = json.load(open(rp))
    for f in files:
        n = tri_count(f)
        total += n
        b = rep.get(os.path.basename(f)[:-4], {}).get("size")
        bs = " x ".join(f"{v:.2f}" for v in b) if b else "-"
        rows.append(f"| `items/models/{os.path.basename(f)}` | {fmt(n)} | {bs} |")
    rows.append(f"| **{len(files)} models** | **{fmt(total)} total**, max {fmt(max(tri_count(f) for f in files))} | |")
    return "\n".join(rows)


def sec_files():
    out = []
    for sub, label in (("textures", "Textures"), ("icons", "Icons")):
        fs = sorted(glob.glob(os.path.join(D.ROOT, "items", sub, "*.png")))
        out.append(f"**{label}** ({len(fs)} files): " + (", ".join(f"`{os.path.basename(f)}`" for f in fs) or "_pending_"))
    fs = sorted(glob.glob(os.path.join(D.ROOT, "studio", "items", "*.luau")))
    out.append(f"**Luau** ({len(fs)} files): " + (", ".join(f"`{os.path.basename(f)}`" for f in fs) or "_pending_"))
    return "\n\n".join(out)


def sec_balance():
    p = os.path.join(D.ROOT, "items", "balance_table.json")
    if not os.path.exists(p):
        return "_Pending._"
    b = json.load(open(p))
    rows = ["| Hour | Best net (tier) | Best tank (tier) | Rebirths | Income / s (median) |", "|---|---|---|---|---|"]
    for h in b["hourly"][:10]:
        rows.append(f"| {h['hour']} | {D.NETS[h['net'] - 1]['name']} ({h['net']}) | {D.TANKS[h['tank'] - 1]['name']} "
                    f"({h['tank']}) | {h['rebirths']} | {fmt(h['incomePerSecond'])} |")
    ms = ", ".join(f"{k} {v['medianHours']} h" for k, v in b["milestones"].items()
                   if k.startswith(("first_", "rebirth_")) or k in ("net_8", "tank_6"))
    return "\n".join(rows) + f"\n\nMilestones (median of 40 simulated players): {ms}."


SECTIONS = dict(ids=sec_ids, models=sec_models, files=sec_files, balance=sec_balance)


def main():
    text = open(MAN).read()
    for name, fn in SECTIONS.items():
        pat = re.compile(rf"(<!-- AUTO:{name} -->)\n?.*?\n?(<!-- /AUTO:{name} -->)", re.S)
        text = pat.sub(lambda m: m.group(1) + "\n" + fn() + "\n" + m.group(2), text)
    open(MAN, "w").write(text)
    print("manifest tables updated")


if __name__ == "__main__":
    main()
