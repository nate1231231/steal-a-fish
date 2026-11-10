--[[
	EventSchedule  (ModuleScript)
	Put in: ReplicatedStorage > Items > Modules > EventSchedule

	Deterministic world-event calendar. It is a PURE function of time:
		EventSchedule.GetState(workspace:GetServerTimeNow())
	Every server (and every player) that asks about the same moment gets the same answer, so all
	servers agree on the current event and countdown without MessagingService or DataStores.

	How it works
	  * Time since `epochUnix` is cut into slots of `slotSeconds` (40 min).
	  * Each slot gets ONE event, picked by a 32-bit hash of (seed, slot number) weighted by
	    MutationData scheduleWeight (rarer events appear less often).
	  * The event starts `startOffsetSeconds` (25 min) into its slot and lasts its durationSeconds
	    (max 15 min), so there is never more than one event at a time, and there is always a calm
	    gap of at least 25 minutes between two events.

	Clients may require this to preview the calendar, but the SERVER decides what is active
	(EventAuthority) and only the server rolls mutations.
]]

local MutationData = require(script.Parent.MutationData)

local EventSchedule = {}

EventSchedule.Config = {
	seed = 61610, -- change to reshuffle the whole calendar (every server follows the new one)
	epochUnix = 1767225600, -- 2026-01-01 00:00:00 UTC, slot 0 starts here
	slotSeconds = 40 * 60, -- one event per 40-minute slot
	startOffsetSeconds = 25 * 60, -- each event starts 25 min into its slot (guaranteed calm gap)
	calmWeight = 0, -- > 0 lets some slots have no event at all (weight next to scheduleWeight)
	countdownSeconds = 15 * 60, -- the UI only counts down during the final 15 minutes
	headsUpSeconds = { 15 * 60, 60 }, -- heads-up banners before an event starts
	lookaheadSlots = 64, -- how far GetNext searches (only matters if calmWeight is large)
}
table.freeze(EventSchedule.Config.headsUpSeconds)
table.freeze(EventSchedule.Config)

local Config = EventSchedule.Config
local TWO_32 = 4294967296

-- ===================================================================== validation + weights
local picks = {} -- { {eventId or false, cumulativeWeight} }
local totalWeight = 0
for _, mutation in ipairs(MutationData.List) do
	assert(
		mutation.durationSeconds <= Config.slotSeconds - Config.startOffsetSeconds,
		("EventSchedule: %s lasts %ds but a slot only has %ds after the start offset"):format(
			mutation.id, mutation.durationSeconds, Config.slotSeconds - Config.startOffsetSeconds)
	)
	if mutation.scheduleWeight > 0 then
		totalWeight += mutation.scheduleWeight
		table.insert(picks, { mutation.id, totalWeight })
	end
end
if Config.calmWeight > 0 then
	totalWeight += Config.calmWeight
	table.insert(picks, { false, totalWeight })
end
assert(totalWeight > 0, "EventSchedule: at least one event needs scheduleWeight > 0")

-- ===================================================================== deterministic hash
-- 32-bit multiply that stays exact in doubles (split into 16-bit halves)
local function mul32(a, b)
	local aLow, aHigh = a % 65536, (a - a % 65536) / 65536
	return (aLow * b + ((aHigh * b) % 65536) * 65536) % TWO_32
end

-- murmur3 finalizer: scrambles a 32-bit integer
local function mix32(x)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x85EBCA6B)
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = mul32(x, 0xC2B2AE35)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x
end

local seedMix = mix32(Config.seed % TWO_32)

-- Same number in [0, 1) for the same slot on every server
function EventSchedule.SlotRandom(slotIndex)
	local x = mix32(bit32.bxor(mix32(slotIndex % TWO_32), seedMix))
	return mix32(bit32.bxor(x, 0x9E3779B9)) / TWO_32
end

local function pickEvent(roll)
	local target = roll * totalWeight
	for _, entry in ipairs(picks) do
		if target < entry[2] then
			return entry[1] or nil
		end
	end
	return picks[#picks][1] or nil
end

-- ===================================================================== slots
local cache, cacheSize = {}, 0

function EventSchedule.ClearCache()
	cache, cacheSize = {}, 0
end

function EventSchedule.GetSlotIndex(serverTime)
	return math.floor((serverTime - Config.epochUnix) / Config.slotSeconds)
end

-- { index, slotStart, eventId (nil = calm slot), startsAt, endsAt }
function EventSchedule.GetSlot(slotIndex)
	local cached = cache[slotIndex]
	if cached then
		return cached
	end
	local slotStart = Config.epochUnix + slotIndex * Config.slotSeconds
	local eventId = pickEvent(EventSchedule.SlotRandom(slotIndex))
	local info = { index = slotIndex, slotStart = slotStart, eventId = eventId }
	if eventId then
		info.startsAt = slotStart + Config.startOffsetSeconds
		info.endsAt = info.startsAt + MutationData.ById[eventId].durationSeconds
	end
	table.freeze(info)
	if cacheSize >= 256 then
		EventSchedule.ClearCache()
	end
	cache[slotIndex] = info
	cacheSize += 1
	return info
end

-- The slot whose event is running at serverTime, or nil
function EventSchedule.GetActive(serverTime)
	local slot = EventSchedule.GetSlot(EventSchedule.GetSlotIndex(serverTime))
	if slot.eventId and serverTime >= slot.startsAt and serverTime < slot.endsAt then
		return slot
	end
	return nil
end

function EventSchedule.GetActiveEventId(serverTime)
	local active = EventSchedule.GetActive(serverTime)
	return active and active.eventId or nil
end

-- The next event that starts strictly AFTER serverTime
function EventSchedule.GetNext(serverTime)
	local first = EventSchedule.GetSlotIndex(serverTime)
	for index = first, first + Config.lookaheadSlots do
		local slot = EventSchedule.GetSlot(index)
		if slot.eventId and slot.startsAt > serverTime then
			return slot
		end
	end
	return nil
end

-- The next `count` events after serverTime (for a calendar UI or debugging)
function EventSchedule.ListUpcoming(serverTime, count)
	local list, t = {}, serverTime
	for _ = 1, count do
		local nextSlot = EventSchedule.GetNext(t)
		if not nextSlot then
			break
		end
		table.insert(list, nextSlot)
		t = nextSlot.startsAt
	end
	return list
end

--[[
	Full state for UI and server logic:
	{ now, activeEventId, activeStartsAt, activeEndsAt, secondsLeft,
	  nextEventId, nextStartsAt, secondsUntilNext, showCountdown }
]]
function EventSchedule.GetState(serverTime)
	local active = EventSchedule.GetActive(serverTime)
	local nextSlot = EventSchedule.GetNext(serverTime)
	local state = { now = serverTime, secondsLeft = 0, secondsUntilNext = math.huge, showCountdown = false }
	if active then
		state.activeEventId = active.eventId
		state.activeStartsAt = active.startsAt
		state.activeEndsAt = active.endsAt
		state.secondsLeft = active.endsAt - serverTime
	end
	if nextSlot then
		state.nextEventId = nextSlot.eventId
		state.nextStartsAt = nextSlot.startsAt
		state.secondsUntilNext = nextSlot.startsAt - serverTime
		state.showCountdown = active == nil and state.secondsUntilNext <= Config.countdownSeconds
	end
	return state
end

-- ===================================================================== statistics (economy + UI)
-- Chance that a given slot holds this event
function EventSchedule.EventProbability(eventId)
	local mutation = MutationData.ById[eventId]
	return mutation and mutation.scheduleWeight / totalWeight or 0
end

-- Fraction of all time where SOME event is active (about 0.23 with the default config)
function EventSchedule.ExpectedUptime()
	local seconds = 0
	for _, mutation in ipairs(MutationData.List) do
		seconds += EventSchedule.EventProbability(mutation.id) * mutation.durationSeconds
	end
	return seconds / Config.slotSeconds
end

-- Average real hours between two occurrences of this event
function EventSchedule.AverageHoursBetween(eventId)
	local probability = EventSchedule.EventProbability(eventId)
	return probability > 0 and Config.slotSeconds / probability / 3600 or math.huge
end

-- 899 -> "14:59", 3725 -> "1:02:05"
function EventSchedule.FormatCountdown(seconds)
	seconds = math.max(0, math.ceil(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, secs)
	end
	return ("%d:%02d"):format(minutes, secs)
end

return EventSchedule
