--[[
	EventAtmosphere  (ModuleScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient > EventAtmosphere

	Client-side sky and lighting for the active event, read from MutationData `sky` presets:
	time of day, brightness, fog, color correction, atmosphere, plus extras:
	  rain       camera-following rain (Thunderstorm, Typhoon)
	  lightning  random screen flashes (Thunderstorm, Typhoon, Bakunawa Eclipse)
	  moonSize   a huge moon for Blood Moon; 0 hides the moon for Bakunawa Eclipse (it got eaten)
	  aurora     glowing green/violet sky curtains (Beams)
	  bloom / sunRays / hueCycle for Golden Tide and Rainbow Bloom
	Everything is restored when the event ends. Lite devices get 30% rain, one aurora curtain,
	fewer lightning flashes and no bloom/sun rays.
	This only changes what THIS player sees; it has no effect on the server or on mutation rolls.
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DeviceProfile = require(script.Parent.DeviceProfile)

local EventAtmosphere = {}
EventAtmosphere.__index = EventAtmosphere

local FADE = TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local PREFIX = "SAF_Event"

function EventAtmosphere.new()
	local self = setmetatable({}, EventAtmosphere)
	self.created = {}
	self.connections = {}
	self.original = nil
	self.active = nil
	return self
end

function EventAtmosphere:Snapshot()
	local sky = Lighting:FindFirstChildOfClass("Sky")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	self.original = {
		lighting = { ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, FogColor = Lighting.FogColor,
			FogEnd = Lighting.FogEnd, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient },
		atmosphere = atmosphere and { Density = atmosphere.Density, Color = atmosphere.Color, Haze = atmosphere.Haze } or nil,
		sky = sky and { MoonAngularSize = sky.MoonAngularSize, StarCount = sky.StarCount } or nil,
		wind = workspace.GlobalWind,
	}
end

local function make(className, parent, props)
	local object = Instance.new(className)
	object.Name = PREFIX .. className
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

function EventAtmosphere:Track(object)
	table.insert(self.created, object)
	return object
end

function EventAtmosphere:Connect(signal, fn)
	table.insert(self.connections, signal:Connect(fn))
end

function EventAtmosphere:StartRain(amount, lite)
	local part = self:Track(make("Part", workspace.CurrentCamera, { Anchored = true, CanCollide = false, CanQuery = false,
		CanTouch = false, Transparency = 1, Size = Vector3.new(140, 1, 140), CastShadow = false }))
	local rain = make("ParticleEmitter", part, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(190, 215, 240)),
		Transparency = NumberSequence.new(0.35),
		Size = NumberSequence.new(0.12),
		Lifetime = NumberRange.new(1.1, 1.4),
		Rate = (lite and 90 or 320) * amount,
		Speed = NumberRange.new(70, 85),
		SpreadAngle = Vector2.new(4, 4),
		EmissionDirection = Enum.NormalId.Bottom,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		LightInfluence = 1,
		Acceleration = workspace.GlobalWind * 0.5,
	})
	self:Connect(RunService.RenderStepped, function()
		local camera = workspace.CurrentCamera
		if camera then
			part.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
		end
	end)
	return rain
end

function EventAtmosphere:StartLightning(color, colorCorrection, lite)
	local running = true
	table.insert(self.connections, { Disconnect = function()
		running = false
	end })
	task.spawn(function()
		while running do
			task.wait(lite and math.random(12, 20) or math.random(5, 12))
			if not running then
				break
			end
			local flashes = (not lite and math.random() < 0.5) and 2 or 1
			for _ = 1, flashes do
				colorCorrection.TintColor = color
				colorCorrection.Brightness = 0.45
				TweenService:Create(colorCorrection, TweenInfo.new(0.35), { Brightness = 0 }):Play()
				task.wait(0.15)
			end
		end
	end)
end

function EventAtmosphere:StartAurora(lite)
	local anchor = self:Track(make("Part", workspace.CurrentCamera, { Anchored = true, CanCollide = false, CanQuery = false,
		CanTouch = false, Transparency = 1, Size = Vector3.new(1, 1, 1) }))
	local beams = {}
	for i = 1, (lite and 1 or 3) do
		local a0 = make("Attachment", anchor, { Position = Vector3.new(-420, 200 + i * 25, -380 + i * 70) })
		local a1 = make("Attachment", anchor, { Position = Vector3.new(420, 230 + i * 20, -420 + i * 60) })
		local beam = make("Beam", anchor, {
			Attachment0 = a0,
			Attachment1 = a1,
			Width0 = 150,
			Width1 = 110,
			Segments = 30,
			FaceCamera = true,
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 255, 160)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 200, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 90, 255)),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(0.7, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
		table.insert(beams, beam)
	end
	self:Connect(RunService.RenderStepped, function()
		local camera = workspace.CurrentCamera
		if camera then
			anchor.CFrame = CFrame.new(camera.CFrame.Position)
		end
		local t = os.clock()
		for i, beam in ipairs(beams) do
			beam.CurveSize0 = 90 * math.sin(t * 0.35 + i)
			beam.CurveSize1 = -90 * math.cos(t * 0.3 + i * 2)
		end
	end)
end

function EventAtmosphere:Apply(mutation)
	if self.active then
		self:Clear(true)
	end
	if not self.original then
		self:Snapshot()
	end
	local sky = mutation.sky
	local lite = DeviceProfile.IsLite()
	self.active = mutation.id

	TweenService:Create(Lighting, FADE, {
		ClockTime = sky.clockTime or Lighting.ClockTime,
		Brightness = sky.brightness or Lighting.Brightness,
		FogColor = sky.fogColor or Lighting.FogColor,
		FogEnd = sky.fogEnd or Lighting.FogEnd,
	}):Play()

	local cc = self:Track(make("ColorCorrectionEffect", Lighting, { TintColor = Color3.new(1, 1, 1), Saturation = 0 }))
	TweenService:Create(cc, FADE, { TintColor = sky.tint or Color3.new(1, 1, 1), Saturation = sky.saturation or 0 }):Play()

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = self:Track(make("Atmosphere", Lighting, { Density = 0, Haze = 0 }))
	end
	TweenService:Create(atmosphere, FADE, { Density = sky.atmosphereDensity or atmosphere.Density,
		Color = sky.atmosphereColor or atmosphere.Color }):Play()

	if sky.moonSize or sky.stars then
		local skyObject = Lighting:FindFirstChildOfClass("Sky") or self:Track(make("Sky", Lighting))
		if sky.moonSize then
			skyObject.MoonAngularSize = sky.moonSize
		end
		if sky.stars then
			skyObject.StarCount = sky.stars
		end
	end
	if sky.wind then
		workspace.GlobalWind = Vector3.new(sky.wind, 0, sky.wind * 0.3)
	end
	if sky.rain then
		self:StartRain(sky.rain, lite)
	end
	if sky.lightning then
		self:StartLightning(sky.lightning, cc, lite)
	end
	if sky.aurora then
		self:StartAurora(lite)
	end
	if not lite then
		if sky.bloom then
			local bloom = self:Track(make("BloomEffect", Lighting, { Intensity = 0, Size = 30, Threshold = 0.9 }))
			TweenService:Create(bloom, FADE, { Intensity = sky.bloom }):Play()
		end
		if sky.sunRays then
			local rays = self:Track(make("SunRaysEffect", Lighting, { Intensity = 0, Spread = 0.6 }))
			TweenService:Create(rays, FADE, { Intensity = sky.sunRays }):Play()
		end
		if sky.hueCycle then
			self:Connect(RunService.Heartbeat, function()
				cc.TintColor = Color3.fromHSV((os.clock() * 0.05) % 1, 0.12, 1)
			end)
		end
	end
end

-- Fades everything back to how the place looked before the event
function EventAtmosphere:Clear(instant)
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	local created = self.created
	self.created = {}
	self.active = nil
	local original = self.original
	if original then
		local info = instant and TweenInfo.new(0) or FADE
		TweenService:Create(Lighting, info, original.lighting):Play()
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere and original.atmosphere then
			TweenService:Create(atmosphere, info, original.atmosphere):Play()
		end
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky and original.sky then
			sky.MoonAngularSize = original.sky.MoonAngularSize
			sky.StarCount = original.sky.StarCount
		end
		workspace.GlobalWind = original.wind
	end
	for _, object in ipairs(created) do
		if object:IsA("PostEffect") or object:IsA("Atmosphere") then
			if not instant then
				local goal = object:IsA("ColorCorrectionEffect") and { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0 }
					or object:IsA("Atmosphere") and { Density = 0 } or { Intensity = 0 }
				TweenService:Create(object, FADE, goal):Play()
			end
			task.delay(instant and 0 or 4.1, function()
				object:Destroy()
			end)
		else
			object:Destroy()
		end
	end
end

return EventAtmosphere
