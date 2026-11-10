"""Bundle Studio ModuleScripts with tiny Roblox stubs and run them with the Luau CLI.

python tools/mutations/run_luau.py tests     -> tools/mutations/tests.luau (unit tests)
python tools/mutations/run_luau.py sim       -> tools/mutations/economy_sim.luau -> items/mutation_balance.json
python tools/mutations/run_luau.py analyze   -> luau-analyze on every studio/**/*.luau (Roblox globals declared)
Set LUAU_BIN_DIR if the Luau CLI is not in /tmp/luau.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("LUAU_BIN_DIR", "/tmp/luau")
WORK = "/tmp/luau/mut"

MODULE_DIRS = [os.path.join(ROOT, "studio", "items"), os.path.join(ROOT, "studio", "mutations", "shared"),
               os.path.join(ROOT, "studio", "mutations", "server")]
PURE_MODULES = ["RarityConfig", "FishData", "NetData", "TankData", "LockData", "BoostData", "CosmeticData",
                "ShopData", "StarConfig", "MutationData", "EventSchedule", "EconomyBalance", "ItemRegistry",
                "LootRoller", "FishDisplay", "FishSchema", "MutationRoller"]

STUBS = r'''
local Color3 = { new = function(r, g, b) return { R = r, G = g, B = b } end,
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
-- xorshift32: exact with bit32, independent stream per Random object
local Random = { new = function(seed)
	local state = (math.floor(seed or 1) % 4294967295) + 1
	local obj = {}
	function obj:NextNumber(a, b)
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		local u = state / 4294967296
		if a then return a + (b - a) * u end
		return u
	end
	function obj:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
	for _ = 1, 8 do obj:NextNumber() end
	return obj
end }
local function warn(...) print("WARN", ...) end
local MODULES, CACHE = {}, {}
local function require(ref)
	local name = ref.__name
	if CACHE[name] == nil then
		assert(MODULES[name], "module not bundled: " .. tostring(name))
		CACHE[name] = MODULES[name](ref.__script)
	end
	return CACHE[name]
end
local parent = {}
local function ref(name) return { __name = name, __script = { Parent = parent, Name = name } } end
setmetatable(parent, { __index = function(_, k) return ref(k) end })
parent.WaitForChild = function(_, k) return ref(k) end
local itemsFolder = { WaitForChild = function() return parent end }
local game = { GetService = function() return { WaitForChild = function() return itemsFolder end } end }
'''

ROBLOX_GLOBALS = ["game", "workspace", "script", "Instance", "Enum", "Color3", "UDim", "UDim2", "Vector2", "Vector3",
                  "CFrame", "TweenInfo", "NumberSequence", "NumberSequenceKeypoint", "ColorSequence",
                  "ColorSequenceKeypoint", "NumberRange", "Random", "task", "tick", "warn", "UserSettings", "Font",
                  "Rect", "BrickColor", "DateTime", "Content", "time", "delay", "spawn", "settings"]


def find_module(name):
    for d in MODULE_DIRS:
        p = os.path.join(d, name + ".luau")
        if os.path.exists(p):
            return p
    raise FileNotFoundError(name)


def bundle(entry):
    parts = [STUBS]
    for n in PURE_MODULES:
        try:
            src = open(find_module(n)).read()
        except FileNotFoundError:
            continue
        parts.append(f'MODULES["{n}"] = function(script)\n{src}\nend\n')
    parts.append(open(os.path.join(HERE, entry)).read())
    os.makedirs(WORK, exist_ok=True)
    out = os.path.join(WORK, entry.replace(".luau", ".bundle.luau"))
    with open(out, "w") as fh:
        fh.write("\n".join(parts))
    return out


def run(entry):
    out = bundle(entry)
    proc = subprocess.run([os.path.join(BIN, "luau"), out], capture_output=True, text=True, timeout=900)
    return proc.returncode, proc.stdout + proc.stderr


def analyze():
    tmp = os.path.join(WORK, "analyze")
    os.makedirs(tmp, exist_ok=True)
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    files = []
    for base in (os.path.join(ROOT, "studio", "items"), os.path.join(ROOT, "studio", "mutations")):
        for dp, _, fns in os.walk(base):
            for fn in fns:
                if fn.endswith(".luau"):
                    dst = os.path.join(tmp, fn)
                    with open(os.path.join(dp, fn)) as a, open(dst, "w") as b:
                        b.write(a.read())
                    files.append(dst)
    with open(os.path.join(tmp, ".luaurc"), "w") as fh:
        json.dump({"languageMode": "nonstrict", "globals": ROBLOX_GLOBALS}, fh)
    proc = subprocess.run([os.path.join(BIN, "luau-analyze")] + sorted(files), capture_output=True, text=True)
    lines = [ln for ln in (proc.stdout + proc.stderr).splitlines() if ln.strip() and "Unknown require" not in ln]
    return len(files), lines


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "tests"
    if mode == "analyze":
        n, lines = analyze()
        print("\n".join(lines) or f"luau-analyze: {n} files, no issues (Roblox-only requires ignored)")
        sys.exit(1 if lines else 0)
    entry = {"tests": "tests.luau", "sim": "economy_sim.luau"}[mode]
    code, output = run(entry)
    if mode == "sim":
        rows = [ln[5:] for ln in output.splitlines() if ln.startswith("JSON ")]
        if rows:
            with open(os.path.join(ROOT, "items", "mutation_balance.json"), "w") as fh:
                fh.write(rows[-1] + "\n")
        output = "\n".join(ln for ln in output.splitlines() if not ln.startswith("JSON "))
    print(output)
    sys.exit(code)


if __name__ == "__main__":
    main()
