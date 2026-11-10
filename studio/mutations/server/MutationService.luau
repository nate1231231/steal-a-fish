--[[
	MutationService  (ModuleScript, SERVER ONLY)
	Put in: ServerStorage > Items > ServerModules > MutationService

	What your gameplay scripts call. It ties together EventAuthority (which event is active),
	MutationRoller (the rolls), FishSchema (the saved format) and the popup RemoteEvent.

	CATCH (inside your cast handler, after the cooldown check):
		local catch = LootRoller.RollFish({ netId = ..., extraLuck = ..., rebirths = ... })
		local record = MutationService.CreateCaughtFish(player, catch, catch.luckUsed)
		-- save `record` into the player's data (tank/backpack), then spawn a model:
		MutationService.TagFishModel(fishModel, record)

	STEAL (only after YOUR server code confirmed the steal succeeded):
		local newRecord = MutationService.ProcessStolenFish(thief, record, thiefLuck, victim)
		-- remove `record` from the victim's data and add `newRecord` to the thief's data

	Popups: the server fires ReplicatedStorage.Items.Remotes.FishPopup to the player:
		(kind = "Catch" | "Steal" | "Lost", record, gainedMutationIds, otherPlayerName)
	It is server -> client only. Anything a client fires at it is ignored.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")
local FishDisplay = require(Modules:WaitForChild("FishDisplay"))
local EventAuthority = require(script.Parent.EventAuthority)
local MutationRoller = require(script.Parent.MutationRoller)
local FishSchema = require(script.Parent.FishSchema)

local MutationService = {}

MutationService.FISH_TAG = "SAF_Fish" -- CollectionService tag the client FishVisuals listens for

local popupRemote = nil

function MutationService.Init()
	if popupRemote then
		return
	end
	local items = ReplicatedStorage:WaitForChild("Items")
	local remotes = items:FindFirstChild("Remotes")
	if remotes == nil then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = items
	end
	popupRemote = remotes:FindFirstChild("FishPopup")
	if popupRemote == nil then
		popupRemote = Instance.new("RemoteEvent")
		popupRemote.Name = "FishPopup"
		popupRemote.Parent = remotes
	end
	popupRemote.OnServerEvent:Connect(function(player)
		-- Clients have no reason to fire this. Never trust or act on it.
		warn(("[MutationService] ignored FishPopup fired by client %s"):format(player.Name))
	end)
end

local function sendPopup(player, kind, record, gained, otherPlayer)
	if popupRemote == nil or player == nil then
		return
	end
	popupRemote:FireClient(player, kind, FishSchema.Copy(record), gained or {}, otherPlayer and otherPlayer.DisplayName or nil)
end

-- Returns record, gainedMutationIds. `luck` is the server-computed total luck for this cast.
function MutationService.CreateCaughtFish(player, catch, luck)
	local record, gained = MutationRoller.CreateCatch(catch, {
		eventId = EventAuthority.GetActiveEventId(),
		luck = luck or 0,
		uid = HttpService:GenerateGUID(false),
		now = math.floor(EventAuthority.Now()),
		ownerUserId = player and player.UserId or 0,
	})
	sendPopup(player, "Catch", record, gained)
	return record, gained
end

-- Returns newRecord, gainedMutationIds. Call ONCE per successful steal.
function MutationService.ProcessStolenFish(thief, record, luck, victim)
	local newRecord, gained = MutationRoller.ApplySteal(record, {
		eventId = EventAuthority.GetActiveEventId(),
		luck = luck or 0,
	})
	sendPopup(thief, "Steal", newRecord, gained, victim)
	if victim then
		sendPopup(victim, "Lost", record, {}, thief)
	end
	return newRecord, gained
end

-- Puts the display data on a fish Model/MeshPart so every client can draw stars and tints.
-- Attributes replicate to clients but client edits never reach the server (display only).
function MutationService.TagFishModel(instance, record)
	instance:SetAttribute("FishUid", record.uid)
	instance:SetAttribute("FishId", record.id)
	instance:SetAttribute("Stars", record.st)
	instance:SetAttribute("Mutations", table.concat(record.mu or {}, ","))
	instance:SetAttribute("SizeFraction", record.sz)
	instance:SetAttribute("DisplayName", FishDisplay.FormatName(record.id, record.mu))
	CollectionService:AddTag(instance, MutationService.FISH_TAG)
end

-- For Roblox Tools in the backpack: tool.Name = MutationService.GetToolName(record)
function MutationService.GetToolName(record)
	return FishDisplay.ToolName(record)
end

return MutationService
