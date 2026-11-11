--[[
	TerrainBuilder  (COMMAND BAR script, run ONCE in edit mode)
	Location: paste into View > Command Bar and press Enter. Do not keep it as a Script.
	Needs: ReplicatedStorage.World.WorldConfig (paste it first).

	Replaces the flat baseplate with a tropical island:
	  * island shape from layered Perlin noise (math.noise), round with rocky coves
	  * flattened grass pad under each of Plot1..Plot8 and a round plaza under the spawn
	  * packed-dirt paths from every plot to the plaza
	  * sand beach, shallow turquoise shelf, deep sea, sea floor of sand/rock
	  * rocky coves and a few boulders in the shallows
	Your plots, spawn and scripts are not touched. The Baseplate is destroyed (anything named "Baseplate").
	Every chunk write is wrapped in pcall; failures are counted and printed, never fatal.

	Takes 20-60 s for a 500-stud island. Undo with Ctrl+Z if you don't like it (or run again after
	changing WorldConfig.SETTINGS; it clears its own terrain first).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Terrain = workspace.Terrain
local WorldConfig = require(ReplicatedStorage:WaitForChild("World"):WaitForChild("WorldConfig"))

local S = WorldConfig.SETTINGS
local L = WorldConfig.Layout()
local RES = S.VOXEL_RES
local SEED = 1337
local CHUNK = 64 -- studs per WriteVoxels call

print(("[TerrainBuilder] island radius %d, plot level %.1f, sea level %.1f, %d plots"):format(
	L.radius, L.plotLevel, L.seaLevel, #L.plots))
ChangeHistoryService:SetWaypoint("Before island")

-- ===================================================================== noise helpers
local function fbm(x, z, octaves, freq, seed)
	local sum, amp, f, norm = 0, 1, freq, 0
	for _ = 1, octaves do
		sum += math.noise(x * f + seed, z * f - seed, seed * 0.37) * amp
		norm += amp
		amp *= 0.5
		f *= 2.1
	end
	return sum / norm -- about -0.7 .. 0.7
end

local function smoothstep(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- ===================================================================== flat zones (pads, plaza, paths)
local zones = {} -- { kind, test(x, z) -> weight 0..1 }
for _, p in ipairs(L.plots) do
	local hx, hz = p.size.X / 2 + S.PAD_MARGIN, p.size.Z / 2 + S.PAD_MARGIN
	local px, pz = p.position.X, p.position.Z
	table.insert(zones, { kind = "pad", y = p.base, test = function(x, z)
		local dx, dz = math.abs(x - px) - hx, math.abs(z - pz) - hz
		local d = math.max(dx, dz)
		return 1 - smoothstep(0, 14, d)
	end })
end
table.insert(zones, { kind = "plaza", y = L.plotLevel, test = function(x, z)
	local d = (Vector2.new(x, z) - Vector2.new(L.plazaCenter.X, L.plazaCenter.Z)).Magnitude - S.PLAZA_RADIUS
	return 1 - smoothstep(0, 16, d)
end })
local paths = {}
for _, p in ipairs(L.plots) do
	local a = Vector2.new(p.position.X, p.position.Z)
	local b = Vector2.new(L.plazaCenter.X, L.plazaCenter.Z)
	table.insert(paths, { a = a, b = b, ya = p.base, yb = L.plotLevel })
end
local function pathWeight(x, z)
	local best, y = 0, L.plotLevel
	local q = Vector2.new(x, z)
	for _, pth in ipairs(paths) do
		local ab = pth.b - pth.a
		local t = math.clamp((q - pth.a):Dot(ab) / ab:Dot(ab), 0, 1)
		local d = (q - (pth.a + ab * t)).Magnitude - S.PATH_WIDTH / 2
		local w = 1 - smoothstep(0, 8, d)
		if w > best then
			best, y = w, pth.ya + (pth.yb - pth.ya) * t
		end
	end
	return best, y
end

-- ===================================================================== height + material functions
local cx, cz = L.center.X, L.center.Z
local function islandMask(x, z)
	local dx, dz = x - cx, z - cz
	local ang = math.atan2(dz, dx)
	local wobble = 1 + 0.16 * math.noise(math.cos(ang) * 1.7 + SEED, math.sin(ang) * 1.7, 0.5)
		+ 0.07 * math.noise(math.cos(ang) * 4.2, math.sin(ang) * 4.2 + SEED, 1.5)
	local r = math.sqrt(dx * dx + dz * dz) / (L.radius * wobble)
	return r -- < 1 inside the island, coves where wobble is small
end

local function groundHeight(x, z)
	local r = islandMask(x, z)
	local land = 1 - smoothstep(0.78, 1.0, r) -- 1 inland .. 0 at the shoreline
	local hills = (fbm(x, z, 4, 1 / 90, SEED) + 0.35) * S.HILL_HEIGHT * smoothstep(0.35, 0.9, land)
	local ridges = math.abs(fbm(x, z, 2, 1 / 40, SEED + 9)) * 6 * land
	local y = L.plotLevel + hills + ridges + 1.5 * land
	-- shoreline drop to the beach
	local beach = L.seaLevel + 2.2 + 3.5 * land
	y = y * land + beach * (1 - land)
	-- sea floor beyond the shore
	local shelf = smoothstep(1.0, 1.08, r)
	local deep = smoothstep(1.06, 1.5, r)
	local floor = L.seaLevel - 4 - 6 * shelf - S.SEA_DEPTH * deep + fbm(x, z, 3, 1 / 60, SEED + 3) * 4 * deep
	if r > 1.0 then
		y = math.min(y, floor)
	end
	-- flatten pads, plaza and paths
	for _, zone in ipairs(zones) do
		local w = zone.test(x, z)
		if w > 0 then
			y = y + (zone.y - y) * w
		end
	end
	local pw, py = pathWeight(x, z)
	if pw > 0 then
		y = y + (py - y) * pw
	end
	return y, r, land
end

local function materialAt(x, z, y, r, land)
	for _, zone in ipairs(zones) do
		if zone.test(x, z) > 0.6 then
			return zone.kind == "plaza" and Enum.Material.Cobblestone or Enum.Material.Grass
		end
	end
	local pw = pathWeight(x, z)
	if pw > 0.5 then
		return Enum.Material.Ground
	end
	if y < L.seaLevel + 0.5 then
		return (fbm(x, z, 2, 1 / 25, SEED + 5) > 0.22) and Enum.Material.Rock or Enum.Material.Sand
	end
	if y < L.seaLevel + S.BEACH_WIDTH * 0.16 + 1.5 then
		return Enum.Material.Sand
	end
	-- rocky coves where the coast wobble is tight
	if r > 0.86 and math.noise(x / 30 + SEED, z / 30, 2) > 0.28 then
		return Enum.Material.Rock
	end
	if y > L.plotLevel + S.HILL_HEIGHT * 0.65 then
		return Enum.Material.LeafyGrass
	end
	return Enum.Material.Grass
end

-- ===================================================================== clear + write
local extent = L.radius * 1.7
local yMin = L.seaLevel - S.SEA_DEPTH - 16
local yMax = L.plotLevel + S.HILL_HEIGHT + 24
local function snap(v)
	return math.floor(v / RES) * RES
end
local x0, x1 = snap(cx - extent), snap(cx + extent)
local z0, z1 = snap(cz - extent), snap(cz + extent)
yMin, yMax = snap(yMin), snap(yMax) + RES

pcall(function()
	Terrain:FillBlock(CFrame.new((x0 + x1) / 2, (yMin + yMax) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, yMax - yMin, z1 - z0), Enum.Material.Air)
end)
for _, obj in ipairs(workspace:GetChildren()) do
	if obj.Name == "Baseplate" and obj:IsA("BasePart") then
		obj:Destroy()
	end
end

local failures, chunks = 0, 0
local ny = (yMax - yMin) / RES
for bx = x0, x1 - RES, CHUNK do
	for bz = z0, z1 - RES, CHUNK do
		local w = math.min(CHUNK, x1 - bx) / RES
		local d = math.min(CHUNK, z1 - bz) / RES
		local region = Region3.new(Vector3.new(bx, yMin, bz), Vector3.new(bx + w * RES, yMax, bz + d * RES))
		local mats, occ = {}, {}
		for i = 1, w do
			mats[i], occ[i] = {}, {}
			local x = bx + (i - 0.5) * RES
			for j = 1, ny do
				mats[i][j], occ[i][j] = {}, {}
			end
			for k = 1, d do
				local z = bz + (k - 0.5) * RES
				local h, r, land = groundHeight(x, z)
				local mat = materialAt(x, z, h, r, land)
				for j = 1, ny do
					local y = yMin + (j - 0.5) * RES
					local solid = math.clamp((h - (y - RES / 2)) / RES, 0, 1)
					if solid > 0.02 then
						mats[i][j][k] = mat
						occ[i][j][k] = solid
					elseif y < L.seaLevel then
						mats[i][j][k] = Enum.Material.Water
						occ[i][j][k] = math.clamp((L.seaLevel - (y - RES / 2)) / RES, 0, 1)
					else
						mats[i][j][k] = Enum.Material.Air
						occ[i][j][k] = 0
					end
				end
			end
		end
		local ok, err = pcall(function()
			Terrain:WriteVoxels(region, RES, mats, occ)
		end)
		chunks += 1
		if not ok then
			failures += 1
			warn("[TerrainBuilder] chunk failed: " .. tostring(err))
		end
		if chunks % 8 == 0 then
			task.wait()
		end
	end
end

-- a few boulders in the shallows (FillBall), rocky coves
local rng = Random.new(SEED)
for _ = 1, 14 do
	local a = rng:NextNumber(0, math.pi * 2)
	local rr = L.radius * rng:NextNumber(0.98, 1.12)
	local px, pz = cx + math.cos(a) * rr, cz + math.sin(a) * rr
	local h = groundHeight(px, pz)
	pcall(function()
		Terrain:FillBall(Vector3.new(px, h + 1, pz), rng:NextNumber(4, 9), Enum.Material.Rock)
	end)
end

-- water look (also set by LightingSetup; repeated here so the island looks right immediately)
pcall(function()
	Terrain.WaterColor = Color3.fromRGB(12, 120, 140)
	Terrain.WaterTransparency = 0.72
	Terrain.WaterReflectance = 0.55
	Terrain.WaterWaveSize = 0.18
	Terrain.WaterWaveSpeed = 12
end)

ChangeHistoryService:SetWaypoint("Island built")
print(("[TerrainBuilder] done: %d chunks written, %d failed. Pier/plaza props: run PropBuilder next."):format(chunks, failures))
