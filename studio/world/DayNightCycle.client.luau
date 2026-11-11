--[[
	DayNightCycle  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > DayNightCycle

	A slow day/night cycle that every player sees in sync, computed from the server clock
	(workspace:GetServerTimeNow()), so no replication and no fighting with the client-side event skies:
	  * PAUSES while a world event is active (ReplicatedStorage.Items.EventState.EventId ~= "")
	    so EventAtmosphere owns ClockTime; when the event ends it tweens back and this script resumes
	  * dwells in golden hour: 60% of the cycle sits between 16.5 and 18.5 o'clock, nights are short
	  * also fades Brightness, Bloom and Atmosphere haze a little between day and night

	CYCLE_MINUTES real minutes per full day. Set it to 0 to freeze at GOLDEN_HOUR.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CYCLE_MINUTES = 24
local GOLDEN_HOUR = 17.3

-- piecewise curve: cycle fraction -> clock time (hours). Flat stretch around golden hour.
local CURVE = {
	{ 0.00, 6.0 }, -- dawn
	{ 0.15, 11.0 }, -- morning
	{ 0.30, 15.5 },
	{ 0.40, 16.8 }, -- golden hour starts
	{ 0.75, 18.3 }, -- golden hour ends (35% of the cycle)
	{ 0.84, 19.6 }, -- dusk
	{ 0.92, 23.5 }, -- short night
	{ 1.00, 30.0 }, -- = 6.0 next day
}

local function clockFor(fraction)
	for i = 1, #CURVE - 1 do
		local a, b = CURVE[i], CURVE[i + 1]
		if fraction >= a[1] and fraction <= b[1] then
			local t = (fraction - a[1]) / (b[1] - a[1])
			return (a[2] + (b[2] - a[2]) * t) % 24
		end
	end
	return GOLDEN_HOUR
end

local eventState = ReplicatedStorage:WaitForChild("Items", 10) and ReplicatedStorage.Items:FindFirstChild("EventState")
local function eventActive()
	if eventState == nil then
		eventState = ReplicatedStorage:FindFirstChild("Items") and ReplicatedStorage.Items:FindFirstChild("EventState")
	end
	local id = eventState and eventState:GetAttribute("EventId")
	return id ~= nil and id ~= ""
end

local bloom = Lighting:FindFirstChild("SAF_Bloom")
local atmosphere = Lighting:FindFirstChild("SAF_Atmosphere")
local wasActive = false
local accumulator = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.5 then
		return
	end
	accumulator = 0
	local active = eventActive()
	if active then
		wasActive = true
		return
	end
	if wasActive then
		wasActive = false
		task.wait(4.5) -- let EventAtmosphere finish its 4 s fade back before we move ClockTime again
	end
	local clock = GOLDEN_HOUR
	if CYCLE_MINUTES > 0 then
		local fraction = (workspace:GetServerTimeNow() / (CYCLE_MINUTES * 60)) % 1
		clock = clockFor(fraction)
	end
	Lighting.ClockTime = clock
	-- night factor 0 (day) .. 1 (midnight)
	local night = math.clamp(1 - math.abs(((clock + 12) % 24) - 12) / 6, 0, 1) -- 1 near 0:00, 0 near 6:00/18:00
	Lighting.Brightness = 2.6 - 1.6 * night
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 124, 138):Lerp(Color3.fromRGB(50, 58, 85), night)
	if bloom then
		bloom.Intensity = 0.55 + 0.35 * night
	end
	if atmosphere then
		atmosphere.Haze = 1.6 - 0.8 * night
		atmosphere.Glare = 0.45 * (1 - night)
	end
end)
