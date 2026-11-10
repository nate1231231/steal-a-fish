--[[
	FishDisplay  (ModuleScript)
	Put in: ReplicatedStorage > Items > Modules > FishDisplay

	Pure text/number helpers for showing a fish record anywhere: popups, backpack tools,
	tank labels, shop lists. No Instances are created here, so it is safe on server and client.

		FishDisplay.StarText(3)                          --> "★★★☆☆"
		FishDisplay.FormatName("fish_bangus", { "golden_tide", "thunderstorm" })
		                                                 --> "Golden Thunderstruck Bangus"
		FishDisplay.ToolName(record)                     --> "★3 Golden Thunderstruck Bangus"
		FishDisplay.Describe(record)                     --> table with everything a UI needs

	`record` is a fish record from FishSchema: { id, w (kg), st (stars), mu (mutation ids), ... }
]]

local FishData = require(script.Parent.FishData)
local StarConfig = require(script.Parent.StarConfig)
local MutationData = require(script.Parent.MutationData)
local EconomyBalance = require(script.Parent.EconomyBalance)

local FishDisplay = {}

FishDisplay.STAR_FILLED = "★"
FishDisplay.STAR_EMPTY = "☆"

-- Celebration tiers for popups, smallest to biggest
FishDisplay.Tiers = { "Normal", "Great", "Epic", "Legendary" }
local TIER_RANK = { Normal = 1, Great = 2, Epic = 3, Legendary = 4 }

function FishDisplay.StarText(stars)
	stars = StarConfig.Clamp(stars)
	return string.rep(FishDisplay.STAR_FILLED, stars) .. string.rep(FishDisplay.STAR_EMPTY, StarConfig.MAX_STARS - stars)
end

-- Fish name with mutation prefixes, rarest first. Extra mutations become "+N".
function FishDisplay.FormatName(fishIdOrName, mutationIds, maxPrefixes)
	local fish = FishData.ById[fishIdOrName]
	local baseName = fish and fish.name or tostring(fishIdOrName)
	local sorted = MutationData.Sanitize(mutationIds)
	maxPrefixes = maxPrefixes or MutationData.Rules.maxNamePrefixes
	local parts = {}
	for index, mutationId in ipairs(sorted) do
		if index > maxPrefixes then
			break
		end
		table.insert(parts, MutationData.ById[mutationId].prefix)
	end
	table.insert(parts, baseName)
	local name = table.concat(parts, " ")
	if #sorted > maxPrefixes then
		name ..= " +" .. tostring(#sorted - maxPrefixes)
	end
	return name
end

-- Short text for Roblox Tool names in the default backpack hotbar
function FishDisplay.ToolName(record)
	return ("★%d %s"):format(StarConfig.Clamp(record.st), FishDisplay.FormatName(record.id, record.mu, 1))
end

-- How big the popup celebration should be
function FishDisplay.CelebrationTier(record, gainedIds)
	local rank = 1
	local stars = StarConfig.Clamp(record.st)
	if stars >= 5 then
		rank = math.max(rank, 3)
	elseif stars >= 4 then
		rank = math.max(rank, 2)
	end
	local fish = FishData.ById[record.id]
	if fish and fish.rarity == "Mythic" then
		rank = math.max(rank, 4)
	elseif fish and fish.rarity == "Legendary" then
		rank = math.max(rank, 3)
	end
	for _, mutationId in ipairs(gainedIds or {}) do
		local mutation = MutationData.ById[mutationId]
		if mutation then
			if mutation.multiplier >= 5 then
				rank = math.max(rank, 4)
			elseif mutation.multiplier >= 3.5 then
				rank = math.max(rank, 3)
			else
				rank = math.max(rank, 2)
			end
		end
	end
	return FishDisplay.Tiers[rank]
end

function FishDisplay.TierRank(tier)
	return TIER_RANK[tier] or 1
end

-- Short number text: 950 -> "950", 12500 -> "12.5K", 3400000 -> "3.4M"
function FishDisplay.Abbreviate(value)
	local suffixes = { "", "K", "M", "B", "T", "Qa" }
	local index = 1
	while math.abs(value) >= 1000 and index < #suffixes do
		value /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(math.floor(value * 10 + 0.5) / 10)
	end
	local text = ("%.1f%s"):format(value, suffixes[index]):gsub("%.0([KMBTQ])", "%1")
	return text
end

--[[
	Everything a UI needs for one fish:
	{ name, baseName, rarity, stars, starText, starColor, mutations = { {id, prefix, multiplier, color, isNew} },
	  starMultiplier, mutationMultiplier, mutationRaw, mutationCapped, totalMultiplier,
	  incomePerSecond, sellValue, primary (mutation table or nil), tier }
]]
function FishDisplay.Describe(record, gainedIds)
	local fish = FishData.ById[record.id]
	local gained = {}
	for _, mutationId in ipairs(gainedIds or {}) do
		gained[mutationId] = true
	end
	local mutations = {}
	for _, mutationId in ipairs(MutationData.Sanitize(record.mu)) do
		local mutation = MutationData.ById[mutationId]
		table.insert(mutations, {
			id = mutationId,
			prefix = mutation.prefix,
			eventName = mutation.eventName,
			multiplier = mutation.multiplier,
			color = mutation.color,
			emoji = mutation.emoji,
			isNew = gained[mutationId] == true,
		})
	end
	local mutationMultiplier, mutationRaw, mutationCapped = MutationData.CombineMultipliers(record.mu)
	local starMultiplier = StarConfig.GetMultiplier(record.st)
	return {
		name = FishDisplay.FormatName(record.id, record.mu),
		baseName = fish and fish.name or tostring(record.id),
		rarity = fish and fish.rarity or "Common",
		stars = StarConfig.Clamp(record.st),
		starText = FishDisplay.StarText(record.st),
		starColor = StarConfig.Get(record.st).color,
		mutations = mutations,
		starMultiplier = starMultiplier,
		mutationMultiplier = mutationMultiplier,
		mutationRaw = mutationRaw,
		mutationCapped = mutationCapped,
		totalMultiplier = starMultiplier * mutationMultiplier,
		incomePerSecond = EconomyBalance.FishIncome(record.id, record.w, record.st, record.mu),
		sellValue = EconomyBalance.SellValue(record.id, record.w, record.st, record.mu),
		primary = MutationData.GetPrimary(record.mu),
		tier = FishDisplay.CelebrationTier(record, gainedIds),
	}
end

return FishDisplay
