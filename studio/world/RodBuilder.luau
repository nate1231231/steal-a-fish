--[[
	RodBuilder  (COMMAND BAR script, run ONCE in edit mode)
	Location: paste into View > Command Bar and press Enter.

	Builds the "FishingRod" Tool from Parts into StarterPack (so every player gets it) and a copy in
	ServerStorage.Tools for your shop/net system. Parts: cork handle, reel seat, 4-segment bent shaft
	(graphite), 3 line guides, reel (body, spool, crank), rod tip attachment, bobber (red/white ball)
	with its own attachment, and a Beam for the line. The RodClient LocalScript (paste it INTO the tool
	afterwards, see PASTE_ORDER.md) animates casting.
	The tool has RequiresHandle = true, Handle = the cork grip. 24 parts total, all CastShadow off.
]]

local StarterPack = game:GetService("StarterPack")
local ServerStorage = game:GetService("ServerStorage")

local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = a
	return w
end

local old = StarterPack:FindFirstChild("FishingRod")
if old then
	old:Destroy()
end
local tool = Instance.new("Tool")
tool.Name = "FishingRod"
tool.RequiresHandle = true
tool.CanBeDropped = false
tool.ToolTip = "Cast your line"
tool.Grip = CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(-20))

-- handle (cork grip), the rod's local axis: +Y runs from the butt to the tip
local handle = part(tool, "Handle", Vector3.new(0.45, 2.6, 0.45), CFrame.new(0, 0, 0), Color3.fromRGB(196, 160, 110), Enum.Material.Fabric,
	{ Shape = Enum.PartType.Cylinder })
handle.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis to Y
local butt = part(tool, "ButtCap", Vector3.new(0.55, 0.3, 0.55), CFrame.new(0, -1.4, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(40, 40, 45), Enum.Material.Metal,
	{ Shape = Enum.PartType.Cylinder })
weld(handle, butt)
local seat = part(tool, "ReelSeat", Vector3.new(0.5, 1.0, 0.5), CFrame.new(0, 1.75, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 62, 70), Enum.Material.Metal,
	{ Shape = Enum.PartType.Cylinder })
weld(handle, seat)

-- bent shaft: 4 tapered segments, each bent a little more toward -Z (forward) so the rod curves
local segments = { { 2.6, 0.26, 4 }, { 2.4, 0.2, 9 }, { 2.2, 0.15, 15 }, { 2.0, 0.1, 22 } }
local cursor = CFrame.new(0, 2.25, 0)
local tipPart
for i, seg in ipairs(segments) do
	local len, dia, bend = seg[1], seg[2], seg[3]
	cursor = cursor * CFrame.Angles(math.rad(-bend), 0, 0)
	local mid = cursor * CFrame.new(0, len / 2, 0)
	local p = part(tool, "Shaft" .. i, Vector3.new(dia, len, dia), mid * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(28, 30, 38), Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder, Reflectance = 0.15 })
	weld(handle, p)
	-- line guide ring
	local guide = part(tool, "Guide" .. i, Vector3.new(0.3, 0.08, 0.3), cursor * CFrame.new(0, len * 0.9, -0.12) * CFrame.Angles(math.pi / 2, 0, 0),
		Color3.fromRGB(200, 205, 215), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	weld(handle, guide)
	cursor = cursor * CFrame.new(0, len, 0)
	tipPart = p
end
local tipAttachment = Instance.new("Attachment")
tipAttachment.Name = "LineStart"
tipAttachment.Parent = tipPart
tipAttachment.WorldCFrame = cursor

-- reel: body under the seat, spool on the side, crank
local reelBody = part(tool, "ReelBody", Vector3.new(0.5, 0.7, 0.9), CFrame.new(0, 1.75, 0.55), Color3.fromRGB(55, 58, 66), Enum.Material.Metal, { Reflectance = 0.1 })
weld(handle, reelBody)
local spool = part(tool, "Spool", Vector3.new(0.9, 0.35, 0.9), CFrame.new(0, 1.75, 1.1) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(225, 228, 235), Enum.Material.Metal,
	{ Shape = Enum.PartType.Cylinder, Reflectance = 0.25 })
weld(handle, spool)
local line = part(tool, "SpoolLine", Vector3.new(0.75, 0.2, 0.75), CFrame.new(0, 1.75, 1.0) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(200, 215, 230), Enum.Material.SmoothPlastic,
	{ Shape = Enum.PartType.Cylinder })
weld(handle, line)
local crankArm = part(tool, "CrankArm", Vector3.new(0.12, 0.6, 0.12), CFrame.new(0.5, 2.0, 1.1), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
weld(handle, crankArm)
local knob = part(tool, "CrankKnob", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0.5, 2.3, 1.25), Color3.fromRGB(196, 160, 110), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
weld(handle, knob)

-- bobber: starts parked at the rod tip; RodClient moves it (it is a separate, unwelded part)
local bobber = part(tool, "Bobber", Vector3.new(0.6, 0.6, 0.6), cursor * CFrame.new(0, -0.3, 0), Color3.fromRGB(230, 40, 40), Enum.Material.SmoothPlastic,
	{ Shape = Enum.PartType.Ball, Anchored = true })
local bobberTop = part(bobber, "BobberTop", Vector3.new(0.62, 0.3, 0.62), bobber.CFrame * CFrame.new(0, 0.2, 0), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic,
	{ Shape = Enum.PartType.Ball })
weld(bobber, bobberTop)
local bobberAttachment = Instance.new("Attachment")
bobberAttachment.Name = "LineEnd"
bobberAttachment.Parent = bobber

-- line
local beam = Instance.new("Beam")
beam.Name = "Line"
beam.Attachment0 = tipAttachment
beam.Attachment1 = bobberAttachment
beam.Width0, beam.Width1 = 0.04, 0.04
beam.Color = ColorSequence.new(Color3.fromRGB(230, 240, 250))
beam.Transparency = NumberSequence.new(0.2)
beam.LightEmission = 0.2
beam.Segments = 12
beam.CurveSize0, beam.CurveSize1 = 0, 0
beam.FaceCamera = true
beam.Enabled = false
beam.Parent = tipPart

-- marker modules RodClient reads
tool:SetAttribute("CastRemotePath", "ReplicatedStorage/Remotes/Cast") -- change to your cast RemoteEvent
tool:SetAttribute("CastRange", 34)
tool:SetAttribute("Cooldown", 0) -- 0 = read from NetData/EconomyBalance; else seconds

tool.Parent = StarterPack
local toolsFolder = ServerStorage:FindFirstChild("Tools") or Instance.new("Folder")
toolsFolder.Name = "Tools"
toolsFolder.Parent = ServerStorage
local copy = toolsFolder:FindFirstChild("FishingRod")
if copy then
	copy:Destroy()
end
tool:Clone().Parent = toolsFolder

local count = 0
for _, d in ipairs(tool:GetDescendants()) do
	if d:IsA("BasePart") then
		count += 1
	end
end
print(("[RodBuilder] FishingRod built: %d parts, in StarterPack and ServerStorage.Tools. Now paste RodClient into StarterPack.FishingRod."):format(count))
