--[[
	MutationData  (ModuleScript)
	Put in: ReplicatedStorage > Items > Modules > MutationData

	THE config for world events and the mutations they give. One entry = one event + its mutation.
	Edit numbers here; everything else (scheduler, roller, UI, economy) reads from this table.

	Per entry
	  id               saved in player data. NEVER rename an id after launch (old saves use it)
	  eventName        shown in banners and the countdown panel
	  prefix           added to the fish name: "Golden Thunderstruck Bangus"
	  multiplier       value multiplier of this mutation (x2 ... x8)
	  chance           chance per catch WHILE this event is active (0.10 = 10%)
	  durationSeconds  how long the event lasts (max: EventSchedule slot length minus its start offset)
	  scheduleWeight   how often the event is picked for a slot (bigger = more often)
	  color / accent   UI color theme
	  emoji            icon used by the UI (iconAssetId > 0 replaces it with an uploaded image)
	  tint             how mutated fish look: style = gold | rainbow | electric | crimson | aurora | storm | shadow
	  sky              client-side lighting preset while the event is active (EventAtmosphere)

	Rules (stacking, caps, luck) are below the list. Formula for a fish with mutations m1..mn:
	  Additive (default):  total = 1 + sum(multiplier_i - 1)      ("sum minus the overlap")
	  Multiplicative:      total = product(multiplier_i)
	  Highest:             total = max(multiplier_i)
	  then:                total = min(total, Rules.multiplierCap)
	Example: Golden (x4) + Thunderstruck (x2) = 1 + 3 + 1 = x5. All 8 = x27 raw, capped to x12.
]]

local MutationData = {}

MutationData.Rules = {
	maxMutationsPerFish = 8,
	stacking = "Additive", -- "Additive" | "Multiplicative" | "Highest"
	multiplierCap = 12, -- hard cap on the combined mutation multiplier (stars multiply on top, max x2)
	luckChanceBonus = 0.1, -- +10% of the base chance per point of luck (Golden Trawl 2.5 luck = +25%)
	maxChance = 0.5, -- no event can ever give more than a 50% chance per catch
	stealChanceMultiplier = 1.0, -- chance multiplier for the fresh roll a stolen fish gets
	maxNamePrefixes = 2, -- "Golden Thunderstruck Bangus +1"
}

local rgb = Color3.fromRGB

MutationData.List = {
	{
		id = "thunderstorm",
		eventName = "Thunderstorm",
		prefix = "Thunderstruck",
		multiplier = 2,
		chance = 0.10,
		durationSeconds = 600,
		scheduleWeight = 30,
		color = rgb(70, 160, 255),
		accent = rgb(225, 245, 255),
		emoji = "⛈️",
		iconAssetId = 0,
		tint = { style = "electric", fill = rgb(60, 150, 255), outline = rgb(200, 240, 255) },
		sky = { preset = "storm", clockTime = 16.5, brightness = 0.8, tint = rgb(190, 205, 230), saturation = -0.3,
			fogColor = rgb(70, 80, 95), fogEnd = 900, atmosphereDensity = 0.45, atmosphereColor = rgb(120, 130, 150),
			rain = 1.0, lightning = rgb(200, 230, 255), wind = 15 },
	},
	{
		id = "typhoon",
		eventName = "Typhoon (Bagyo)",
		prefix = "Bagyo",
		multiplier = 2.5,
		chance = 0.08,
		durationSeconds = 600,
		scheduleWeight = 22,
		color = rgb(40, 190, 175),
		accent = rgb(210, 255, 245),
		emoji = "🌀",
		iconAssetId = 0,
		tint = { style = "storm", fill = rgb(60, 180, 170), outline = rgb(180, 210, 210) },
		sky = { preset = "typhoon", clockTime = 15, brightness = 0.6, tint = rgb(175, 200, 200), saturation = -0.4,
			fogColor = rgb(80, 95, 100), fogEnd = 450, atmosphereDensity = 0.6, atmosphereColor = rgb(110, 130, 135),
			rain = 1.6, lightning = rgb(220, 255, 250), wind = 45 },
	},
	{
		id = "blood_moon",
		eventName = "Blood Moon",
		prefix = "Crimson",
		multiplier = 3,
		chance = 0.06,
		durationSeconds = 540,
		scheduleWeight = 16,
		color = rgb(220, 30, 50),
		accent = rgb(255, 190, 190),
		emoji = "🌕",
		iconAssetId = 0,
		tint = { style = "crimson", fill = rgb(200, 0, 25), outline = rgb(255, 80, 80) },
		sky = { preset = "bloodMoon", clockTime = 0, brightness = 1.2, tint = rgb(255, 160, 160), saturation = 0.1,
			fogColor = rgb(90, 10, 20), fogEnd = 700, atmosphereDensity = 0.4, atmosphereColor = rgb(160, 30, 40),
			moonSize = 32, stars = 1500 },
	},
	{
		id = "aurora",
		eventName = "Aurora",
		prefix = "Aurora",
		multiplier = 3.5,
		chance = 0.05,
		durationSeconds = 540,
		scheduleWeight = 12,
		color = rgb(60, 230, 160),
		accent = rgb(180, 120, 255),
		emoji = "🌌",
		iconAssetId = 0,
		tint = { style = "aurora", fill = rgb(50, 230, 150), outline = rgb(170, 100, 255) },
		sky = { preset = "aurora", clockTime = 22, brightness = 1.4, tint = rgb(200, 255, 230), saturation = 0.2,
			fogColor = rgb(20, 40, 60), fogEnd = 1500, atmosphereDensity = 0.3, atmosphereColor = rgb(60, 120, 140),
			aurora = true, stars = 4000 },
	},
	{
		id = "golden_tide",
		eventName = "Golden Tide",
		prefix = "Golden",
		multiplier = 4,
		chance = 0.04,
		durationSeconds = 480,
		scheduleWeight = 9,
		color = rgb(255, 195, 30),
		accent = rgb(255, 245, 190),
		emoji = "🪙",
		iconAssetId = 0,
		tint = { style = "gold", fill = rgb(255, 190, 20), outline = rgb(255, 245, 170) },
		sky = { preset = "golden", clockTime = 17.8, brightness = 2.6, tint = rgb(255, 225, 160), saturation = 0.25,
			fogColor = rgb(255, 200, 120), fogEnd = 2000, atmosphereDensity = 0.3, atmosphereColor = rgb(255, 200, 120),
			sunRays = 0.25 },
	},
	{
		id = "rainbow_bloom",
		eventName = "Rainbow Bloom",
		prefix = "Rainbow",
		multiplier = 5,
		chance = 0.03,
		durationSeconds = 480,
		scheduleWeight = 6,
		color = rgb(255, 90, 200),
		accent = rgb(120, 220, 255),
		emoji = "🌈",
		iconAssetId = 0,
		tint = { style = "rainbow", fill = rgb(255, 0, 0), outline = rgb(255, 255, 255) },
		sky = { preset = "rainbow", clockTime = 13, brightness = 2.8, tint = rgb(255, 240, 255), saturation = 0.45,
			fogColor = rgb(220, 200, 255), fogEnd = 2500, atmosphereDensity = 0.25, atmosphereColor = rgb(230, 210, 255),
			bloom = 0.8, hueCycle = true },
	},
	{
		id = "solar_eclipse",
		eventName = "Solar Eclipse",
		prefix = "Eclipsed",
		multiplier = 6,
		chance = 0.02,
		durationSeconds = 360,
		scheduleWeight = 4,
		color = rgb(255, 150, 40),
		accent = rgb(40, 30, 50),
		emoji = "🌑",
		iconAssetId = 0,
		tint = { style = "shadow", fill = rgb(15, 10, 20), outline = rgb(255, 170, 50) },
		sky = { preset = "eclipse", clockTime = 12, brightness = 0.3, tint = rgb(255, 200, 160), saturation = -0.5,
			fogColor = rgb(30, 20, 30), fogEnd = 800, atmosphereDensity = 0.5, atmosphereColor = rgb(60, 40, 50),
			stars = 3000 },
	},
	{
		id = "bakunawa_eclipse",
		eventName = "Bakunawa Eclipse",
		prefix = "Moon-Eaten",
		multiplier = 8,
		chance = 0.01,
		durationSeconds = 360,
		scheduleWeight = 1,
		color = rgb(150, 70, 255),
		accent = rgb(90, 230, 255),
		emoji = "🐉",
		iconAssetId = 0,
		tint = { style = "shadow", fill = rgb(25, 0, 50), outline = rgb(90, 230, 255) },
		sky = { preset = "bakunawa", clockTime = 0, brightness = 0.5, tint = rgb(190, 160, 255), saturation = -0.2,
			fogColor = rgb(25, 10, 50), fogEnd = 600, atmosphereDensity = 0.55, atmosphereColor = rgb(60, 30, 110),
			moonSize = 0, stars = 5000, lightning = rgb(120, 240, 255) },
	},
}

-- ===================================================================== lookups
MutationData.ById = {}
MutationData.RarityRank = {} -- [id] = 1 (most common) .. 8 (rarest)
for index, mutation in ipairs(MutationData.List) do
	assert(MutationData.ById[mutation.id] == nil, "MutationData: duplicate id " .. mutation.id)
	assert(mutation.multiplier >= 1, "MutationData: multiplier must be >= 1 for " .. mutation.id)
	assert(mutation.chance >= 0 and mutation.chance <= 1, "MutationData: chance must be 0..1 for " .. mutation.id)
	mutation.order = index
	MutationData.ById[mutation.id] = mutation
	MutationData.RarityRank[mutation.id] = index
	table.freeze(mutation.tint)
	table.freeze(mutation.sky)
	table.freeze(mutation)
end
table.freeze(MutationData.List)
table.freeze(MutationData.ById)
table.freeze(MutationData.Rules)

function MutationData.Get(mutationId)
	return MutationData.ById[mutationId]
end

function MutationData.IsValid(mutationId)
	return type(mutationId) == "string" and MutationData.ById[mutationId] ~= nil
end

-- Removes unknown ids and duplicates, keeps at most maxMutationsPerFish (rarest kept first).
-- Use it on anything loaded from a DataStore.
function MutationData.Sanitize(mutationIds)
	local seen, clean = {}, {}
	if type(mutationIds) ~= "table" then
		return clean
	end
	for _, mutationId in ipairs(mutationIds) do
		if MutationData.IsValid(mutationId) and not seen[mutationId] then
			seen[mutationId] = true
			table.insert(clean, mutationId)
		end
	end
	table.sort(clean, function(a, b)
		return MutationData.RarityRank[a] > MutationData.RarityRank[b]
	end)
	while #clean > MutationData.Rules.maxMutationsPerFish do
		table.remove(clean)
	end
	return clean
end

-- Copy of the list sorted rarest first (the order used for name prefixes and chips)
function MutationData.SortByRarity(mutationIds)
	return MutationData.Sanitize(mutationIds)
end

-- The rarest mutation (decides the main tint), or nil
function MutationData.GetPrimary(mutationIds)
	local sorted = MutationData.Sanitize(mutationIds)
	return sorted[1] and MutationData.ById[sorted[1]] or nil
end

function MutationData.Has(mutationIds, mutationId)
	for _, id in ipairs(mutationIds or {}) do
		if id == mutationId then
			return true
		end
	end
	return false
end

--[[
	Combined mutation multiplier. Returns: capped total, raw total (before the cap), wasCapped.
	Empty list -> 1.
]]
function MutationData.CombineMultipliers(mutationIds, rules)
	rules = rules or MutationData.Rules
	local clean = MutationData.Sanitize(mutationIds)
	if #clean == 0 then
		return 1, 1, false
	end
	local raw
	if rules.stacking == "Multiplicative" then
		raw = 1
		for _, id in ipairs(clean) do
			raw *= MutationData.ById[id].multiplier
		end
	elseif rules.stacking == "Highest" then
		raw = 1
		for _, id in ipairs(clean) do
			raw = math.max(raw, MutationData.ById[id].multiplier)
		end
	else -- "Additive": sum of multipliers minus the shared base of 1 for every extra mutation
		raw = 1
		for _, id in ipairs(clean) do
			raw += MutationData.ById[id].multiplier - 1
		end
	end
	local capped = math.min(raw, rules.multiplierCap)
	return capped, raw, raw > rules.multiplierCap
end

return MutationData
