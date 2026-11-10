--[[
	LootRoller  (ModuleScript, SERVER ONLY)
	Put in: ServerStorage > Items > ServerModules > LootRoller

	Rolls which fish a player catches. Two steps:
	  1. Pick a RARITY with weighted odds. Luck makes rare rarities heavier:
	       weight = RarityConfig weight * (1 + luck) ^ luckExponent
	     (Common has exponent 0, so luck never changes its weight; Mythic has 2, so luck helps it most.)
	  2. Pick a FISH inside that rarity using each fish's catchWeight, then roll its weight in kg.
	     Heavier fish earn up to +25% income (see EconomyBalance.FishIncome).

	Odds at a glance (percent per cast):
	  luck 0   (Basic Net)        Common 76.7 | Rare 20.4 | Epic 2.6 | Legendary 0.31 | Mythic 0.012
	  luck 2.5 (Golden Trawl)     Common 60.8 | Rare 30.4 | Epic 7.1 | Legendary 1.6  | Mythic 0.12
	  Call LootRoller.GetOdds(luck) to show live odds in your UI.

	================  ANTI-EXPLOIT RULES (please read)  ================
	1. Only require this from server Scripts. It lives in ServerStorage so clients can't even see it.
	2. The client should only say "I want to cast" (a RemoteEvent with NO arguments). The SERVER
	   decides which net the player owns, how much luck they have, and which fish comes out.
	   Never accept netId, luck, fishId, rarity, weight or cash values from the client.
	3. Enforce the cast cooldown on the server with LootRoller.CanCast(). Exploiters can fire a
	   RemoteEvent thousands of times per second; ignore casts that come in too fast.
	4. Luck must come from server-side state only: the net saved in the player's data, boosts the
	   server started (with server timestamps), gamepasses checked with
	   MarketplaceService:UserOwnsGamePassAsync, and the player's saved rebirth count.
	5. Luck is clamped to MAX_LUCK so a bug or corrupted save can't produce endless Mythics.
	6. One Random object lives on the server. Never let a client choose or see a seed.
	7. Put the caught fish straight into the player's server-side data, THEN tell the client what
	   they caught (for the UI and animation only).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")

local RarityConfig = require(Modules:WaitForChild("RarityConfig"))
local FishData = require(Modules:WaitForChild("FishData"))
local NetData = require(Modules:WaitForChild("NetData"))
local EconomyBalance = require(Modules:WaitForChild("EconomyBalance"))

local LootRoller = {}

-- Safety cap: Golden Trawl (2.5) + Luck Potion (1) + VIP (0.25) + 10 rebirths (1) is about 4.75.
LootRoller.MAX_LUCK = 10

-- One random generator for the whole server
local serverRandom = Random.new()

-- Group fish by rarity once, so every roll is fast
local fishByRarity = {}
for _, fish in ipairs(FishData.List) do
	if fishByRarity[fish.rarity] == nil then
		fishByRarity[fish.rarity] = {}
	end
	table.insert(fishByRarity[fish.rarity], fish)
end

-- Picks one entry from a list, where bigger weight = more likely.
local function pickWeighted(entries, getWeight, random)
	local total = 0
	for _, entry in ipairs(entries) do
		total += getWeight(entry)
	end
	local roll = random:NextNumber() * total
	for _, entry in ipairs(entries) do
		roll -= getWeight(entry)
		if roll <= 0 then
			return entry
		end
	end
	return entries[#entries] -- only reached through tiny floating point errors
end

-- Total luck from the net, extra sources (potions, VIP) and rebirths, clamped to a safe range.
function LootRoller.GetTotalLuck(netId, extraLuck, rebirths)
	local net = NetData.ById[netId]
	local luck = (net and net.luck or 0) + (extraLuck or 0) + EconomyBalance.RebirthLuck(rebirths or 0)
	return math.clamp(luck, 0, LootRoller.MAX_LUCK)
end

-- { Common = number, Rare = number, ... } after luck is applied
function LootRoller.GetRarityWeights(luck)
	local weights = {}
	for _, rarityName in ipairs(RarityConfig.Order) do
		local rarity = RarityConfig.Rarities[rarityName]
		weights[rarityName] = rarity.weight * (1 + luck) ^ rarity.luckExponent
	end
	return weights
end

-- Percent chance per rarity, in display order. Safe to send to clients for an odds UI.
function LootRoller.GetOdds(luck)
	local weights = LootRoller.GetRarityWeights(luck)
	local total = 0
	for _, weight in pairs(weights) do
		total += weight
	end
	local odds = {}
	for _, rarityName in ipairs(RarityConfig.Order) do
		table.insert(odds, { rarity = rarityName, percent = weights[rarityName] / total * 100 })
	end
	return odds
end

-- Returns a rarity name like "Epic".
function LootRoller.RollRarity(luck, random)
	local weights = LootRoller.GetRarityWeights(luck)
	return pickWeighted(RarityConfig.Order, function(rarityName)
		return weights[rarityName]
	end, random or serverRandom)
end

--[[
	Roll one catch. All options come from SERVER data:
		LootRoller.RollFish({
			netId = profile.equippedNet,   -- e.g. "net_pukot"
			extraLuck = 1.0,               -- luck potion, VIP, events...
			rebirths = profile.rebirths,
		})
	Returns { fishId, rarity, weightKg, cashPerSecond, sellValue, luckUsed }
]]
function LootRoller.RollFish(options)
	options = options or {}
	local random = options.random or serverRandom
	local luck = LootRoller.GetTotalLuck(options.netId, options.extraLuck, options.rebirths)

	local rarity = LootRoller.RollRarity(luck, random)
	local fish = pickWeighted(fishByRarity[rarity], function(candidate)
		return candidate.catchWeight
	end, random)

	local weightKg = fish.weightMin + (fish.weightMax - fish.weightMin) * random:NextNumber()
	weightKg = math.floor(weightKg * 1000 + 0.5) / 1000 -- keep 3 decimals

	return {
		fishId = fish.id,
		rarity = rarity,
		weightKg = weightKg,
		cashPerSecond = EconomyBalance.FishIncome(fish.id, weightKg),
		sellValue = EconomyBalance.SellValue(fish.id, weightKg),
		luckUsed = luck,
	}
end

-- Seconds a player must wait between casts with this net.
function LootRoller.GetCastCooldown(netId)
	return EconomyBalance.CastSeconds(netId)
end

-- Server-side cooldown check. `now` should come from os.clock() or workspace:GetServerTimeNow().
function LootRoller.CanCast(lastCastTime, now, netId)
	if lastCastTime == nil then
		return true
	end
	-- 5% tolerance so normal network jitter never rejects an honest player
	return (now - lastCastTime) >= LootRoller.GetCastCooldown(netId) * 0.95
end

--[[
	EXAMPLE (server Script):

	local LootRoller = require(game.ServerStorage.Items.ServerModules.LootRoller)
	local castRemote = game.ReplicatedStorage.Remotes.Cast   -- RemoteEvent you create
	local lastCast = {}

	castRemote.OnServerEvent:Connect(function(player)        -- NO arguments are trusted
		local profile = getProfile(player)                     -- your data system
		local now = os.clock()
		if not LootRoller.CanCast(lastCast[player], now, profile.equippedNet) then
			return                                             -- too fast: ignore
		end
		lastCast[player] = now
		local catch = LootRoller.RollFish({
			netId = profile.equippedNet,
			extraLuck = getServerLuckBonus(player),            -- potions/VIP tracked on the server
			rebirths = profile.rebirths,
		})
		addFishToProfile(profile, catch)                       -- save first...
		castRemote:FireClient(player, catch.fishId, catch.weightKg)  -- ...then tell the client
	end)
]]

return LootRoller
