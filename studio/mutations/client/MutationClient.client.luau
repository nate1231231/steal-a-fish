--[[
	MutationClient  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient
	Child ModuleScripts (same folder in studio/mutations/client/): UIKit, DeviceProfile, EventPanel,
	EventBanner, CatchPopup, FishVisuals, EventAtmosphere

	Wires the mutation UI together. It only READS server state:
	  * ReplicatedStorage.Items.EventState attributes (published by the server's EventAuthority)
	  * ReplicatedStorage.Items.Remotes.FishPopup (server -> client catch/steal results)
	Nothing here can change stars, mutations or events; editing these values on a hacked client
	only changes what that client sees.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = ReplicatedStorage:WaitForChild("Items")
local Modules = Items:WaitForChild("Modules")
local MutationData = require(Modules:WaitForChild("MutationData"))
local EventSchedule = require(Modules:WaitForChild("EventSchedule"))

local UIKit = require(script:WaitForChild("UIKit"))
local DeviceProfile = require(script:WaitForChild("DeviceProfile"))
local EventPanel = require(script:WaitForChild("EventPanel"))
local EventBanner = require(script:WaitForChild("EventBanner"))
local CatchPopup = require(script:WaitForChild("CatchPopup"))
local FishVisuals = require(script:WaitForChild("FishVisuals"))
local EventAtmosphere = require(script:WaitForChild("EventAtmosphere"))

local eventState = Items:WaitForChild("EventState")
local popupRemote = Items:WaitForChild("Remotes"):WaitForChild("FishPopup")

DeviceProfile.Start()
local gui = UIKit.CreateScreenGui("MutationHUD", 20)
local panel = EventPanel.new(gui)
local banner = EventBanner.new(gui)
local popups = CatchPopup.new(gui)
local atmosphere = EventAtmosphere.new()
FishVisuals.Start()

local function now()
	return workspace:GetServerTimeNow() + (eventState:GetAttribute("TimeOffset") or 0)
end

local function minutesText(seconds)
	local minutes = math.floor(seconds / 60 + 0.5)
	return minutes == 1 and "1 minute" or (tostring(minutes) .. " minutes")
end

-- ===================================================================== event start / end
local currentEventId = nil
local function onEventChanged(isJoin)
	local id = eventState:GetAttribute("EventId")
	if id == "" then
		id = nil
	end
	if id == currentEventId then
		return
	end
	local previous = currentEventId and MutationData.Get(currentEventId)
	currentEventId = id
	if id then
		local mutation = MutationData.Get(id)
		if mutation then
			banner:Show({
				mutation = mutation,
				kind = "Start",
				title = mutation.eventName .. (isJoin and " is active!" or " is here!"),
				subtitle = "Mutated fish are worth " .. UIKit.FormatMultiplier(mutation.multiplier),
				hold = 4,
			})
			atmosphere:Apply(mutation)
		end
	else
		if previous then
			banner:Show({ mutation = previous, kind = "End", title = previous.eventName .. " has passed",
				subtitle = "Calm seas again", hold = 2.5 })
		end
		atmosphere:Clear()
	end
end
eventState:GetAttributeChangedSignal("EventId"):Connect(function()
	onEventChanged(false)
end)
onEventChanged(true)

-- ===================================================================== popups from the server
popupRemote.OnClientEvent:Connect(function(kind, record, gained, otherName)
	popups:Show(kind, record, gained, otherName)
end)

-- ===================================================================== countdown + heads-up banners (4 Hz)
local previousSecondsUntil = nil
local countdownSeconds = EventSchedule.Config.countdownSeconds

while true do
	local t = now()
	local view
	local active = currentEventId and MutationData.Get(currentEventId)
	if active then
		local startsAt = eventState:GetAttribute("EventStartsAt") or t
		local endsAt = eventState:GetAttribute("EventEndsAt") or t
		view = { mode = "Active", mutation = active, seconds = endsAt - t,
			progress = (endsAt - t) / math.max(endsAt - startsAt, 1) }
		previousSecondsUntil = nil
	else
		local nextMutation = MutationData.Get(eventState:GetAttribute("NextEventId"))
		local secondsUntil = (eventState:GetAttribute("NextEventStartsAt") or 0) - t
		if nextMutation and secondsUntil <= countdownSeconds then
			view = { mode = "Countdown", mutation = nextMutation, seconds = secondsUntil,
				progress = 1 - secondsUntil / countdownSeconds }
		else
			view = { mode = "Calm", mutation = nextMutation }
		end
		-- heads-up banners fire only when the countdown CROSSES 15:00 and 1:00 (not on join)
		if nextMutation and previousSecondsUntil then
			for _, threshold in ipairs(EventSchedule.Config.headsUpSeconds) do
				if previousSecondsUntil > threshold and secondsUntil <= threshold then
					banner:Show({
						mutation = nextMutation,
						kind = "HeadsUp",
						title = nextMutation.eventName .. " in " .. minutesText(threshold) .. "!",
						subtitle = threshold <= 60 and "Get your nets ready!"
							or ("Mutated fish will be worth " .. UIKit.FormatMultiplier(nextMutation.multiplier)),
						hold = 2.5,
					})
				end
			end
		end
		previousSecondsUntil = nextMutation and secondsUntil or nil
	end
	panel:Update(view)
	task.wait(0.25)
end
