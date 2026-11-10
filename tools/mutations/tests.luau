-- Unit tests for stars, mutations, the event scheduler and the economy extension.
-- Run: python tools/mutations/run_luau.py tests   (bundles the real ModuleScripts with Roblox stubs)

local passed, failed = 0, 0
local function check(condition, message)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. message)
	end
end
local function section(name)
	print(("== %s"):format(name))
end
local function near(a, b, tolerance)
	return math.abs(a - b) <= tolerance
end

local MutationData = require(ref("MutationData"))
local EventSchedule = require(ref("EventSchedule"))
local Config = EventSchedule.Config

-- ===================================================================== scheduler
section("EventSchedule: same answer from any server, any cache state")
do
	local rng = Random.new(42)
	local mismatches = 0
	for _ = 1, 3000 do
		local t = 1767225600 + rng:NextNumber() * 86400 * 3650
		local warm = EventSchedule.GetState(t)
		EventSchedule.ClearCache()
		local cold = EventSchedule.GetState(t)
		if warm.activeEventId ~= cold.activeEventId or warm.nextEventId ~= cold.nextEventId
			or warm.nextStartsAt ~= cold.nextStartsAt or warm.activeEndsAt ~= cold.activeEndsAt then
			mismatches += 1
		end
	end
	check(mismatches == 0, "warm vs cold cache mismatches: " .. mismatches)

	-- three "servers" that booted at different times and poll at different rates
	local servers = { { boot = 1793000000, step = 0.5 }, { boot = 1793000000 - 86400 * 9.3, step = 7 },
		{ boot = 1793000000 + 1234.5, step = 13 } }
	local queryTimes = {}
	for k = 1, 400 do
		table.insert(queryTimes, 1793000000 + 2000 + k * 997.3)
	end
	local answers = {}
	for s, server in ipairs(servers) do
		EventSchedule.ClearCache()
		local t = server.boot
		while t < server.boot + 600 do -- warm up like a running server
			EventSchedule.GetState(t)
			t += server.step
		end
		answers[s] = {}
		for _, q in ipairs(queryTimes) do
			local st = EventSchedule.GetState(q)
			answers[s][q] = (st.activeEventId or "-") .. "|" .. (st.nextEventId or "-") .. "|" .. st.nextStartsAt
		end
	end
	local disagree = 0
	for _, q in ipairs(queryTimes) do
		if answers[1][q] ~= answers[2][q] or answers[1][q] ~= answers[3][q] then
			disagree += 1
		end
	end
	check(disagree == 0, "servers disagree at " .. disagree .. " query times")
end

section("EventSchedule: one event at a time, calm gaps, countdown consistency (7 days, 5 s steps)")
do
	local start = 1793000000
	local previousId, currentStart, lastEnd = nil, nil, nil
	local minGap, events, activeSeconds = math.huge, 0, 0
	local badDuration, badCountdown, badNext = 0, 0, 0
	local expectedNextStart = nil
	local step = 5
	for t = start, start + 7 * 86400, step do
		local state = EventSchedule.GetState(t)
		local id = state.activeEventId
		if id then
			activeSeconds += step
		end
		if id ~= previousId then
			if id then -- an event began
				events += 1
				currentStart = state.activeStartsAt
				if lastEnd then
					minGap = math.min(minGap, currentStart - lastEnd)
				end
				if expectedNextStart and expectedNextStart ~= currentStart then
					badNext += 1
				end
				if state.activeEndsAt - state.activeStartsAt ~= MutationData.ById[id].durationSeconds then
					badDuration += 1
				end
			else
				lastEnd = t - (t - currentStart) + MutationData.ById[previousId].durationSeconds
			end
			previousId = id
		end
		if not id then
			-- while calm, "now + countdown" must always point at the same start time
			expectedNextStart = state.nextStartsAt
			if state.nextStartsAt ~= t + state.secondsUntilNext then
				badCountdown += 1
			end
			if state.showCountdown ~= (state.secondsUntilNext <= Config.countdownSeconds) then
				badCountdown += 1
			end
		end
	end
	check(events >= 200, "events in 7 days: " .. events)
	check(minGap >= Config.startOffsetSeconds, ("minimum calm gap %.0fs >= %ds"):format(minGap, Config.startOffsetSeconds))
	check(badDuration == 0, "events with the wrong duration: " .. badDuration)
	check(badCountdown == 0, "countdown inconsistencies: " .. badCountdown)
	check(badNext == 0, "events that started at a different time than the countdown promised: " .. badNext)
	local uptime = activeSeconds / (7 * 86400)
	check(near(uptime, EventSchedule.ExpectedUptime(), 0.03),
		("uptime %.3f vs expected %.3f"):format(uptime, EventSchedule.ExpectedUptime()))
	print(("   %d events in 7 days, min gap %.0f min, uptime %.1f%% (expected %.1f%%)"):format(
		events, minGap / 60, uptime * 100, EventSchedule.ExpectedUptime() * 100))
end

section("EventSchedule: 200,000 slots match scheduleWeight (rarer events less often)")
do
	local counts, N = {}, 200000
	for index = 1, N do
		local id = EventSchedule.GetSlot(index).eventId or "calm"
		counts[id] = (counts[id] or 0) + 1
	end
	for _, mutation in ipairs(MutationData.List) do
		local expected = EventSchedule.EventProbability(mutation.id)
		local got = (counts[mutation.id] or 0) / N
		local tolerance = math.max(0.1 * expected, 0.0015)
		check(near(got, expected, tolerance), ("%s slot share %.4f vs %.4f"):format(mutation.id, got, expected))
		print(("   %-17s expected %6.2f%%  scheduled %6.2f%%  every %.1f h on average"):format(
			mutation.id, expected * 100, got * 100, EventSchedule.AverageHoursBetween(mutation.id)))
	end
	for i = 2, #MutationData.List do
		local a, b = MutationData.List[i - 1], MutationData.List[i]
		check(b.scheduleWeight <= a.scheduleWeight and b.multiplier >= a.multiplier,
			"rarer events must be less frequent and worth more: " .. b.id)
	end
end

section("EventSchedule: edge cases")
do
	check(EventSchedule.FormatCountdown(899) == "14:59", "format 14:59 got " .. EventSchedule.FormatCountdown(899))
	check(EventSchedule.FormatCountdown(3725) == "1:02:05", "format 1:02:05")
	check(EventSchedule.FormatCountdown(-5) == "0:00", "format negative")
	local early = EventSchedule.GetState(1700000000) -- before the epoch
	check(early.nextEventId ~= nil and early.nextStartsAt > 1700000000, "works before the epoch")
	local slot = EventSchedule.GetSlot(1000)
	check(EventSchedule.GetActiveEventId(slot.startsAt) == slot.eventId, "active at start second")
	check(EventSchedule.GetActiveEventId(slot.endsAt) == nil, "inactive at end second")
	check(EventSchedule.GetActiveEventId(slot.startsAt - 0.001) == nil, "inactive just before start")
	check(#EventSchedule.ListUpcoming(slot.startsAt, 5) == 5, "ListUpcoming")
end


-- ===================================================================== stars + mutation roller
local StarConfig = require(ref("StarConfig"))
local MutationRoller = require(ref("MutationRoller"))
local LootRoller = require(ref("LootRoller"))
local FishSchema = require(ref("FishSchema"))
local FishDisplay = require(ref("FishDisplay"))
local EconomyBalance = require(ref("EconomyBalance"))

-- 4.5 standard deviations of a binomial share: loose enough to never flake, tight enough to catch bugs
local function binomialTolerance(p, n)
	return math.max(4.5 * math.sqrt(p * (1 - p) / n), 1e-9)
end

section("Stars: 200,000 real catches (LootRoller -> CreateCatch) match StarConfig odds")
do
	local random = Random.new(7)
	local counts, N, mutatedOutsideEvents = {}, 200000, 0
	for i = 1, N do
		local catch = LootRoller.RollFish({ netId = "net_basic", random = random })
		local record, gained = MutationRoller.CreateCatch(catch, { eventId = nil, luck = 0, random = random, uid = tostring(i) })
		counts[record.st] = (counts[record.st] or 0) + 1
		if #gained > 0 or #record.mu > 0 then
			mutatedOutsideEvents += 1
		end
	end
	for _, grade in ipairs(StarConfig.Grades) do
		local expected = grade.oddsPercent / 100
		local got = (counts[grade.stars] or 0) / N
		check(near(got, expected, binomialTolerance(expected, N)), ("%d stars %.4f vs %.4f"):format(grade.stars, got, expected))
		print(("   %d stars  expected %6.2f%%  rolled %6.2f%%  x%.2f"):format(grade.stars, expected * 100, got * 100, grade.multiplier))
	end
	check(mutatedOutsideEvents == 0, "mutations rolled with no active event: " .. mutatedOutsideEvents)
	check(near(StarConfig.ExpectedMultiplier(), 1.147, 0.001), "expected star multiplier " .. StarConfig.ExpectedMultiplier())
end

section("Mutations: 200,000 rolls per event match the configured chance (luck 0 and luck 2.5)")
do
	local random = Random.new(99)
	for _, mutation in ipairs(MutationData.List) do
		for _, luck in ipairs({ 0, 2.5 }) do
			local N = luck == 0 and 200000 or 50000
			local hits = 0
			for _ = 1, N do
				if MutationRoller.RollMutation({}, { eventId = mutation.id, luck = luck, source = "Catch", random = random }) then
					hits += 1
				end
			end
			local expected = MutationRoller.GetChance(mutation.id, luck, "Catch")
			local got = hits / N
			check(near(got, expected, binomialTolerance(expected, N)),
				("%s luck %.1f: %.5f vs %.5f"):format(mutation.id, luck, got, expected))
			if luck == 0 then
				print(("   %-17s chance %5.2f%%  rolled %5.2f%%  (luck 2.5: %5.2f%%)"):format(
					mutation.id, expected * 100, got * 100, MutationRoller.GetChance(mutation.id, 2.5, "Catch") * 100))
			end
		end
	end
	check(MutationRoller.GetChance("thunderstorm", 1000, "Catch") == MutationData.Rules.maxChance, "chance capped at maxChance")
	check(MutationRoller.GetChance("not_real", 1, "Catch") == 0, "unknown mutation has 0 chance")
end

section("Mutations: only the active event can roll, no duplicates, max 8")
do
	local random = Random.new(5)
	local id, reason = MutationRoller.RollMutation({}, { eventId = nil, random = random })
	check(id == nil and reason == "NoEvent", "no event -> no roll")
	id, reason = MutationRoller.RollMutation({}, { eventId = "fake_event", random = random })
	check(id == nil and reason == "NoEvent", "unknown event -> no roll")
	id, reason = MutationRoller.RollMutation({ "aurora" }, { eventId = "aurora", random = random })
	check(id == nil and reason == "AlreadyHas", "duplicate blocked")
	local allIds = {}
	for _, mutation in ipairs(MutationData.List) do
		table.insert(allIds, mutation.id)
	end
	-- the scheduler only ever reports one active event; the roller must only ever give that one
	local wrong = 0
	for _ = 1, 5000 do
		local t = 1793000000 + random:NextNumber() * 86400 * 30
		local active = EventSchedule.GetActiveEventId(t)
		local gained = MutationRoller.RollMutation({}, { eventId = active, luck = 50, random = random })
		if gained ~= nil and gained ~= active then
			wrong += 1
		end
		if active == nil and gained ~= nil then
			wrong += 1
		end
	end
	check(wrong == 0, "rolled a mutation that was not the active event: " .. wrong)
end

section("Steals: fresh roll, keeps stars + old mutations, can collect all 8, capped value")
do
	local random = Random.new(11)
	local base = FishSchema.New({ uid = "u1", fishId = "fish_bangus", weightKg = 1.0, sizeFraction = 0.9, stars = 4,
		mutations = { "thunderstorm" }, caughtAt = 1, ownerUserId = 1 })
	local N, gainedCount = 200000, 0
	for _ = 1, N do
		local stolen, gained = MutationRoller.ApplySteal(base, { eventId = "golden_tide", luck = 0, random = random })
		if #gained == 1 then
			gainedCount += 1
		end
	end
	local expected = MutationRoller.GetChance("golden_tide", 0, "Steal")
	check(near(gainedCount / N, expected, binomialTolerance(expected, N)),
		("steal fresh roll %.5f vs %.5f"):format(gainedCount / N, expected))
	check(#base.mu == 1 and base.sc == 0, "ApplySteal must not modify the original record")
	-- keep stealing the same fish through every event until it holds all 8
	local fish = base
	for _, mutation in ipairs(MutationData.List) do
		local tries = 0
		repeat
			local gained
			fish, gained = MutationRoller.ApplySteal(fish, { eventId = mutation.id, luck = 100, random = random })
			tries += 1
		until MutationData.Has(fish.mu, mutation.id) or tries > 10000
	end
	check(#fish.mu == 8 and fish.st == 4, "fish collected all 8 mutations and kept 4 stars")
	local _, reason = MutationRoller.RollMutation(fish.mu, { eventId = "thunderstorm", random = random })
	check(reason == "AlreadyHas", "9th mutation impossible")
	check(fish.mu[1] == "bakunawa_eclipse" and fish.mu[8] == "thunderstorm", "mutations stored rarest first")
	local total, raw, capped = MutationData.CombineMultipliers(fish.mu)
	check(total == MutationData.Rules.multiplierCap and raw == 27 and capped, ("all 8: x%s raw x%s"):format(total, raw))
end

section("Stacking formula + hard cap")
do
	check(MutationData.CombineMultipliers({}) == 1, "empty = x1")
	check(MutationData.CombineMultipliers({ "thunderstorm" }) == 2, "single = its multiplier")
	check(MutationData.CombineMultipliers({ "golden_tide", "thunderstorm" }) == 5, "additive: 1 + 3 + 1 = 5")
	check(MutationData.CombineMultipliers({ "thunderstorm", "thunderstorm", "nope" }) == 2, "duplicates/unknown ignored")
	check(MutationData.CombineMultipliers({ "thunderstorm", "typhoon", "blood_moon" }) == 5.5, "3 common = 1+1+1.5+2")
	local multiplicative = table.clone(MutationData.Rules)
	multiplicative.stacking = "Multiplicative"
	check(MutationData.CombineMultipliers({ "golden_tide", "thunderstorm" }, multiplicative) == 8, "multiplicative 4*2")
	local highest = table.clone(MutationData.Rules)
	highest.stacking = "Highest"
	check(MutationData.CombineMultipliers({ "golden_tide", "thunderstorm" }, highest) == 4, "highest")
	-- random subsets can never beat the cap, and the full value multiplier never beats 2 x cap
	local random, worst = Random.new(3), 0
	for _ = 1, 20000 do
		local subset = {}
		for _, mutation in ipairs(MutationData.List) do
			if random:NextNumber() < 0.5 then
				table.insert(subset, mutation.id)
			end
		end
		local stars = 1 + math.floor(random:NextNumber() * 5)
		worst = math.max(worst, EconomyBalance.FishValueMultiplier(stars, subset))
	end
	local maxPossible = StarConfig.Get(5).multiplier * MutationData.Rules.multiplierCap
	check(worst <= maxPossible, ("value multiplier %.2f <= %.2f"):format(worst, maxPossible))
	check(EconomyBalance.FishIncome("fish_bangus", 0.3, 5, { "golden_tide", "thunderstorm" }) == 60, "bangus 6 x2 x5 = 60/s")
	check(EconomyBalance.SellValue("fish_bangus", 0.3, 5, { "golden_tide", "thunderstorm" }) == 1800, "sell 60 x 30")
	check(EconomyBalance.FishIncome("fish_bangus", 0.3) == 6, "old 2-argument call unchanged")
	local income = EconomyBalance.IncomePerSecond({ tankId = "tank_balde",
		fish = { { id = "fish_bangus", weightKg = 0.3, stars = 2, mutations = { "aurora" } } } })
	check(near(income, 6 * 1.15 * 3.5, 0.06), "IncomePerSecond uses stars + mutations (0.1 rounding) " .. income)
end

section("FishSchema (DataStore v2) + FishDisplay")
do
	local migrated = FishSchema.Migrate({ id = "fish_bangus", w = 1.8 })
	check(migrated.v == 2 and #migrated.mu == 0 and migrated.sz == 0.5, "v1 -> v2 defaults")
	check(migrated.st == StarConfig.QualityToStars(0.75), "v1 stars derived from weight deterministically")
	check(FishSchema.Migrate({ fishId = "fish_tuna", weightKg = 30 }).id == "fish_tuna", "legacy field names")
	local dirty = FishSchema.Migrate({ v = 2, uid = 5, id = "fish_bangus", w = 999, sz = 7, st = 9,
		mu = { "x", "golden_tide", "golden_tide", 4 }, sc = -3 })
	check(dirty.w == 1.8 and dirty.sz == 1 and dirty.st == 5 and #dirty.mu == 1 and dirty.sc == 0 and dirty.uid == "5",
		"sanitize clamps a corrupted record")
	check(FishSchema.Migrate({ id = "fish_removed", w = 1 }) == nil, "unknown species dropped")
	local list, dropped = FishSchema.MigrateList({ { id = "fish_dilis", w = 0.01 }, { id = "gone" }, "junk" })
	check(#list == 1 and dropped == 2, "MigrateList")
	check(FishDisplay.StarText(3) == "★★★☆☆", "StarText")
	check(FishDisplay.FormatName("fish_bangus", { "thunderstorm", "golden_tide" }) == "Golden Thunderstruck Bangus",
		"name prefixes: " .. FishDisplay.FormatName("fish_bangus", { "thunderstorm", "golden_tide" }))
	check(FishDisplay.FormatName("fish_bangus", { "thunderstorm", "golden_tide", "aurora", "typhoon" })
		== "Golden Aurora Bangus +2", "prefix limit")
	check(FishDisplay.ToolName({ id = "fish_tilapia", st = 4, mu = { "blood_moon" } }) == "★4 Crimson Tilapia", "ToolName")
	check(FishDisplay.CelebrationTier({ id = "fish_dilis", st = 1, mu = {} }, {}) == "Normal", "tier normal")
	check(FishDisplay.CelebrationTier({ id = "fish_dilis", st = 1, mu = { "thunderstorm" } }, { "thunderstorm" }) == "Great", "tier great")
	check(FishDisplay.CelebrationTier({ id = "fish_dilis", st = 5, mu = {} }, {}) == "Epic", "tier 5 stars")
	check(FishDisplay.CelebrationTier({ id = "fish_dilis", st = 1, mu = { "rainbow_bloom" } }, { "rainbow_bloom" }) == "Legendary", "tier rare mutation")
	check(FishDisplay.Abbreviate(12500) == "12.5K" and FishDisplay.Abbreviate(3000000) == "3M", "abbreviate " .. FishDisplay.Abbreviate(3000000))
	local d = FishDisplay.Describe({ id = "fish_bangus", w = 0.3, st = 5, mu = { "golden_tide", "thunderstorm" } }, { "golden_tide" })
	check(d.totalMultiplier == 10 and d.incomePerSecond == 60 and d.mutations[1].isNew and not d.mutations[2].isNew, "Describe")
end

section("EconomyBalance: event frequency + expected catch value (200,000 catches at random times)")
do
	check(near(EconomyBalance.EventUptime(), EventSchedule.ExpectedUptime(), 1e-12), "EventUptime")
	local random = Random.new(21)
	local N, sum, mutated = 200000, 0, 0
	for _ = 1, N do
		local t = 1793000000 + random:NextNumber() * 86400 * 60
		local catch = LootRoller.RollFish({ netId = "net_basic", random = random })
		local record = MutationRoller.CreateCatch(catch, { eventId = EventSchedule.GetActiveEventId(t), luck = 0, random = random })
		sum += EconomyBalance.FishValueMultiplier(record.st, record.mu)
		if #record.mu > 0 then
			mutated += 1
		end
	end
	local expectedShare = EconomyBalance.MutationChancePerCast(0)
	check(near(mutated / N, expectedShare, binomialTolerance(expectedShare, N)),
		("mutated share %.5f vs %.5f"):format(mutated / N, expectedShare))
	check(near(sum / N, EconomyBalance.ExpectedCatchMultiplier(0), 0.01),
		("average catch multiplier %.4f vs %.4f"):format(sum / N, EconomyBalance.ExpectedCatchMultiplier(0)))
	print(("   mutated catches %.2f%% (expected %.2f%%), average value x%.3f (expected x%.3f)"):format(
		mutated / N * 100, expectedShare * 100, sum / N, EconomyBalance.ExpectedCatchMultiplier(0)))
	local table_ = EconomyBalance.ValueTable
	check(#table_ == 7 and table_[1].totalMultiplier == 1 and table_[#table_].totalMultiplier
		== StarConfig.Get(5).multiplier * MutationData.Rules.multiplierCap, "ValueTable rows (run the sim, then gen_luau)")
	check(EconomyBalance.Milestones.net_8 ~= nil and EconomyBalance.Milestones.net_8 >= 9 and EconomyBalance.Milestones.net_8 <= 11,
		"full-game Golden Trawl stays near 10 hours: " .. tostring(EconomyBalance.Milestones.net_8))
end

--@@MORE_TESTS@@

print(("RESULT: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("tests failed")
end
