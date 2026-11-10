"""Monte-Carlo progression check for EconomyBalance (no boosts, no gamepasses, no stealing).

Player model: casts nonstop at `efficiency` (0.6 = 40% of time spent walking/stealing/idle),
keeps the best fish in the tank, sells the rest, greedily buys the cheapest next net/tank,
and rebirths when the rebirth costs less than the next upgrade (or everything is owned).
Rebirth resets cash + fish, keeps nets/tanks/locks/cosmetics.

python tools/items/balance_sim.py  -> prints milestone medians and writes items/balance_table.json
"""
import json
import os
import random
import statistics

import item_data as D

RAR = D.RARITIES
FISH_BY_RAR = {r["name"]: [f for f in D.FISH if f["rarity"] == r["name"]] for r in RAR}


def roll(rng, luck):
    weights = [r["weight"] * (1 + luck) ** r["luckExponent"] for r in RAR]
    rar = rng.choices(RAR, weights)[0]["name"]
    pool = FISH_BY_RAR[rar]
    f = rng.choices(pool, [p["catchWeight"] for p in pool])[0]
    frac = rng.random()
    return f, f["cashPerSecond"] * (1 + D.WEIGHT_BONUS_MAX * frac)


def rebirth_cost(r):
    return D.nice(D.REBIRTH_BASE_COST * D.REBIRTH_COST_GROWTH ** r)


def simulate(seed, hours=12.0, efficiency=0.6):
    rng = random.Random(seed)
    t = cash = 0.0
    net = tank = 1
    reb = 0
    fish = []
    ms = {}
    hourly = []
    next_hour = 3600
    while t < hours * 3600:
        n = D.NETS[net - 1]
        tk = D.TANKS[tank - 1]
        dt = D.BASE_CAST_SECONDS / n["catchSpeed"] / efficiency
        inc = sum(fish) * tk["incomeMultiplier"] * (1 + D.REBIRTH_INCOME_BONUS * reb)
        t += dt
        cash += inc * dt
        while t >= next_hour:
            hourly.append(dict(hour=next_hour // 3600, net=net, tank=tank, rebirths=reb, income=round(inc)))
            next_hour += 3600
        f, cps = roll(rng, n["luck"] + D.REBIRTH_LUCK_BONUS * reb)
        key = "first_" + f["rarity"]
        ms.setdefault(key, t)
        if len(fish) < tk["capacity"]:
            fish.append(cps)
        elif cps > min(fish):
            lo = min(fish)
            fish.remove(lo)
            fish.append(cps)
            cash += lo * D.SELL_SECONDS
        else:
            cash += cps * D.SELL_SECONDS
        while True:
            opts = []
            if net < 8:
                opts.append(("net", D.NETS[net]["price"]))
            if tank < 6:
                opts.append(("tank", D.TANKS[tank]["price"]))
            opts.sort(key=lambda o: o[1])
            rc = rebirth_cost(reb)
            if opts and cash >= opts[0][1]:
                cash -= opts[0][1]
                if opts[0][0] == "net":
                    net += 1
                    ms[f"net_{net}"] = t
                else:
                    tank += 1
                    ms[f"tank_{tank}"] = t
            elif (not opts or rc < opts[0][1]) and cash >= rc:
                reb += 1
                ms[f"rebirth_{reb}"] = t
                cash = 0
                fish = []
            else:
                break
    return ms, hourly


def main():
    runs = [simulate(s) for s in range(40)]
    keys = sorted({k for ms, _ in runs for k in ms}, key=lambda k: statistics.median(
        [ms.get(k, 1e9) for ms, _ in runs]))
    out = {}
    for k in keys:
        vals = [ms[k] / 3600 for ms, _ in runs if k in ms]
        out[k] = dict(medianHours=round(statistics.median(vals), 2), reachedPct=round(100 * len(vals) / len(runs)))
        print(f"{k:16s} median {out[k]['medianHours']:6.2f} h  reached {out[k]['reachedPct']:3d}%")
    hourly = []
    for h in range(12):
        rows = [hr[h] for _, hr in runs if len(hr) > h]
        hourly.append(dict(hour=h + 1,
                           net=int(statistics.median(r["net"] for r in rows)),
                           tank=int(statistics.median(r["tank"] for r in rows)),
                           rebirths=int(statistics.median(r["rebirths"] for r in rows)),
                           incomePerSecond=int(statistics.median(r["income"] for r in rows))))
        print(hourly[-1])
    with open(os.path.join(D.ROOT, "items", "balance_table.json"), "w") as fh:
        json.dump(dict(milestones=out, hourly=hourly, rebirthCosts=[rebirth_cost(r) for r in range(6)]), fh, indent=1)


if __name__ == "__main__":
    main()
