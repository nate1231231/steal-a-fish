--[[
	DeviceProfile  (ModuleScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient > DeviceProfile

	Decides if this device should use the LITE visual mode (less rain, no aurora curtains,
	fewer particles and highlights). Lite is on when:
	  * the player picked graphics quality 1-4 in Roblox settings, or
	  * quality is "Automatic" and the device is a touch device without a keyboard (phone/tablet), or
	  * the frame rate stays under 35 FPS for 5 seconds (switches to lite, never back automatically)
	A settings menu can force it: DeviceProfile.SetLite(true/false).
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local DeviceProfile = {}

local lite = false
local changed = Instance.new("BindableEvent")
DeviceProfile.Changed = changed.Event -- fires (isLite)

function DeviceProfile.IsLite()
	return lite
end

function DeviceProfile.SetLite(value)
	if lite ~= value then
		lite = value
		changed:Fire(lite)
	end
end

function DeviceProfile.IsMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function DeviceProfile.Start()
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level and level ~= Enum.SavedQualitySetting.Automatic then
		lite = level.Value <= 4
	else
		lite = DeviceProfile.IsMobile()
	end
	-- FPS watchdog
	local frames, elapsed, slowWindows = 0, 0, 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= 1 then
			local fps = frames / elapsed
			frames, elapsed = 0, 0
			slowWindows = fps < 35 and slowWindows + 1 or 0
			if slowWindows >= 5 then
				DeviceProfile.SetLite(true)
				connection:Disconnect()
			end
		end
	end)
	return lite
end

return DeviceProfile
