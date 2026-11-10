--[[
	FishSchema  (ModuleScript, SERVER ONLY)
	Put in: ServerStorage > Items > ServerModules > FishSchema

	DataStore format for ONE fish. Keep every fish a player owns (tank, backpack) in this shape.

	v2 record (short keys keep DataStore saves small, about 120 bytes per fish):
	{
		v  = 2,                          -- schema version
		uid = "3F2504E0-...",            -- unique id (HttpService:GenerateGUID), used for steal/sell lookups
		id = "fish_bangus",              -- FishData id
		w  = 1.234,                      -- weight in kg (3 decimals)
		sz = 0.52,                       -- size roll 0..1 (visual length, part of the star roll)
		st = 3,                          -- star grade 1..5
		mu = { "golden_tide", "thunderstorm" }, -- mutation ids, rarest first, no duplicates, max 8
		ca = 1793000000,                 -- caught at (server unix time)
		sc = 0,                          -- times this fish has been stolen
		ow = 123456,                     -- UserId of the original catcher (0 = unknown)
	}

	v1 (before this update) was { id, w } or { fishId, weightKg }. Migrate() upgrades it:
	stars come from the weight with a neutral size roll (no randomness, so a re-load never
	changes them), and mutations start empty.

	ALWAYS run loaded data through FishSchema.Migrate (it also sanitizes): a corrupted or edited
	save can then never contain 6 stars, unknown mutations, duplicates, or an impossible weight.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")
local FishData = require(Modules:WaitForChild("FishData"))
local StarConfig = require(Modules:WaitForChild("StarConfig"))
local MutationData = require(Modules:WaitForChild("MutationData"))

local FishSchema = {}

FishSchema.VERSION = 2

local function round(value, decimals)
	local factor = 10 ^ decimals
	return math.floor(value * factor + 0.5) / factor
end

local function weightFraction(fish, weightKg)
	if fish.weightMax <= fish.weightMin then
		return 0
	end
	return math.clamp((weightKg - fish.weightMin) / (fish.weightMax - fish.weightMin), 0, 1)
end

-- Builds a clean v2 record. fields: uid, fishId, weightKg, sizeFraction, stars, mutations, caughtAt, ownerUserId
function FishSchema.New(fields)
	return FishSchema.Sanitize({
		v = FishSchema.VERSION,
		uid = fields.uid,
		id = fields.fishId,
		w = fields.weightKg,
		sz = fields.sizeFraction,
		st = fields.stars,
		mu = fields.mutations or {},
		ca = fields.caughtAt,
		sc = fields.stealCount or 0,
		ow = fields.ownerUserId or 0,
	})
end

-- Returns a clean copy, or nil if the species no longer exists.
function FishSchema.Sanitize(record)
	if type(record) ~= "table" then
		return nil
	end
	local fish = FishData.ById[record.id]
	if fish == nil then
		return nil
	end
	local w = tonumber(record.w) or fish.weightMin
	w = round(math.clamp(w, fish.weightMin, fish.weightMax), 3)
	local sz = tonumber(record.sz)
	sz = sz and round(math.clamp(sz, 0, 1), 3) or 0.5
	local st = tonumber(record.st)
	if st == nil then
		st = StarConfig.QualityToStars(StarConfig.QualityFromRolls(weightFraction(fish, w), sz))
	end
	return {
		v = FishSchema.VERSION,
		uid = tostring(record.uid or ""),
		id = fish.id,
		w = w,
		sz = sz,
		st = StarConfig.Clamp(st),
		mu = MutationData.Sanitize(record.mu),
		ca = math.floor(tonumber(record.ca) or 0),
		sc = math.max(0, math.floor(tonumber(record.sc) or 0)),
		ow = math.floor(tonumber(record.ow) or 0),
	}
end

-- Upgrades any older record to the current version (and sanitizes). nil = drop this fish.
function FishSchema.Migrate(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local version = tonumber(raw.v) or 1
	if version < 2 then
		raw = {
			uid = raw.uid,
			id = raw.id or raw.fishId,
			w = raw.w or raw.weightKg,
			sz = nil, -- neutral size: stars come from weight alone, deterministically
			st = nil,
			mu = {},
			ca = raw.ca or raw.caughtAt,
			sc = 0,
			ow = raw.ow or 0,
		}
	end
	return FishSchema.Sanitize(raw)
end

function FishSchema.Copy(record)
	local copy = table.clone(record)
	copy.mu = table.clone(record.mu or {})
	return copy
end

-- Migrates a whole saved list, dropping fish whose species was removed. Returns list, droppedCount.
function FishSchema.MigrateList(rawList)
	local list, dropped = {}, 0
	for _, raw in ipairs(type(rawList) == "table" and rawList or {}) do
		local record = FishSchema.Migrate(raw)
		if record then
			table.insert(list, record)
		else
			dropped += 1
		end
	end
	return list, dropped
end

return FishSchema
