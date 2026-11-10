--[[
	EventAuthority  (ModuleScript, SERVER ONLY)
	Put in: ServerStorage > Items > ServerModules > EventAuthority

	The server's single answer to "which event is active right now?".
	  * Normal play: EventSchedule.GetState(workspace:GetServerTimeNow())  (same on every server)
	  * Publishes the state as attributes on ReplicatedStorage.Items.EventState so clients can show it:
	      EventId, EventStartsAt, EventEndsAt, NextEventId, NextEventStartsAt, TimeOffset
	    Clients can READ these but cannot change them: client-side attribute edits never replicate.

	STUDIO-ONLY debug switches (ignored in live servers, RunService:IsStudio() must be true).
	Set them on ServerStorage.Items from the Command Bar while playing (Server view):
	  game.ServerStorage.Items:SetAttribute("DebugForceEvent", "golden_tide")  -- start an event now
	  game.ServerStorage.Items:SetAttribute("DebugTimeOffset", 1500)           -- jump the clock forward (seconds)
	The forced event clears itself when it ends.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")
local EventSchedule = require(Modules:WaitForChild("EventSchedule"))
local MutationData = require(Modules:WaitForChild("MutationData"))

local EventAuthority = {}

local IS_STUDIO = RunService:IsStudio()
local debugHolder = ServerStorage:WaitForChild("Items")
local forced = nil -- { eventId, startsAt, endsAt } while a Studio debug event runs

function EventAuthority.GetTimeOffset()
	if not IS_STUDIO then
		return 0
	end
	return tonumber(debugHolder:GetAttribute("DebugTimeOffset")) or 0
end

-- Authoritative server time (plus the Studio debug offset)
function EventAuthority.Now()
	return workspace:GetServerTimeNow() + EventAuthority.GetTimeOffset()
end

function EventAuthority.GetState()
	local now = EventAuthority.Now()
	local state = EventSchedule.GetState(now)
	if not IS_STUDIO then
		return state
	end
	local forcedId = debugHolder:GetAttribute("DebugForceEvent")
	if not MutationData.IsValid(forcedId) then
		forced = nil
		return state
	end
	if forced == nil or forced.eventId ~= forcedId then
		forced = { eventId = forcedId, startsAt = now, endsAt = now + MutationData.ById[forcedId].durationSeconds }
		warn(("[EventAuthority] Studio debug: forcing %s for %ds"):format(forcedId, forced.endsAt - now))
	end
	if now >= forced.endsAt then
		forced = nil
		debugHolder:SetAttribute("DebugForceEvent", nil)
		return state
	end
	state.activeEventId = forced.eventId
	state.activeStartsAt = forced.startsAt
	state.activeEndsAt = forced.endsAt
	state.secondsLeft = forced.endsAt - now
	state.showCountdown = false
	return state
end

-- The id the roller is allowed to use, or nil when no event is active
function EventAuthority.GetActiveEventId()
	return EventAuthority.GetState().activeEventId
end

local published = false

-- Creates ReplicatedStorage.Items.EventState and keeps its attributes current (call once)
function EventAuthority.StartPublishing()
	if published then
		return
	end
	published = true
	local items = ReplicatedStorage:WaitForChild("Items")
	local folder = items:FindFirstChild("EventState")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "EventState"
		folder.Parent = items
	end
	local function set(name, value)
		if folder:GetAttribute(name) ~= value then
			folder:SetAttribute(name, value)
		end
	end
	task.spawn(function()
		while true do
			local state = EventAuthority.GetState()
			set("EventId", state.activeEventId or "")
			set("EventStartsAt", state.activeStartsAt or 0)
			set("EventEndsAt", state.activeEndsAt or 0)
			set("NextEventId", state.nextEventId or "")
			set("NextEventStartsAt", state.nextStartsAt or 0)
			set("TimeOffset", EventAuthority.GetTimeOffset())
			task.wait(0.5)
		end
	end)
end

return EventAuthority
