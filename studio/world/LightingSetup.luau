--[[
	LightingSetup  (COMMAND BAR script, run ONCE in edit mode)
	Location: paste into View > Command Bar and press Enter.

	Golden-hour tropical look with exact values. Creates (or updates) these children of Lighting:
	  Atmosphere, Sky, Bloom, ColorCorrection, SunRays, DepthOfField  (named SAF_*)
	and sets Terrain water. Re-running is safe: it updates the same objects.

	Works with the mutation events: EventAtmosphere snapshots these values when an event starts and
	tweens back to them when it ends. The DayNightCycle LocalScript only moves ClockTime (and only
	while no event is active).
]]

local Lighting = game:GetService("Lighting")
local Terrain = workspace.Terrain

local function ensure(className, name, props)
	local obj = Lighting:FindFirstChild(name)
	if obj == nil or obj.ClassName ~= className then
		if obj then
			obj:Destroy()
		end
		obj = Instance.new(className)
		obj.Name = name
		obj.Parent = Lighting
	end
	for key, value in pairs(props) do
		obj[key] = value
	end
	return obj
end

-- remove other post effects / skies that would double up (keeps yours if you rename them SAF_*)
for _, child in ipairs(Lighting:GetChildren()) do
	if (child:IsA("PostEffect") or child:IsA("Sky") or child:IsA("Atmosphere")) and not child.Name:match("^SAF_") then
		child:Destroy()
	end
end

-- ===================================================================== Lighting
Lighting.Technology = Enum.Technology.Future
Lighting.ClockTime = 17.3 -- golden hour (DayNightCycle dwells here)
Lighting.GeographicLatitude = 12 -- Philippines
Lighting.Brightness = 2.6
Lighting.ExposureCompensation = 0.15
Lighting.EnvironmentDiffuseScale = 0.55
Lighting.EnvironmentSpecularScale = 0.75
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.35
Lighting.Ambient = Color3.fromRGB(70, 75, 85)
Lighting.OutdoorAmbient = Color3.fromRGB(118, 124, 138)
Lighting.ColorShift_Top = Color3.fromRGB(255, 214, 160)
Lighting.ColorShift_Bottom = Color3.fromRGB(80, 110, 140)
Lighting.FogColor = Color3.fromRGB(205, 220, 235)
Lighting.FogStart = 0
Lighting.FogEnd = 100000 -- Atmosphere handles haze

-- ===================================================================== Atmosphere + Sky
ensure("Atmosphere", "SAF_Atmosphere", {
	Density = 0.34,
	Offset = 0.28,
	Color = Color3.fromRGB(205, 215, 230),
	Decay = Color3.fromRGB(255, 170, 110),
	Glare = 0.45,
	Haze = 1.6,
})
ensure("Sky", "SAF_Sky", {
	SunAngularSize = 14,
	MoonAngularSize = 10,
	StarCount = 2500,
	CelestialBodiesShown = true,
	-- keep the default sky textures (no external assets); the Atmosphere tints them
})

-- ===================================================================== post effects
ensure("BloomEffect", "SAF_Bloom", { Enabled = true, Intensity = 0.55, Size = 32, Threshold = 1.15 })
ensure("ColorCorrectionEffect", "SAF_ColorCorrection", {
	Enabled = true,
	Brightness = 0.02,
	Contrast = 0.12,
	Saturation = 0.18,
	TintColor = Color3.fromRGB(255, 246, 232),
})
ensure("SunRaysEffect", "SAF_SunRays", { Enabled = true, Intensity = 0.14, Spread = 0.9 })
ensure("DepthOfFieldEffect", "SAF_DepthOfField", {
	Enabled = true,
	FarIntensity = 0.12, -- light so phones aren't blurred into mush
	FocusDistance = 55,
	InFocusRadius = 45,
	NearIntensity = 0.25,
})

-- ===================================================================== Terrain water + decoration
Terrain.WaterColor = Color3.fromRGB(12, 120, 140)
Terrain.WaterTransparency = 0.72
Terrain.WaterReflectance = 0.55
Terrain.WaterWaveSize = 0.18
Terrain.WaterWaveSpeed = 12
Terrain.Decoration = false -- grass blades cost a lot on phones

print("[LightingSetup] done: Future lighting, golden hour 17.3, SAF_ effects created.")
