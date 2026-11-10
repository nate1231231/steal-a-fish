--[[
	FishVisuals  (ModuleScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient > FishVisuals

	Makes mutated fish LOOK mutated and shows stars above every fish (in tanks, on the ground,
	held). The server marks fish with MutationService.TagFishModel (tag "SAF_Fish" + attributes
	FishId, Stars, Mutations, DisplayName). Everything here is client-only decoration.

	Tint styles (the rarest mutation decides the main look; other mutations add small sparkles):
	  gold      steady gold overlay + gold glitter + warm light
	  rainbow   overlay cycles through every hue (animated) + rainbow sparkles
	  electric  blue overlay with a flickering white outline + fast blue sparks + flickering light
	  crimson   deep red overlay, slow heartbeat pulse + dark red smoke
	  aurora    overlay drifts green <-> violet (animated) + green/violet motes rising
	  storm     teal overlay + water droplets falling
	  shadow    near-black overlay with a glowing outline (gold corona / moon-eater cyan) + dark smoke

	Phone budget: at most 20 Highlights (8 in lite mode; Roblox renders 31 max). Rarest fish get them
	first; the rest still get particles. Animations run in ONE loop at 20 Hz.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")
local MutationData = require(Modules:WaitForChild("MutationData"))
local StarConfig = require(Modules:WaitForChild("StarConfig"))
local FishDisplay = require(Modules:WaitForChild("FishDisplay"))
local DeviceProfile = require(script.Parent.DeviceProfile)
local UIKit = require(script.Parent.UIKit)

local FishVisuals = {}

FishVisuals.TAG = "SAF_Fish"
FishVisuals.MAX_HIGHLIGHTS = 20
FishVisuals.MAX_HIGHLIGHTS_LITE = 8
FishVisuals.BILLBOARD_DISTANCE = 45

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local tracked = {} -- [instance] = { parts created, style, highlight, emitters, light, phase, primary }
local highlightCount = 0

local function rainbowSequence()
	local keys = {}
	for k = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 1, 1)))
	end
	return ColorSequence.new(keys)
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = "SAF_Mutation"
	e.LightInfluence = 0
	e.LightEmission = 1
	e.Rate = 5
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	e.Texture = SPARKLE
	for key, value in pairs(props) do
		e[key] = value
	end
	e.Parent = parent
	return e
end

-- Builds the effects for one style. Returns { emitters = {}, light = PointLight? }
local function buildStyle(part, mutation, lite, rateScale)
	local tint = mutation.tint
	local style = tint.style
	local out = { emitters = {} }
	local function add(props)
		props.Rate = (props.Rate or 5) * rateScale * (lite and 0.5 or 1)
		table.insert(out.emitters, emitter(part, props))
	end
	if style == "gold" then
		add({ Color = ColorSequence.new(tint.fill, tint.outline), Rate = 7, Size = NumberSequence.new(0.3, 0) })
	elseif style == "rainbow" then
		add({ Color = rainbowSequence(), Rate = 9, Size = NumberSequence.new(0.32, 0) })
	elseif style == "electric" then
		add({ Color = ColorSequence.new(tint.outline, tint.fill), Rate = 14, Lifetime = NumberRange.new(0.12, 0.25),
			Speed = NumberRange.new(4, 7), Size = NumberSequence.new(0.18, 0) })
	elseif style == "crimson" then
		add({ Texture = SMOKE, Color = ColorSequence.new(tint.fill, Color3.fromRGB(40, 0, 5)), Rate = 4, LightEmission = 0,
			Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.3, 0.8), Acceleration = Vector3.new(0, 1.5, 0),
			Transparency = NumberSequence.new(0.55, 1), Size = NumberSequence.new(0.4, 1.1) })
	elseif style == "aurora" then
		add({ Color = ColorSequence.new(Color3.fromRGB(60, 255, 160), Color3.fromRGB(170, 90, 255)), Rate = 7,
			Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.3, 0.6), Acceleration = Vector3.new(0, 1.2, 0) })
	elseif style == "storm" then
		add({ Color = ColorSequence.new(Color3.fromRGB(190, 240, 255)), Rate = 9, Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(0, 0.5), Acceleration = Vector3.new(0, -9, 0), Size = NumberSequence.new(0.14, 0.05) })
	elseif style == "shadow" then
		add({ Texture = SMOKE, Color = ColorSequence.new(tint.fill, Color3.new(0, 0, 0)), Rate = 5, LightEmission = 0,
			Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(0.2, 0.6), Transparency = NumberSequence.new(0.4, 1),
			Size = NumberSequence.new(0.5, 1.3) })
		add({ Color = ColorSequence.new(tint.outline), Rate = 3, Size = NumberSequence.new(0.2, 0) })
	end
	if not lite and (style == "gold" or style == "electric" or style == "shadow") then
		local light = Instance.new("PointLight")
		light.Name = "SAF_Mutation"
		light.Color = style == "shadow" and tint.outline or tint.fill
		light.Range = 7
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = part
		out.light = light
	end
	return out
end

local function getPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function parseMutations(text)
	local list = {}
	for id in string.gmatch(text or "", "[^,]+") do
		table.insert(list, id)
	end
	return MutationData.Sanitize(list)
end

local function clear(instance)
	local entry = tracked[instance]
	if not entry then
		return
	end
	for _, object in ipairs(entry.created) do
		object:Destroy()
	end
	if entry.highlight then
		highlightCount -= 1
	end
	tracked[instance] = nil
end

local function makeBillboard(part, stars, mutations, displayName)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SAF_FishTag"
	billboard.Size = UDim2.new(4, 0, 1.2, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 0.9, 0)
	billboard.MaxDistance = FishVisuals.BILLBOARD_DISTANCE
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.ResetOnSpawn = false
	local starLabel = UIKit.Label({ Text = FishDisplay.StarText(stars), Size = UDim2.fromScale(1, 0.5), TextScaled = true,
		Font = UIKit.FONT_TITLE, TextColor3 = StarConfig.Get(stars).color, TextTruncate = Enum.TextTruncate.None })
	starLabel.Parent = billboard
	if #mutations > 0 then
		local primary = MutationData.Get(mutations[1])
		local nameLabel = UIKit.Label({ Text = displayName, Size = UDim2.fromScale(1, 0.45), Position = UDim2.fromScale(0, 0.52),
			TextScaled = true, TextColor3 = primary.accent })
		nameLabel.Parent = billboard
	end
	billboard.Parent = part
	return billboard
end

local function apply(instance)
	clear(instance)
	local part = getPart(instance)
	if not part then
		return
	end
	local lite = DeviceProfile.IsLite()
	local stars = StarConfig.Clamp(instance:GetAttribute("Stars") or 1)
	local mutations = parseMutations(instance:GetAttribute("Mutations"))
	local displayName = instance:GetAttribute("DisplayName") or FishDisplay.FormatName(instance:GetAttribute("FishId"), mutations)
	local entry = { created = {}, phase = math.random() * 10 }
	tracked[instance] = entry
	table.insert(entry.created, makeBillboard(part, stars, mutations, displayName))
	if #mutations == 0 then
		return
	end
	local primary = MutationData.Get(mutations[1])
	entry.primary = primary
	local limit = lite and FishVisuals.MAX_HIGHLIGHTS_LITE or FishVisuals.MAX_HIGHLIGHTS
	if highlightCount < limit then
		local highlight = Instance.new("Highlight")
		highlight.Name = "SAF_Mutation"
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = primary.tint.fill
		highlight.OutlineColor = primary.tint.outline
		highlight.FillTransparency = primary.tint.style == "shadow" and 0.2 or 0.5
		highlight.OutlineTransparency = 0.1
		highlight.Parent = instance
		entry.highlight = highlight
		highlightCount += 1
		table.insert(entry.created, highlight)
	end
	local main = buildStyle(part, primary, lite, 1)
	entry.emitters, entry.light = main.emitters, main.light
	for _, e in ipairs(main.emitters) do
		table.insert(entry.created, e)
	end
	if main.light then
		table.insert(entry.created, main.light)
	end
	if not lite then -- up to 2 secondary mutations add a small sparkle in their color
		for index = 2, math.min(#mutations, 3) do
			local extra = MutationData.Get(mutations[index])
			table.insert(entry.created, emitter(part, { Color = ColorSequence.new(extra.color), Rate = 2,
				Size = NumberSequence.new(0.18, 0) }))
		end
	end
end

local function watch(instance)
	apply(instance)
	local connections = {}
	for _, attribute in ipairs({ "Stars", "Mutations", "DisplayName" }) do
		table.insert(connections, instance:GetAttributeChangedSignal(attribute):Connect(function()
			apply(instance)
		end))
	end
	table.insert(connections, instance.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clear(instance)
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
	end))
end

-- One animation loop for every mutated fish (20 Hz)
local function animate(t)
	for _, entry in pairs(tracked) do
		local primary = entry.primary
		if primary then
			local style = primary.tint.style
			local h, phase = entry.highlight, entry.phase
			if style == "rainbow" then
				local color = Color3.fromHSV((t * 0.25 + phase) % 1, 1, 1)
				if h then
					h.FillColor = color
					h.OutlineColor = Color3.fromHSV((t * 0.25 + phase + 0.5) % 1, 0.6, 1)
				end
			elseif style == "aurora" then
				local alpha = (math.sin(t * 1.2 + phase) + 1) / 2
				if h then
					h.FillColor = Color3.fromRGB(50, 230, 150):Lerp(Color3.fromRGB(160, 80, 255), alpha)
					h.OutlineColor = Color3.fromRGB(170, 100, 255):Lerp(Color3.fromRGB(120, 255, 200), alpha)
				end
			elseif style == "electric" then
				if h then
					h.OutlineTransparency = math.random() < 0.25 and 0.7 or 0
				end
				if entry.light then
					entry.light.Brightness = math.random() < 0.2 and 3 or 0.8
				end
			elseif style == "gold" then
				if h then
					h.FillTransparency = 0.5 + 0.12 * math.sin(t * 3 + phase)
				end
			elseif style == "crimson" then
				if h then
					local beat = math.max(0, math.sin(t * 4 + phase)) ^ 6
					h.FillTransparency = 0.5 - 0.25 * beat
				end
			elseif style == "storm" then
				if h then
					h.FillColor = primary.tint.fill:Lerp(Color3.fromRGB(150, 165, 175), (math.sin(t * 0.8 + phase) + 1) / 2)
				end
			elseif style == "shadow" then
				if h then
					h.OutlineTransparency = 0.25 * (math.sin(t * 2 + phase) + 1)
				end
			end
		end
	end
end

function FishVisuals.Start()
	CollectionService:GetInstanceAddedSignal(FishVisuals.TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(FishVisuals.TAG):Connect(clear)
	for _, instance in ipairs(CollectionService:GetTagged(FishVisuals.TAG)) do
		task.spawn(watch, instance)
	end
	DeviceProfile.Changed:Connect(function()
		for instance in pairs(tracked) do
			apply(instance)
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.05 then
			accumulator = 0
			animate(os.clock())
		end
	end)
end

return FishVisuals
