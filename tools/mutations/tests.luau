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

-- ===================================================================== (later phases append tests below)
--@@MORE_TESTS@@

print(("RESULT: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("tests failed")
end
