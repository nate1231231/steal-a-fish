--[[
	AmbientSound  (Script)
	Location: ServerScriptService > World > AmbientSound

	SoundService setup + three looping ambient layers:
	  * waves    3D, placed at points along the shoreline (so they get louder near the water)
	  * seagulls 3D, a few spots over the beach, random gaps between cries
	  * wind     2D, everywhere, gusts with volume wobble
	plus a SoundGroup "Ambient" you can mute from a settings menu (SoundService.Ambient.Volume).

	SOUND IDS: Roblox has no built-in wave/seagull/wind files, so paste free Creator Store audio ids
	below (search "ocean waves loop", "seagulls", "wind loop" and use ones marked free to use).
	With an id of 0 the script falls back to Roblox's built-in swim/whoosh sounds (slow, quiet
	loops) so you still hear something; replace them when you can.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SOUND_IDS = {
	waves = 0, -- e.g. "rbxassetid://123456789"  (looping ocean waves)
	seagulls = 0, -- seagull cries (short clip, played with gaps)
	wind = 0, -- looping wind
}
local FALLBACK = {
	waves = { id = "rbxasset://sounds/action_swim.mp3", speed = 0.45, volume = 0.35 },
	seagulls = nil, -- no built-in bird sound; silent until you paste an id
	wind = { id = "rbxasset://sounds/Rocket whoosh 01.wav", speed = 0.25, volume = 0.12 },
}

-- ===================================================================== SoundService
SoundService.AmbientReverb = Enum.ReverbType.Plain
SoundService.DistanceFactor = 3.33
SoundService.DopplerScale = 1
SoundService.RolloffScale = 1
SoundService.RespectFilteringEnabled = true

local group = SoundService:FindFirstChild("Ambient")
if group == nil then
	group = Instance.new("SoundGroup")
	group.Name = "Ambient"
	group.Parent = SoundService
end
group.Volume = 0.9

local function resolve(kind)
	local id = SOUND_IDS[kind]
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. id, 1, 1
	elseif type(id) == "string" and id ~= "" then
		return id, 1, 1
	end
	local fb = FALLBACK[kind]
	if fb == nil then
		warn(("[AmbientSound] no %s sound id; silent until SOUND_IDS.%s is set"):format(kind, kind))
		return nil
	end
	warn(("[AmbientSound] SOUND_IDS.%s is 0, using the built-in fallback (replace it later)"):format(kind))
	return fb.id, fb.speed, fb.volume
end

local function makeSound(kind, parent, volume, looped, rolloffMax)
	local id, speed, volMul = resolve(kind)
	if id == nil then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Ambient_" .. kind
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = volume * volMul
	sound.PlaybackSpeed = speed
	sound.SoundGroup = group
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = rolloffMax or 120
	sound.Parent = parent
	return sound
end

local function anchorPart(name, position)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.CastShadow = false
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	return part
end

-- ===================================================================== placement from the island layout
local layout
local ok, WorldConfig = pcall(function()
	return require(ReplicatedStorage:WaitForChild("World"):WaitForChild("WorldConfig"))
end)
if ok and WorldConfig then
	layout = WorldConfig.Layout()
end
local center = layout and layout.center or Vector3.new(0, 0, 0)
local radius = layout and layout.radius or 220
local seaLevel = layout and layout.seaLevel or -5

local folder = workspace:FindFirstChild("AmbientSounds")
if folder then
	folder:Destroy()
end
folder = Instance.new("Folder")
folder.Name = "AmbientSounds"
folder.Parent = workspace

-- waves: 10 emitters around the shoreline
local waves = {}
for i = 1, 10 do
	local a = (i - 1) / 10 * math.pi * 2
	local pos = Vector3.new(center.X + math.cos(a) * radius * 0.98, seaLevel + 1, center.Z + math.sin(a) * radius * 0.98)
	local part = anchorPart("WaveEmitter" .. i, pos)
	part.Parent = folder
	local s = makeSound("waves", part, 0.6, true, 170)
	if s then
		s.TimePosition = math.random() * 5
		s:Play()
		table.insert(waves, s)
	end
end

-- wind: one 2D looping sound in SoundService with gusts
local wind = makeSound("wind", SoundService, 0.25, true)
if wind then
	wind:Play()
	task.spawn(function()
		while wind.Parent do
			local target = 0.15 + math.random() * 0.25
			local steps = 30
			local start = wind.Volume
			for k = 1, steps do
				wind.Volume = start + (target - start) * k / steps
				task.wait(0.1)
			end
			task.wait(2 + math.random() * 6)
		end
	end)
end

-- seagulls: 4 spots over the beach, random cries
local gullSpots = {}
for i = 1, 4 do
	local a = (i - 0.5) / 4 * math.pi * 2
	local pos = Vector3.new(center.X + math.cos(a) * radius * 0.85, seaLevel + 28, center.Z + math.sin(a) * radius * 0.85)
	local part = anchorPart("GullSpot" .. i, pos)
	part.Parent = folder
	local s = makeSound("seagulls", part, 0.5, false, 220)
	if s then
		table.insert(gullSpots, s)
	end
end
if #gullSpots > 0 then
	task.spawn(function()
		while true do
			task.wait(6 + math.random() * 14)
			local s = gullSpots[math.random(#gullSpots)]
			s.PlaybackSpeed = 0.9 + math.random() * 0.25
			s:Play()
		end
	end)
end

print(("[AmbientSound] %d wave emitters, wind %s, %d gull spots"):format(#waves, wind and "on" or "off", #gullSpots))
