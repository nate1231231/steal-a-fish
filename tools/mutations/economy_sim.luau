-- Economy simulation on the REAL ModuleScripts (LootRoller, MutationRoller, EventSchedule, EconomyBalance).
-- Run: python tools/mutations/run_luau.py sim   -> prints tables, writes items/mutation_balance.json
--
-- Player model (same as tools/items/balance_sim.py so results are comparable):
--   casts nonstop at 60% efficiency, keeps the most valuable fish in the tank and sells the rest,
--   buys the cheapest next net/tank, rebirths when the rebirth is cheaper than the next upgrade.
--   Every player starts at a different real-world time, so they live through different events.
--   No boosts, gamepasses or stealing (steals move fish between players; they create no new fish).

local NetData = require(ref("NetData"))
local TankData = require(ref("TankData"))
local EconomyBalance = require(ref("EconomyBalance"))
local LootRoller = require(ref("LootRoller"))
local MutationRoller = require(ref("MutationRoller"))
local EventSchedule = require(ref("EventSchedule"))
local MutationData = require(ref("MutationData"))
local StarConfig = require(ref("StarConfig"))
local FishData = require(ref("FishData"))

local PLAYERS, HOURS, EFFICIENCY = 40, 12, 0.6

local function median(list)
	if #list == 0 then
		return 0
	end
	local copy = table.clone(list)
	table.sort(copy)
	local mid = (#copy + 1) / 2
	return (copy[math.floor(mid)] + copy[math.ceil(mid)]) / 2
end

local function simulate(seed, features)
	local random = Random.new(seed)
	local startTime = 1793000000 + random:NextNumber() * 86400 * 14
	local t, cash, net, tank, rebirths = 0, 0, 1, 1, 0
	local fish = {} -- { value, stars, mutated }
	local milestones, hourly = {}, {}
	local nextHour = 3600
	local catches, mutatedCatches = 0, 0
	while t < HOURS * 3600 do
		local netItem, tankItem = NetData.List[net], TankData.List[tank]
		local dt = EconomyBalance.BASE_CAST_SECONDS / netItem.catchSpeed / EFFICIENCY
		local income = 0
		for _, f in ipairs(fish) do
			income += f.value
		end
		income *= tankItem.incomeMultiplier * EconomyBalance.RebirthMultiplier(rebirths)
		t += dt
		cash += income * dt
		while t >= nextHour do
			local stars, mutated = 0, 0
			for _, f in ipairs(fish) do
				stars += f.stars
				mutated += f.mutated and 1 or 0
			end
			table.insert(hourly, { net = net, tank = tank, rebirths = rebirths, income = income,
				avgStars = #fish > 0 and stars / #fish or 0, mutatedShare = #fish > 0 and mutated / #fish or 0 })
			nextHour += 3600
		end

		local catch = LootRoller.RollFish({ netId = netItem.id, rebirths = rebirths, random = random })
		local entry
		catches += 1
		if features then
			local record = MutationRoller.CreateCatch(catch, { eventId = EventSchedule.GetActiveEventId(startTime + t),
				luck = catch.luckUsed, random = random, uid = "", now = 0 })
			entry = { value = EconomyBalance.RecordIncome(record), stars = record.st, mutated = #record.mu > 0 }
			if entry.mutated then
				mutatedCatches += 1
				milestones.first_mutation = milestones.first_mutation or t
			end
			if record.st == 5 then
				milestones.first_5star = milestones.first_5star or t
			end
		else
			entry = { value = catch.cashPerSecond, stars = 1, mutated = false }
		end
		local key = "first_" .. catch.rarity
		milestones[key] = milestones[key] or t

		if #fish < tankItem.capacity then
			table.insert(fish, entry)
		else
			local lowIndex = 1
			for i = 2, #fish do
				if fish[i].value < fish[lowIndex].value then
					lowIndex = i
				end
			end
			if entry.value > fish[lowIndex].value then
				cash += fish[lowIndex].value * EconomyBalance.SELL_SECONDS
				fish[lowIndex] = entry
			else
				cash += entry.value * EconomyBalance.SELL_SECONDS
			end
		end

		while true do
			local options = {}
			if net < #NetData.List then
				table.insert(options, { "net", NetData.List[net + 1].price })
			end
			if tank < #TankData.List then
				table.insert(options, { "tank", TankData.List[tank + 1].price })
			end
			table.sort(options, function(a, b)
				return a[2] < b[2]
			end)
			local rebirthCost = EconomyBalance.RebirthCost(rebirths)
			if options[1] and cash >= options[1][2] then
				cash -= options[1][2]
				if options[1][1] == "net" then
					net += 1
					milestones["net_" .. net] = t
				else
					tank += 1
					milestones["tank_" .. tank] = t
				end
			elseif (not options[1] or rebirthCost < options[1][2]) and cash >= rebirthCost then
				rebirths += 1
				milestones["rebirth_" .. rebirths] = t
				cash = 0
				fish = {}
			else
				break
			end
		end
	end
	return milestones, hourly, mutatedCatches / catches
end

local function run(features, label)
	local all, hourlyAll, mutatedShares = {}, {}, {}
	for p = 1, PLAYERS do
		local milestones, hourly, mutatedShare = simulate(1000 + p, features)
		table.insert(all, milestones)
		table.insert(hourlyAll, hourly)
		table.insert(mutatedShares, mutatedShare)
	end
	local keys = {}
	for _, milestones in ipairs(all) do
		for k in pairs(milestones) do
			keys[k] = true
		end
	end
	local result = { milestones = {}, hourly = {}, mutatedCatchShare = median(mutatedShares) }
	local ordered = {}
	for k in pairs(keys) do
		local values = {}
		for _, milestones in ipairs(all) do
			if milestones[k] then
				table.insert(values, milestones[k] / 3600)
			end
		end
		result.milestones[k] = { medianHours = math.floor(median(values) * 100 + 0.5) / 100,
			reachedPct = math.floor(#values / PLAYERS * 100 + 0.5) }
		table.insert(ordered, k)
	end
	table.sort(ordered, function(a, b)
		return result.milestones[a].medianHours < result.milestones[b].medianHours
	end)
	print(("== %s"):format(label))
	for _, k in ipairs(ordered) do
		local m = result.milestones[k]
		print(("   %-16s median %6.2f h  reached %3d%%"):format(k, m.medianHours, m.reachedPct))
	end
	for h = 1, HOURS do
		local function col(name)
			local values = {}
			for _, hourly in ipairs(hourlyAll) do
				if hourly[h] then
					table.insert(values, hourly[h][name])
				end
			end
			return median(values)
		end
		local row = { hour = h, net = math.floor(col("net")), tank = math.floor(col("tank")),
			rebirths = math.floor(col("rebirths")), incomePerSecond = math.floor(col("income")),
			avgStars = math.floor(col("avgStars") * 100 + 0.5) / 100,
			mutatedShare = math.floor(col("mutatedShare") * 1000 + 0.5) / 1000 }
		table.insert(result.hourly, row)
		print(("   hour %2d  net %d  tank %d  rebirths %d  income %10d/s  tank avg stars %.2f  mutated %4.1f%%"):format(
			row.hour, row.net, row.tank, row.rebirths, row.incomePerSecond, row.avgStars, row.mutatedShare * 100))
	end
	print(("   mutated catches: %.2f%% of all catches"):format(result.mutatedCatchShare * 100))
	return result
end

-- ===================================================================== expected value table
local function valueTable()
	local function chanceActive(id)
		local mutation = MutationData.ById[id]
		return EventSchedule.EventProbability(id) * mutation.durationSeconds / EventSchedule.Config.slotSeconds
	end
	local p5 = StarConfig.Get(5).oddsPercent / 100
	local rows = {}
	local function add(label, stars, mutations, oneIn)
		local mult = EconomyBalance.FishValueMultiplier(stars, mutations)
		local _, raw = MutationData.CombineMultipliers(mutations)
		table.insert(rows, {
			label = label, stars = stars, mutations = #mutations, starMultiplier = StarConfig.GetMultiplier(stars),
			mutationRaw = raw, mutationMultiplier = EconomyBalance.MutationMultiplier(mutations), totalMultiplier = mult,
			bangusIncome = EconomyBalance.FishIncome("fish_bangus", FishData.ById.fish_bangus.weightMin, stars, mutations),
			bangusSell = EconomyBalance.SellValue("fish_bangus", FishData.ById.fish_bangus.weightMin, stars, mutations),
			tunaIncome = EconomyBalance.FishIncome("fish_tuna", FishData.ById.fish_tuna.weightMin, stars, mutations),
			tunaSell = EconomyBalance.SellValue("fish_tuna", FishData.ById.fish_tuna.weightMin, stars, mutations),
			oneInCatches = oneIn,
		})
	end
	local thunder = MutationData.ById.thunderstorm
	local bakunawa = MutationData.ById.bakunawa_eclipse
	add("Base fish (1 star, no mutation)", 1, {}, 1 / (StarConfig.Get(1).oddsPercent / 100))
	add("5 stars, no mutation", 5, {}, 1 / p5)
	add("5 stars + 1 mutation (Thunderstruck, most common)", 5, { "thunderstorm" },
		1 / (p5 * chanceActive("thunderstorm") * thunder.chance))
	add("5 stars + 1 mutation (Moon-Eaten, rarest)", 5, { "bakunawa_eclipse" },
		1 / (p5 * chanceActive("bakunawa_eclipse") * bakunawa.chance))
	add("5 stars + 3 mutations (3 most common)", 5, { "thunderstorm", "typhoon", "blood_moon" }, nil)
	add("5 stars + 3 mutations (3 rarest, capped)", 5, { "rainbow_bloom", "solar_eclipse", "bakunawa_eclipse" }, nil)
	local all = {}
	for _, mutation in ipairs(MutationData.List) do
		table.insert(all, mutation.id)
	end
	add("5 stars + all 8 mutations (capped)", 5, all, nil)
	print("== Expected value: base fish vs 5-star fish with 1, 3, 8 mutations (Bangus 6/s, Tuna 450/s base)")
	for _, row in ipairs(rows) do
		print(("   %-50s x%-6.2f bangus %8.1f/s  tuna %9.1f/s  %s"):format(row.label, row.totalMultiplier,
			row.bangusIncome, row.tunaIncome, row.oneInCatches and ("1 in %d catches"):format(math.floor(row.oneInCatches + 0.5))
				or "via steals across events"))
	end
	local average = EconomyBalance.ExpectedCatchMultiplier and EconomyBalance.ExpectedCatchMultiplier(0) or nil
	if average then
		print(("   average catch (luck 0): x%.3f   event uptime %.1f%%"):format(average, EconomyBalance.EventUptime() * 100))
	end
	return rows, average
end

-- ===================================================================== tiny JSON encoder
local function encode(value)
	local kind = type(value)
	if kind == "table" then
		if #value > 0 or next(value) == nil then
			local parts = {}
			for _, v in ipairs(value) do
				table.insert(parts, encode(v))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(value) do
			table.insert(keys, k)
		end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do
			table.insert(parts, ("%q:%s"):format(tostring(k), encode(value[k])))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif kind == "string" then
		return ("%q"):format(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge then
			return "null"
		end
		return tostring(value)
	elseif kind == "boolean" then
		return tostring(value)
	end
	return "null"
end

local baseline = run(false, "BASELINE: stars + mutations OFF (items-only game)")
local full = run(true, "FULL GAME: stars + mutations + world events ON")
local rows, average = valueTable()
print("JSON " .. encode({ baseline = baseline, full = full, valueTable = rows, averageCatchMultiplier = average,
	eventUptime = EventSchedule.ExpectedUptime(), players = PLAYERS }))
