--[[
	MutationRoller  (ModuleScript, SERVER ONLY)
	Put in: ServerStorage > Items > ServerModules > MutationRoller

	Rolls star grades and mutations. Pure logic: no Instances, no RemoteEvents, so it is unit
	tested outside Roblox (tools/mutations/tests.luau). MutationService calls it for you.

	When rolls happen
	  * CATCH: LootRoller.RollFish picks the species + weight, then CreateCatch rolls:
	      stars    = quality from weight + a size roll (StarConfig)
	      mutation = the ACTIVE event's mutation, with chance MutationData chance * luck bonus
	  * STEAL: ApplySteal gives the stolen fish a FRESH roll for the active event's mutation.
	    It keeps its stars and old mutations, so a fish can collect up to 8 mutations by being
	    stolen during different events.
	  * No active event = no mutation. Ever.

	================  ANTI-EXPLOIT RULES  ================
	1. Only the server requires this (it lives in ServerStorage, invisible to clients).
	2. `eventId` must come from EventAuthority.GetActiveEventId() on the server. Never from a
	   RemoteEvent, a client attribute, or a client-reported time.
	3. Clients never send stars, mutations, size, weight or the event. The client only says
	   "I cast" / "I stole fish <uid>"; the server checks the steal itself (distance, prompt time
	   from EconomyBalance.StealSeconds, the fish really is in the victim's tank).
	4. Roll exactly once per catch and once per successful steal. A failed or cancelled steal
	   must not roll (otherwise thieves could farm mutations by spamming attempts).
	5. Save the returned record to the player's server-side data FIRST, then tell the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")
local StarConfig = require(Modules:WaitForChild("StarConfig"))
local MutationData = require(Modules:WaitForChild("MutationData"))
local EconomyBalance = require(Modules:WaitForChild("EconomyBalance"))
local FishSchema = require(script.Parent.FishSchema)

local MutationRoller = {}

local serverRandom = Random.new()

-- Star roll. Returns stars, sizeFraction, quality.
function MutationRoller.RollQuality(weightFraction, random)
	local sizeFraction = (random or serverRandom):NextNumber()
	local quality = StarConfig.QualityFromRolls(weightFraction, sizeFraction)
	return StarConfig.QualityToStars(quality), sizeFraction, quality
end

-- Chance (0..maxChance) to gain `mutationId` on one roll
function MutationRoller.GetChance(mutationId, luck, source)
	local mutation = MutationData.ById[mutationId]
	if mutation == nil then
		return 0
	end
	local rules = MutationData.Rules
	local chance = mutation.chance * (1 + rules.luckChanceBonus * math.max(tonumber(luck) or 0, 0))
	if source == "Steal" then
		chance *= rules.stealChanceMultiplier
	end
	return math.clamp(chance, 0, rules.maxChance)
end

--[[
	One mutation roll for the active event.
	context = { eventId = <from EventAuthority>, luck = number, source = "Catch" | "Steal", random = Random? }
	Returns the gained mutation id, or nil plus a reason ("NoEvent", "AlreadyHas", "Full", "Missed").
]]
function MutationRoller.RollMutation(currentMutations, context)
	local eventId = context.eventId
	if not MutationData.IsValid(eventId) then
		return nil, "NoEvent"
	end
	currentMutations = currentMutations or {}
	if MutationData.Has(currentMutations, eventId) then
		return nil, "AlreadyHas"
	end
	if #currentMutations >= MutationData.Rules.maxMutationsPerFish then
		return nil, "Full"
	end
	local random = context.random or serverRandom
	if random:NextNumber() < MutationRoller.GetChance(eventId, context.luck, context.source) then
		return eventId
	end
	return nil, "Missed"
end

--[[
	A freshly caught fish.
	catch   = result of LootRoller.RollFish ({ fishId, weightKg, ... })
	context = { eventId, luck, random?, uid, now, ownerUserId }
	Returns record (FishSchema v2), gained (array of new mutation ids)
]]
function MutationRoller.CreateCatch(catch, context)
	local random = context.random or serverRandom
	local weightFraction = EconomyBalance.WeightFraction(catch.fishId, catch.weightKg)
	local stars, sizeFraction = MutationRoller.RollQuality(weightFraction, random)
	local gained = {}
	local mutationId = MutationRoller.RollMutation({}, {
		eventId = context.eventId,
		luck = context.luck,
		source = "Catch",
		random = random,
	})
	if mutationId then
		table.insert(gained, mutationId)
	end
	local record = FishSchema.New({
		uid = context.uid,
		fishId = catch.fishId,
		weightKg = catch.weightKg,
		sizeFraction = sizeFraction,
		stars = stars,
		mutations = gained,
		caughtAt = context.now,
		ownerUserId = context.ownerUserId,
	})
	return record, gained
end

--[[
	A fish that was just stolen successfully. Returns a NEW record (the input is not changed)
	and the array of gained mutation ids (empty or one id).
	context = { eventId, luck, random? }
]]
function MutationRoller.ApplySteal(record, context)
	local copy = FishSchema.Copy(record)
	copy.sc = (copy.sc or 0) + 1
	local gained = {}
	local mutationId = MutationRoller.RollMutation(copy.mu, {
		eventId = context.eventId,
		luck = context.luck,
		source = "Steal",
		random = context.random,
	})
	if mutationId then
		table.insert(copy.mu, mutationId)
		copy.mu = MutationData.Sanitize(copy.mu)
		table.insert(gained, mutationId)
	end
	return copy, gained
end

return MutationRoller
