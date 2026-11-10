--[[
	EventServer  (Script)
	Put in: ServerScriptService > Mutations > EventServer

	Starts the world-event system on every server:
	  1. Publishes the current/next event to ReplicatedStorage.Items.EventState (EventAuthority)
	  2. Creates the server -> client popup RemoteEvent (MutationService.Init)
	Nothing else is needed: the calendar is computed from server time, so all servers agree.

	Your fishing / stealing scripts then call MutationService (see its header) to give fish
	stars and mutations.
]]

local ServerStorage = game:GetService("ServerStorage")

local ServerModules = ServerStorage:WaitForChild("Items"):WaitForChild("ServerModules")
local EventAuthority = require(ServerModules:WaitForChild("EventAuthority"))
local MutationService = require(ServerModules:WaitForChild("MutationService"))

MutationService.Init()
EventAuthority.StartPublishing()

local state = EventAuthority.GetState()
print(("[EventServer] running. Active: %s | next: %s in %ds"):format(
	state.activeEventId or "none", tostring(state.nextEventId), math.floor(state.secondsUntilNext)))
