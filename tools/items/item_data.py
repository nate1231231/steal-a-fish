"""Single source of truth for every Steal a Fish item.

Run:  python tools/items/item_data.py  -> writes items/item_data.json
Mesh, icon and Luau generators all import this module, so ids/prices stay in sync.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
STUD_METERS = 0.28            # scale rule from the prompt: 1 stud = 0.28 m
FISH_BASE_LENGTH = 2.0        # studs; every fish OBJ is baked at this length, game applies sizeScale

# ---------------------------------------------------------------- economy constants
BASE_CAST_SECONDS = 10.0      # seconds per catch with catchSpeed 1.0
SELL_SECONDS = 30             # sell value = cashPerSecond * SELL_SECONDS
WEIGHT_BONUS_MAX = 0.25       # heaviest roll in a species' range earns +25% income
REBIRTH_BASE_COST = 10_000_000
REBIRTH_COST_GROWTH = 5.0
REBIRTH_INCOME_BONUS = 0.5    # +50% income per rebirth
REBIRTH_LUCK_BONUS = 0.1
NET_PRICE_BASE, NET_PRICE_GROWTH = 800, 9.5      # tier 2 price, x per tier
TANK_PRICE_BASE, TANK_PRICE_GROWTH = 2_500, 13.0


def nice(x):
    """Round to 2 significant digits so prices read cleanly (12,345 -> 12,000)."""
    if x <= 0:
        return 0
    digits = len(str(int(x))) - 2
    step = 10 ** max(digits, 0)
    return int(round(x / step) * step)


def tier_price(base, growth, tier):
    return 0 if tier == 1 else nice(base * growth ** (tier - 2))


RARITIES = [
    # name, color, base roll weight, luck exponent (higher = luck helps more), stars
    dict(name="Common", order=1, color=[154, 165, 177], weight=75.0, luckExponent=0.0),
    dict(name="Rare", order=2, color=[59, 130, 246], weight=20.0, luckExponent=0.5),
    dict(name="Epic", order=3, color=[168, 85, 247], weight=2.5, luckExponent=1.0),
    dict(name="Legendary", order=4, color=[245, 158, 11], weight=0.3, luckExponent=1.5),
    dict(name="Mythic", order=5, color=[239, 68, 68], weight=0.012, luckExponent=2.0),
]
RARITY_BY_NAME = {r["name"]: r for r in RARITIES}

# ---------------------------------------------------------------- fish
# visual: body variant + shape/texture params consumed by gen_fish.py
#   variants: slender, deep, tuna, squid, crab  (5 shared base shapes)
#   colors are RGB 0-255: back, belly, fin, accent
F = lambda **k: k  # noqa: E731
FISH = [
    # ---- Common
    F(id="fish_dilis", name="Dilis", englishName="Anchovy", rarity="Common", cashPerSecond=1,
      weightKg=[0.005, 0.02], catchWeight=30, sizeScale=0.55,
      description="Tiny but everywhere. Every fisher starts with dilis.",
      visual=dict(variant="slender", ratio=6.2, back=[120, 150, 165], belly=[225, 232, 236], fin=[200, 210, 215],
                  accent=[235, 240, 245], pattern="hstripe")),
    F(id="fish_tamban", name="Tamban", englishName="Sardine", rarity="Common", cashPerSecond=2,
      weightKg=[0.04, 0.12], catchWeight=26, sizeScale=0.65,
      description="Canned, fried or dried, tamban feeds the whole barangay.",
      visual=dict(variant="slender", ratio=5.2, back=[40, 92, 122], belly=[222, 228, 232], fin=[170, 185, 190],
                  accent=[30, 45, 60], pattern="spotrow")),
    F(id="fish_galunggong", name="Galunggong", englishName="Round Scad", rarity="Common", cashPerSecond=3,
      weightKg=[0.1, 0.35], catchWeight=24, sizeScale=0.75,
      description="The people's fish. GG for short.",
      visual=dict(variant="slender", ratio=4.6, back=[70, 100, 140], belly=[215, 222, 230], fin=[205, 170, 120],
                  accent=[40, 50, 70], pattern="gillspot")),
    F(id="fish_sapsap", name="Sapsap", englishName="Ponyfish", rarity="Common", cashPerSecond=3,
      weightKg=[0.03, 0.12], catchWeight=20, sizeScale=0.6,
      description="Shiny, slippery and perfect for paksiw.",
      visual=dict(variant="deep", ratio=2.1, back=[160, 175, 185], belly=[238, 240, 242], fin=[235, 215, 120],
                  accent=[120, 135, 150], pattern="wavy")),
    F(id="fish_tilapia", name="Tilapia", englishName="Tilapia", rarity="Common", cashPerSecond=4,
      weightKg=[0.2, 1.2], catchWeight=20, sizeScale=0.9,
      description="Fishpond favorite, great inihaw.",
      visual=dict(variant="deep", ratio=2.6, back=[105, 118, 98], belly=[205, 205, 185], fin=[190, 110, 95],
                  accent=[80, 90, 75], pattern="vbars")),
    F(id="fish_hito", name="Hito", englishName="Catfish", rarity="Common", cashPerSecond=5,
      weightKg=[0.3, 2.0], catchWeight=14, sizeScale=1.0,
      description="Whiskered mud-lover. Best with burong mangga.",
      visual=dict(variant="slender", ratio=5.6, tail="round", whiskers=True, back=[72, 66, 60],
                  belly=[150, 140, 122], fin=[60, 55, 50], accent=[45, 40, 36], pattern="mottled")),
    F(id="fish_bangus", name="Bangus", englishName="Milkfish", rarity="Common", cashPerSecond=6,
      weightKg=[0.3, 1.8], catchWeight=12, sizeScale=1.1,
      description="The national fish of the Philippines.",
      visual=dict(variant="slender", ratio=4.6, back=[88, 120, 142], belly=[236, 239, 242], fin=[120, 135, 150],
                  accent=[200, 212, 222], pattern="scales")),
    # ---- Rare
    F(id="fish_alumahan", name="Alumahan", englishName="Indian Mackerel", rarity="Rare", cashPerSecond=12,
      weightKg=[0.1, 0.4], catchWeight=26, sizeScale=0.9,
      description="Striped speedster, loves sinigang.",
      visual=dict(variant="slender", ratio=4.8, back=[60, 120, 110], belly=[230, 228, 200], fin=[210, 190, 90],
                  accent=[25, 55, 55], pattern="wavy")),
    F(id="fish_dalagang_bukid", name="Dalagang Bukid", englishName="Redbelly Fusilier", rarity="Rare",
      cashPerSecond=15, weightKg=[0.2, 0.8], catchWeight=22, sizeScale=0.9,
      description="The 'country maiden' with a bright yellow tail.",
      visual=dict(variant="slender", ratio=4.4, back=[45, 95, 190], belly=[235, 130, 150], fin=[250, 210, 40],
                  accent=[250, 215, 50], pattern="hstripe")),
    F(id="fish_pusit", name="Pusit", englishName="Squid", rarity="Rare", cashPerSecond=18,
      weightKg=[0.1, 0.8], catchWeight=20, sizeScale=0.9,
      description="Inky escape artist. Adobong pusit, anyone?",
      visual=dict(variant="squid", back=[232, 196, 190], belly=[245, 230, 226], fin=[225, 180, 172],
                  accent=[160, 70, 60], pattern="spots")),
    F(id="fish_bisugo", name="Bisugo", englishName="Threadfin Bream", rarity="Rare", cashPerSecond=20,
      weightKg=[0.15, 0.6], catchWeight=16, sizeScale=0.9,
      description="Pink with golden stripes, a fried-fish classic.",
      visual=dict(variant="deep", ratio=2.9, back=[228, 130, 150], belly=[245, 220, 222], fin=[245, 205, 110],
                  accent=[250, 215, 80], pattern="hlines")),
    F(id="fish_alimasag", name="Alimasag", englishName="Blue Swimming Crab", rarity="Rare", cashPerSecond=24,
      weightKg=[0.15, 0.5], catchWeight=14, sizeScale=0.8,
      description="Blue-clawed and sideways. Watch your fingers.",
      visual=dict(variant="crab", back=[60, 92, 175], belly=[220, 225, 240], fin=[80, 120, 200],
                  accent=[235, 240, 250], tips=[150, 50, 90], pattern="crabspots")),
    F(id="fish_talakitok", name="Talakitok", englishName="Giant Trevally", rarity="Rare", cashPerSecond=30,
      weightKg=[1.0, 8.0], catchWeight=10, sizeScale=1.3,
      description="A reef bully with serious pulling power.",
      visual=dict(variant="deep", ratio=2.5, back=[88, 96, 104], belly=[210, 214, 218], fin=[45, 50, 58],
                  accent=[30, 32, 36], pattern="spots")),
    # ---- Epic
    F(id="fish_mameng", name="Mameng", englishName="Parrotfish", rarity="Epic", cashPerSecond=70,
      weightKg=[1.0, 5.0], catchWeight=24, sizeScale=1.3,
      description="Crunches coral and poops sand. Respect.",
      visual=dict(variant="deep", ratio=2.7, tail="square", back=[30, 170, 145], belly=[120, 220, 190],
                  fin=[240, 130, 100], accent=[245, 140, 110], pattern="scales")),
    F(id="fish_tanigue", name="Tanigue", englishName="Spanish Mackerel", rarity="Epic", cashPerSecond=90,
      weightKg=[3.0, 15.0], catchWeight=22, sizeScale=1.6,
      description="Kinilaw royalty. Fast and toothy.",
      visual=dict(variant="slender", ratio=6.0, back=[60, 85, 120], belly=[225, 230, 236], fin=[70, 80, 95],
                  accent=[40, 55, 80], pattern="vbars")),
    F(id="fish_maya_maya", name="Maya-Maya", englishName="Red Snapper", rarity="Epic", cashPerSecond=110,
      weightKg=[1.0, 10.0], catchWeight=20, sizeScale=1.4,
      description="Bright red and fancy. Steamed with ginger.",
      visual=dict(variant="deep", ratio=2.6, back=[215, 55, 55], belly=[245, 160, 150], fin=[225, 70, 70],
                  accent=[255, 200, 190], pattern="gradient")),
    F(id="fish_alimango", name="Alimango", englishName="Mud Crab", rarity="Epic", cashPerSecond=130,
      weightKg=[0.5, 2.5], catchWeight=18, sizeScale=1.1,
      description="Giant claws, bad attitude, amazing with chili.",
      visual=dict(variant="crab", back=[72, 82, 50], belly=[190, 175, 120], fin=[95, 100, 60],
                  accent=[110, 120, 70], tips=[230, 120, 40], pattern="mottled")),
    F(id="fish_lapu_lapu", name="Lapu-Lapu", englishName="Coral Grouper", rarity="Epic", cashPerSecond=160,
      weightKg=[2.0, 20.0], catchWeight=16, sizeScale=1.6,
      description="Named after the hero of Mactan. Red with blue spots.",
      visual=dict(variant="deep", ratio=3.0, tail="round", back=[200, 45, 45], belly=[235, 110, 95],
                  fin=[190, 40, 45], accent=[70, 170, 255], pattern="spots")),
    # ---- Legendary
    F(id="fish_tuna", name="Tuna (Tambakol)", englishName="Yellowfin Tuna", rarity="Legendary", cashPerSecond=450,
      weightKg=[20.0, 150.0], catchWeight=34, sizeScale=2.0,
      description="General Santos City's pride. Pure muscle.",
      visual=dict(variant="tuna", ratio=3.6, back=[22, 40, 92], belly=[226, 232, 240], fin=[250, 205, 30],
                  accent=[250, 210, 40], pattern="hstripe", finlets=True)),
    F(id="fish_pating", name="Pating", englishName="Blacktip Reef Shark", rarity="Legendary", cashPerSecond=600,
      weightKg=[10.0, 60.0], catchWeight=28, sizeScale=2.4,
      description="Steal this one quietly.",
      visual=dict(variant="tuna", ratio=5.0, tail="shark", dorsal="shark", back=[112, 122, 132],
                  belly=[236, 238, 240], fin=[112, 122, 132], accent=[20, 22, 26], pattern="gradient")),
    F(id="fish_pusit_higante", name="Pusit Higante", englishName="Giant Squid", rarity="Legendary",
      cashPerSecond=750, weightKg=[50.0, 250.0], catchWeight=22, sizeScale=2.6,
      description="Legends say it once ate a whole bangka.",
      visual=dict(variant="squid", back=[200, 70, 50], belly=[240, 160, 130], fin=[185, 60, 45],
                  accent=[120, 30, 25], pattern="spots")),
    F(id="fish_malasugi", name="Malasugi", englishName="Blue Marlin", rarity="Legendary", cashPerSecond=900,
      weightKg=[50.0, 400.0], catchWeight=16, sizeScale=2.8,
      description="The spear of the deep. A once-in-a-lifetime catch.",
      visual=dict(variant="tuna", ratio=5.4, bill=True, dorsal="sail", tail="crescent", back=[20, 60, 150],
                  belly=[226, 232, 242], fin=[30, 80, 170], accent=[120, 190, 255], pattern="vbars")),
    # ---- Mythic (fantasy)
    F(id="fish_diwata", name="Diwatang Isda", englishName="Spirit Fairy Fish", rarity="Mythic",
      cashPerSecond=2500, weightKg=[5.0, 30.0], catchWeight=65, sizeScale=2.4,
      description="A diwata's guardian fish. Glows under the full moon.",
      visual=dict(variant="deep", ratio=2.3, tail="veil", longFins=True, back=[120, 220, 240],
                  belly=[255, 190, 230], fin=[255, 170, 225], accent=[255, 240, 160], pattern="iridescent")),
    F(id="fish_bakunawa", name="Bakunawa", englishName="Moon-Eater Sea Serpent", rarity="Mythic",
      cashPerSecond=5000, weightKg=[500.0, 2000.0], catchWeight=35, sizeScale=3.0,
      description="The sea dragon that tried to swallow the moon.",
      visual=dict(variant="slender", ratio=7.5, tail="long", crest=True, horns=True, whiskers=True,
                  back=[45, 25, 100], belly=[235, 185, 60], fin=[240, 190, 60], accent=[90, 230, 255],
                  pattern="dragon")),
]

# ---------------------------------------------------------------- nets / rods (8 tiers)
_NETS = [
    ("net_basic", "Basic Net (Lambat)", "hand_net", 1.0, 0.0, "Common", "A patched-up hand net. It works... mostly."),
    ("net_bamboo_rod", "Bamboo Rod (Bingwit)", "rod", 1.15, 0.15, "Common", "Lolo's trusty bamboo pole."),
    ("net_pukot", "Pukot Net", "hand_net", 1.3, 0.35, "Rare", "A proper nylon net for bigger schools."),
    ("net_fiberglass_rod", "Fiberglass Rod", "rod", 1.5, 0.6, "Rare", "Light, bendy and surprisingly lucky."),
    ("net_sapyaw", "Sapyaw Net", "hand_net", 1.75, 0.9, "Epic", "Wide-mouth scoop net used on night boats."),
    ("net_steel_reel", "Steel Reel Rod", "rod", 2.0, 1.3, "Epic", "Heavy reel for heavy fish."),
    ("net_diamond", "Diamond Net", "hand_net", 2.4, 1.8, "Legendary", "Woven with crystal thread. Fish love shiny."),
    ("net_golden_trawl", "Golden Trawl Net", "trawl", 3.0, 2.5, "Mythic", "The ultimate net. Even the Bakunawa fears it."),
]
NETS = [dict(id=i, name=n, style=s, tier=t + 1, catchSpeed=cs, luck=lk, rarity=r, description=d,
             price=tier_price(NET_PRICE_BASE, NET_PRICE_GROWTH, t + 1))
        for t, (i, n, s, cs, lk, r, d) in enumerate(_NETS)]

# ---------------------------------------------------------------- tanks (6 tiers)
_TANKS = [
    ("tank_balde", "Balde (Bucket)", 3, 1.0, "Common", "A plastic bucket. Humble beginnings."),
    ("tank_banyera", "Banyera (Fish Tub)", 5, 1.1, "Common", "The wet-market classic."),
    ("tank_aquarium", "Glass Aquarium", 7, 1.25, "Rare", "Show off your catch."),
    ("tank_palaisdaan", "Palaisdaan (Fish Pond)", 9, 1.5, "Epic", "Your own backyard fishpond."),
    ("tank_coral_reef", "Coral Reef Tank", 12, 1.75, "Legendary", "A living reef. Fish grow happier (and richer)."),
    ("tank_ocean_dome", "Ocean Dome", 15, 2.0, "Mythic", "A piece of the ocean under a golden dome."),
]
TANKS = [dict(id=i, name=n, tier=t + 1, capacity=c, incomeMultiplier=m, rarity=r, description=d,
              price=tier_price(TANK_PRICE_BASE, TANK_PRICE_GROWTH, t + 1))
         for t, (i, n, c, m, r, d) in enumerate(_TANKS)]

# ---------------------------------------------------------------- base locks & defenses
LOCKS = [
    dict(id="lock_padlock", name="Padlock (Kandado)", tier=1, rarity="Common", stealDifficulty=1, price=2_500,
         extraStealSeconds=2, description="Adds a little extra time to every steal."),
    dict(id="lock_chain_gate", name="Chain Gate", tier=2, rarity="Rare", stealDifficulty=2, price=25_000,
         extraStealSeconds=4, description="Heavy chains slow thieves at your door."),
    dict(id="lock_alarm_bell", name="Alarm Bell (Kampana)", tier=3, rarity="Epic", stealDifficulty=3, price=250_000,
         extraStealSeconds=3, alertsOwner=True, thiefSlowPercent=25, thiefSlowSeconds=5,
         description="Rings when someone grabs a fish and slows the thief."),
    dict(id="lock_laser_fence", name="Laser Fence", tier=4, rarity="Legendary", stealDifficulty=4,
         price=2_500_000, extraStealSeconds=5, lockSeconds=30, cooldownSeconds=90,
         description="Activate to block your base completely for 30 seconds."),
    dict(id="lock_guard_dog_statue", name="Guard Dog Statue (Bantay)", tier=5, rarity="Mythic", stealDifficulty=5,
         price=25_000_000, extraStealSeconds=6, knockbackStuds=25, cooldownSeconds=45,
         description="Bantay comes alive and knocks thieves back."),
]

# ---------------------------------------------------------------- boosts (price scales with your income)
BOOSTS = [
    dict(id="boost_speed_boots", name="Speed Boots", rarity="Rare", durationSeconds=300,
         effect=dict(walkSpeedMultiplier=1.4), priceSecondsOfIncome=60, minPrice=500,
         description="Run 40% faster. Great for escaping with stolen fish."),
    dict(id="boost_cash_potion", name="2x Cash Potion", rarity="Epic", durationSeconds=600,
         effect=dict(cashMultiplier=2.0), priceSecondsOfIncome=300, minPrice=2_000,
         description="Double all fish income for 10 minutes."),
    dict(id="boost_luck_potion", name="Luck Potion", rarity="Epic", durationSeconds=600,
         effect=dict(luckBonus=1.0), priceSecondsOfIncome=240, minPrice=1_500,
         description="+1 luck for 10 minutes. Rare fish incoming!"),
    dict(id="boost_auto_net", name="Auto-Net", rarity="Legendary", durationSeconds=900,
         effect=dict(autoCast=True, autoCastIntervalMultiplier=1.5), priceSecondsOfIncome=360, minPrice=3_000,
         description="Catches fish for you, even while AFK, for 15 minutes."),
]

# ---------------------------------------------------------------- cosmetics
BANGKA_SKINS = [
    dict(id="skin_bangka_classic", name="Klasikong Bangka", rarity="Common", price=0,
         colors=dict(hull=[245, 245, 240], trim=[30, 90, 200], stripe=[220, 40, 40], outrigger=[200, 170, 110],
                     deck=[150, 100, 60], sail=[250, 250, 245]), description="Blue, white and red, the classic."),
    dict(id="skin_bangka_coral", name="Coral Reef Bangka", rarity="Rare", price=50_000,
         colors=dict(hull=[255, 140, 150], trim=[30, 190, 180], stripe=[255, 220, 120], outrigger=[240, 230, 210],
                     deck=[200, 140, 110], sail=[255, 245, 235]), description="Pink and teal like a living reef."),
    dict(id="skin_bangka_sunset", name="Sunset Bangka", rarity="Rare", price=150_000,
         colors=dict(hull=[250, 140, 50], trim=[120, 50, 150], stripe=[255, 210, 60], outrigger=[90, 40, 110],
                     deck=[170, 80, 50], sail=[255, 190, 120]), description="Painted like a Manila Bay sunset."),
    dict(id="skin_bangka_perlas", name="Perlas Bangka", rarity="Epic", price=2_000_000,
         colors=dict(hull=[240, 238, 250], trim=[215, 180, 90], stripe=[190, 170, 230], outrigger=[225, 220, 235],
                     deck=[205, 195, 215], sail=[250, 245, 255]), description="Pearl-white with gold trim."),
    dict(id="skin_bangka_jeepney", name="Jeepney Bangka", rarity="Legendary", price=25_000_000,
         colors=dict(hull=[200, 205, 212], trim=[230, 30, 60], stripe=[30, 160, 230], outrigger=[250, 200, 30],
                     deck=[60, 170, 80], sail=[250, 200, 30]), description="Chrome and loud colors, King of the Sea."),
    dict(id="skin_bangka_ginto", name="Gintong Bangka", rarity="Mythic", price=250_000_000,
         colors=dict(hull=[240, 190, 50], trim=[150, 30, 40], stripe=[255, 240, 170], outrigger=[200, 150, 40],
                     deck=[120, 30, 35], sail=[255, 235, 160]), description="Solid gold. Probably not seaworthy."),
]
HATS = [
    dict(id="hat_salakot", name="Salakot", style="salakot", rarity="Common", price=1_000,
         description="The classic Filipino farmer-fisher hat."),
    dict(id="hat_bucket", name="Bucket Hat", style="bucket", rarity="Common", price=5_000,
         description="Keeps the sun off while you wait for a bite."),
    dict(id="hat_beanie", name="Fisher Beanie", style="beanie", rarity="Rare", price=20_000,
         description="For cold early-morning trips."),
    dict(id="hat_buri", name="Buri Straw Hat", style="buri", rarity="Rare", price=50_000,
         description="Hand-woven from buri palm."),
    dict(id="hat_captain", name="Kapitan Cap", style="captain", rarity="Epic", price=1_000_000,
         description="You're the captain of this bangka now."),
    dict(id="hat_bangus", name="Bangus Hat", style="bangus", rarity="Legendary", price=20_000_000,
         description="Wear the national fish with pride."),
]

# ---------------------------------------------------------------- gamepasses & dev products (data only)
PLACEHOLDER_ID = 0
GAMEPASSES = [
    dict(id="gp_2x_cash", name="2x Cash", rarity="Legendary", robux=299, gamePassId=PLACEHOLDER_ID,
         perks=dict(cashMultiplier=2.0), description="Permanently double all fish income."),
    dict(id="gp_auto_net", name="Auto-Net Pass", rarity="Legendary", robux=349, gamePassId=PLACEHOLDER_ID,
         perks=dict(autoCast=True), description="Permanent Auto-Net. Catch fish while AFK."),
    dict(id="gp_vip", name="VIP", rarity="Mythic", robux=199, gamePassId=PLACEHOLDER_ID,
         perks=dict(incomeMultiplier=1.1, luckBonus=0.25, chatTag="[VIP]"),
         description="+10% income, +0.25 luck and a VIP chat tag."),
]
DEV_PRODUCTS = [
    dict(id="dp_cash_small", name="Pouch of Pesos", rarity="Rare", robux=49, productId=PLACEHOLDER_ID,
         cashSecondsOfIncome=600, minCash=5_000, description="10 minutes of income (at least 5,000)."),
    dict(id="dp_cash_medium", name="Sack of Pesos", rarity="Epic", robux=149, productId=PLACEHOLDER_ID,
         cashSecondsOfIncome=2_400, minCash=25_000, description="40 minutes of income (at least 25,000)."),
    dict(id="dp_cash_large", name="Treasure Chest", rarity="Legendary", robux=399, productId=PLACEHOLDER_ID,
         cashSecondsOfIncome=9_000, minCash=150_000, description="2.5 hours of income (at least 150,000)."),
]


def _finish_fish():
    totals = {}
    for f in FISH:
        totals[f["rarity"]] = totals.get(f["rarity"], 0) + f["catchWeight"]
    rsum = sum(r["weight"] for r in RARITIES)
    for i, f in enumerate(FISH):
        f["order"] = i + 1
        f["sellValue"] = f["cashPerSecond"] * SELL_SECONDS
        f["bodyVariant"] = f["visual"]["variant"]
        # base % chance at luck 0 = rarity share * share inside rarity
        share = RARITY_BY_NAME[f["rarity"]]["weight"] / rsum * f["catchWeight"] / totals[f["rarity"]]
        f["catchChance"] = round(share * 100, 4)


_finish_fish()

CATEGORIES = {
    "Fish": FISH, "Net": NETS, "Tank": TANKS, "Lock": LOCKS, "Boost": BOOSTS,
    "BangkaSkin": BANGKA_SKINS, "Hat": HATS, "GamePass": GAMEPASSES, "DevProduct": DEV_PRODUCTS,
}
MODEL_CATEGORIES = ["Fish", "Net", "Tank", "Lock", "Boost", "BangkaSkin", "Hat"]


def all_items():
    for cat, items in CATEGORIES.items():
        for it in items:
            yield cat, it


def export_json(path=None):
    path = path or os.path.join(ROOT, "items", "item_data.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    ids = [it["id"] for _, it in all_items()]
    assert len(ids) == len(set(ids)), "duplicate item ids"
    data = dict(studMeters=STUD_METERS, fishBaseLengthStuds=FISH_BASE_LENGTH, rarities=RARITIES,
                economy=dict(baseCastSeconds=BASE_CAST_SECONDS, sellSeconds=SELL_SECONDS,
                             weightBonusMax=WEIGHT_BONUS_MAX, rebirthBaseCost=REBIRTH_BASE_COST,
                             rebirthCostGrowth=REBIRTH_COST_GROWTH, rebirthIncomeBonus=REBIRTH_INCOME_BONUS,
                             rebirthLuckBonus=REBIRTH_LUCK_BONUS, netPriceBase=NET_PRICE_BASE,
                             netPriceGrowth=NET_PRICE_GROWTH, tankPriceBase=TANK_PRICE_BASE,
                             tankPriceGrowth=TANK_PRICE_GROWTH, placeholderId=PLACEHOLDER_ID),
                categories=CATEGORIES)
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1)
    return path, len(ids)


if __name__ == "__main__":
    p, n = export_json()
    print(f"wrote {p} ({n} items)")
