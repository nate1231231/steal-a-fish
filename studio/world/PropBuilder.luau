--[[
	PropBuilder  (COMMAND BAR script, run ONCE in edit mode, AFTER TerrainBuilder)
	Location: paste into View > Command Bar and press Enter.
	Needs: ReplicatedStorage.World.WorldConfig.

	Builds every prop from Parts and WedgeParts only (no meshes, no external assets) into
	workspace.WorldProps, placed on the terrain around your plots:
	  * a nipa hut beside each plot (bamboo walls, cogon roof from wedges, stilts, door, window)
	  * bamboo fences along the back of each plot pad
	  * coconut palms (bent trunk from 5 tilted cylinders, 7 leaf wedges, 3 coconuts)
	  * rocks (rotated slate blocks), lanterns (post + glass + PointLight) along the paths and plaza
	  * a wooden pier from the plaza into the sea (posts, planks, rails, two lanterns)
	Everything is Anchored, small parts have CastShadow/CanCollide/CanQuery/CanTouch off.
	Re-running deletes workspace.WorldProps first. Part budget is printed at the end (about 1,100 parts).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local WorldConfig = require(ReplicatedStorage:WaitForChild("World"):WaitForChild("WorldConfig"))

local S = WorldConfig.SETTINGS
local L = WorldConfig.Layout()
local rng = Random.new(4242)
local partCount = 0

ChangeHistoryService:SetWaypoint("Before props")
local old = workspace:FindFirstChild("WorldProps")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "WorldProps"
root.Parent = workspace

-- ===================================================================== helpers
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }

local function groundAt(x, z, fallback)
	local hit = workspace:Raycast(Vector3.new(x, L.plotLevel + 80, z), Vector3.new(0, -200, 0), rayParams)
	if hit then
		return hit.Position.Y, hit.Material
	end
	return fallback or L.plotLevel, Enum.Material.Grass
end

local function part(parent, props, small)
	local p = Instance.new(props.Wedge and "WedgePart" or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.Wood
	p.Color = props.Color or Color3.fromRGB(150, 100, 60)
	p.Size = props.Size
	p.CFrame = props.CFrame
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	if small then
		p.CastShadow = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	else
		p.CanCollide = props.CanCollide ~= false
		p.CanTouch = false
	end
	p.Name = props.Name or "Part"
	p.Parent = parent
	partCount += 1
	return p
end

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or root
	return m
end

local C = {
	bamboo = Color3.fromRGB(205, 186, 110), bambooDark = Color3.fromRGB(150, 135, 70), cogon = Color3.fromRGB(176, 142, 78),
	cogonDark = Color3.fromRGB(135, 104, 52), wood = Color3.fromRGB(128, 86, 52), woodLight = Color3.fromRGB(165, 118, 72),
	trunk = Color3.fromRGB(120, 92, 60), leaf = Color3.fromRGB(70, 150, 60), leafDark = Color3.fromRGB(45, 110, 45),
	coconut = Color3.fromRGB(110, 80, 40), rock = Color3.fromRGB(110, 110, 105), rockDark = Color3.fromRGB(80, 82, 80),
	lantern = Color3.fromRGB(255, 200, 110), iron = Color3.fromRGB(50, 50, 55), rope = Color3.fromRGB(200, 180, 130),
}

-- ===================================================================== props
local function nipaHut(cf, scale)
	local m = model("NipaHut")
	scale = scale or 1
	local w, d, h = 14 * scale, 12 * scale, 7 * scale
	local stilt = 3 * scale
	for _, off in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 } }) do
		part(m, { Size = Vector3.new(0.8, stilt, 0.8), CFrame = cf * CFrame.new(off[1] * (w / 2 - 1), stilt / 2, off[2] * (d / 2 - 1)),
			Color = C.bambooDark, Material = Enum.Material.Wood }, true)
	end
	part(m, { Name = "Floor", Size = Vector3.new(w + 2, 0.5, d + 2), CFrame = cf * CFrame.new(0, stilt, 0), Color = C.woodLight,
		Material = Enum.Material.WoodPlanks })
	-- walls (bamboo slat look via material + two tones)
	local wallY = stilt + h / 2
	part(m, { Size = Vector3.new(w, h, 0.6), CFrame = cf * CFrame.new(0, wallY, d / 2), Color = C.bamboo, Material = Enum.Material.Wood })
	part(m, { Size = Vector3.new(0.6, h, d), CFrame = cf * CFrame.new(-w / 2, wallY, 0), Color = C.bamboo, Material = Enum.Material.Wood })
	part(m, { Size = Vector3.new(0.6, h, d), CFrame = cf * CFrame.new(w / 2, wallY, 0), Color = C.bamboo, Material = Enum.Material.Wood })
	-- front wall with door gap and window
	local doorW = 3.2 * scale
	part(m, { Size = Vector3.new((w - doorW) / 2, h, 0.6), CFrame = cf * CFrame.new(-(doorW / 2 + (w - doorW) / 4), wallY, -d / 2), Color = C.bamboo })
	part(m, { Size = Vector3.new((w - doorW) / 2, h, 0.6), CFrame = cf * CFrame.new((doorW / 2 + (w - doorW) / 4), wallY, -d / 2), Color = C.bamboo })
	part(m, { Size = Vector3.new(doorW, h * 0.25, 0.6), CFrame = cf * CFrame.new(0, stilt + h * 0.875, -d / 2), Color = C.bamboo })
	part(m, { Name = "Window", Size = Vector3.new(3 * scale, 2.2 * scale, 0.3), CFrame = cf * CFrame.new(w / 2 + 0.1, stilt + h * 0.6, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color = Color3.fromRGB(40, 35, 30), Material = Enum.Material.SmoothPlastic }, true)
	part(m, { Name = "Awning", Size = Vector3.new(3.6 * scale, 0.25, 2.2 * scale), CFrame = cf * CFrame.new(w / 2 + 1.1, stilt + h * 0.6 + 1.4, 0) * CFrame.Angles(0, 0, math.rad(25)),
		Color = C.cogon, Material = Enum.Material.Fabric }, true)
	-- dark slat stripes on walls
	for k = 1, 4 do
		part(m, { Size = Vector3.new(w + 0.1, 0.18, 0.2), CFrame = cf * CFrame.new(0, stilt + k * h / 5, d / 2 + 0.3), Color = C.bambooDark }, true)
		part(m, { Size = Vector3.new(0.2, 0.18, d + 0.1), CFrame = cf * CFrame.new(-w / 2 - 0.3, stilt + k * h / 5, 0), Color = C.bambooDark }, true)
	end
	-- hip roof from 4 wedges (steep cogon)
	local roofH, over = 6 * scale, 2.2 * scale
	local ry = stilt + h + roofH / 2
	part(m, { Wedge = true, Size = Vector3.new(w + over * 2, roofH, d / 2 + over), CFrame = cf * CFrame.new(0, ry, -(d / 4 + over / 2)) * CFrame.Angles(0, math.pi, 0),
		Color = C.cogon, Material = Enum.Material.Fabric })
	part(m, { Wedge = true, Size = Vector3.new(w + over * 2, roofH, d / 2 + over), CFrame = cf * CFrame.new(0, ry, (d / 4 + over / 2)),
		Color = C.cogon, Material = Enum.Material.Fabric })
	part(m, { Wedge = true, Size = Vector3.new(d + over * 2, roofH, w / 2 + over), CFrame = cf * CFrame.new(-(w / 4 + over / 2), ry, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color = C.cogonDark, Material = Enum.Material.Fabric })
	part(m, { Wedge = true, Size = Vector3.new(d + over * 2, roofH, w / 2 + over), CFrame = cf * CFrame.new((w / 4 + over / 2), ry, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		Color = C.cogonDark, Material = Enum.Material.Fabric })
	part(m, { Name = "Ridge", Size = Vector3.new(w * 0.5, 0.5, 0.8), CFrame = cf * CFrame.new(0, stilt + h + roofH + 0.1, 0), Color = C.bambooDark }, true)
	-- steps
	for k = 1, 3 do
		part(m, { Size = Vector3.new(3.4 * scale, 0.4, 1.2), CFrame = cf * CFrame.new(0, k * stilt / 3 - 0.2, -d / 2 - 1.2 * (4 - k)), Color = C.wood,
			Material = Enum.Material.WoodPlanks })
	end
	return m
end

local function bambooFence(startPos, endPos, y)
	local m = model("BambooFence")
	local dir = (endPos - startPos)
	local len = dir.Magnitude
	local u = dir.Unit
	local cf = CFrame.lookAt(startPos, endPos)
	local n = math.max(2, math.floor(len / 3.2) + 1)
	for k = 0, n - 1 do
		local p = startPos + u * (k * len / (n - 1))
		part(m, { Size = Vector3.new(0.5, 4.4, 0.5), CFrame = CFrame.new(p.X, y + 2.2, p.Z), Color = C.bamboo, Material = Enum.Material.Wood,
			Shape = Enum.PartType.Cylinder, }, true).CFrame = CFrame.new(p.X, y + 2.2, p.Z) * CFrame.Angles(0, 0, math.pi / 2)
	end
	for _, h in ipairs({ 1.4, 3.4 }) do
		part(m, { Size = Vector3.new(0.35, 0.35, len), CFrame = cf * CFrame.new(0, h, len / 2), Color = C.bambooDark, Material = Enum.Material.Wood }, true)
	end
	return m
end

local function palm(pos, height, lean)
	local m = model("Palm")
	height = height or 16
	local segs = 5
	local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * (lean or 0.25)
	local p = pos

	for k = 1, segs do
		local t = k / segs
		local nextP = p + Vector3.new(dir.X * (height / segs) * t, height / segs, dir.Z * (height / segs) * t)
		local mid = (p + nextP) / 2
		local r = 1.2 - 0.6 * t
		part(m, { Size = Vector3.new(r, (nextP - p).Magnitude + 0.3, r), CFrame = CFrame.lookAt(mid, nextP) * CFrame.Angles(math.pi / 2, 0, 0),
			Color = C.trunk, Material = Enum.Material.Wood, CanCollide = k <= 2 }, k > 2)
		p = nextP
	end
	local top = p
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2 + rng:NextNumber(0, 0.4)
		local droop = rng:NextNumber(-0.35, -0.15)
		local d = Vector3.new(math.cos(a), droop, math.sin(a)).Unit
		local leafLen = 7.5
		local mid = top + d * leafLen / 2
		part(m, { Wedge = true, Size = Vector3.new(2.6, 0.5, leafLen), CFrame = CFrame.lookAt(mid, top + d * leafLen) * CFrame.Angles(math.rad(-8), 0, 0),
			Color = k % 2 == 0 and C.leaf or C.leafDark, Material = Enum.Material.Grass }, true)
	end
	for k = 1, 3 do
		local a = k / 3 * math.pi * 2
		part(m, { Size = Vector3.new(1, 1, 1), Shape = Enum.PartType.Ball, CFrame = CFrame.new(top + Vector3.new(math.cos(a) * 0.8, -0.6, math.sin(a) * 0.8)),
			Color = C.coconut, Material = Enum.Material.SmoothPlastic }, true)
	end
	return m
end

local function rock(pos, size)
	local m = model("Rock")
	local n = rng:NextInteger(2, 3)
	for k = 1, n do
		local s = size * rng:NextNumber(0.55, 1.0)
		local off = Vector3.new(rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.1, 0.2), rng:NextNumber(-0.4, 0.4)) * size
		part(m, { Size = Vector3.new(s * rng:NextNumber(0.8, 1.4), s * rng:NextNumber(0.5, 0.9), s * rng:NextNumber(0.8, 1.4)),
			CFrame = CFrame.new(pos + off) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
			Color = k == 1 and C.rock or C.rockDark, Material = Enum.Material.Slate, CanCollide = size > 2.5 }, size <= 2.5)
	end
	return m
end

local function lantern(pos, tall)
	local m = model("Lantern")
	local h = tall and 7 or 4
	part(m, { Size = Vector3.new(0.5, h, 0.5), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)), Color = C.bambooDark, Material = Enum.Material.Wood }, true)
	part(m, { Size = Vector3.new(1.6, 0.2, 0.3), CFrame = CFrame.new(pos + Vector3.new(0.6, h - 0.3, 0)), Color = C.bambooDark }, true)
	local glass = part(m, { Size = Vector3.new(1.1, 1.5, 1.1), CFrame = CFrame.new(pos + Vector3.new(1.3, h - 1.3, 0)), Color = C.lantern,
		Material = Enum.Material.Neon, Transparency = 0.15 }, true)
	part(m, { Size = Vector3.new(1.3, 0.25, 1.3), CFrame = CFrame.new(pos + Vector3.new(1.3, h - 0.45, 0)), Color = C.iron, Material = Enum.Material.Metal }, true)
	part(m, { Size = Vector3.new(1.3, 0.25, 1.3), CFrame = CFrame.new(pos + Vector3.new(1.3, h - 2.15, 0)), Color = C.iron, Material = Enum.Material.Metal }, true)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Brightness = 1.4
	light.Range = tall and 16 or 11
	light.Shadows = false
	light.Parent = glass
	return m
end

local function pier(startPos, dir, length, width, seaLevel)
	local m = model("Pier")
	local deckY = seaLevel + 3.2
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local n = math.floor(length / 2.4)
	for k = 0, n - 1 do
		local p = startPos + dir * (k * 2.4 + 1.2)
		part(m, { Name = "Plank", Size = Vector3.new(width, 0.45, 2.2), CFrame = CFrame.lookAt(Vector3.new(p.X, deckY, p.Z), Vector3.new(p.X, deckY, p.Z) + dir),
			Color = (k % 3 == 0) and C.wood or C.woodLight, Material = Enum.Material.WoodPlanks })
	end
	for k = 0, math.floor(length / 8) do
		local p = startPos + dir * (k * 8 + 1)
		for _, side in ipairs({ -1, 1 }) do
			local base = p + right * side * (width / 2 - 0.6)
			local gy = groundAt(base.X, base.Z, seaLevel - 10)
			local postH = deckY + 1.6 - gy
			part(m, { Name = "Post", Size = Vector3.new(0.9, postH, 0.9), CFrame = CFrame.new(base.X, gy + postH / 2, base.Z), Color = C.wood, Material = Enum.Material.Wood, CanCollide = false })
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local a = startPos + right * side * (width / 2 - 0.6) + dir * 8
		local b = startPos + right * side * (width / 2 - 0.6) + dir * (length - 1)
		local mid = (a + b) / 2
		part(m, { Name = "Rail", Size = Vector3.new(0.3, 0.3, (b - a).Magnitude), CFrame = CFrame.lookAt(Vector3.new(mid.X, deckY + 2.6, mid.Z), Vector3.new(b.X, deckY + 2.6, b.Z)),
			Color = C.rope, Material = Enum.Material.Fabric }, true)
	end
	local endP = startPos + dir * (length - 2)
	part(m, { Name = "EndDeck", Size = Vector3.new(width + 6, 0.45, 6), CFrame = CFrame.lookAt(Vector3.new(endP.X, deckY, endP.Z), Vector3.new(endP.X, deckY, endP.Z) + dir),
		Color = C.woodLight, Material = Enum.Material.WoodPlanks })
	lantern(endP + right * (width / 2 + 1.5) + Vector3.new(0, 0.2, 0) + Vector3.new(0, deckY - endP.Y, 0), false).Parent = m
	lantern(startPos + right * (width / 2 + 1) + Vector3.new(0, deckY - startPos.Y, 0), true).Parent = m
	-- a "fish here" attachment the rod can use as a preferred cast spot
	local marker = Instance.new("Attachment")
	marker.Name = "CastSpot"
	marker.WorldPosition = endP + dir * 10 + Vector3.new(0, seaLevel - endP.Y, 0)
	marker.Parent = m:FindFirstChild("EndDeck")
	return m
end

-- ===================================================================== placement
local plazaC = L.plazaCenter
-- huts + fences beside every plot (on the side away from the plaza)
for _, p in ipairs(L.plots) do
	local away = Vector3.new(p.position.X - plazaC.X, 0, p.position.Z - plazaC.Z)
	away = away.Magnitude > 1 and away.Unit or Vector3.new(0, 0, 1)
	local side = Vector3.new(-away.Z, 0, away.X)
	local hutPos = p.position + away * (p.size.Z / 2 + S.PAD_MARGIN + 9) + side * 4
	local gy = groundAt(hutPos.X, hutPos.Z, p.base)
	nipaHut(CFrame.lookAt(Vector3.new(hutPos.X, gy, hutPos.Z), Vector3.new(plazaC.X, gy, plazaC.Z)), 0.9)
	local fy = groundAt(p.position.X + away.X * (p.size.Z / 2 + S.PAD_MARGIN - 1), p.position.Z + away.Z * (p.size.Z / 2 + S.PAD_MARGIN - 1), p.base)
	local fa = p.position + away * (p.size.Z / 2 + S.PAD_MARGIN - 1) - side * (p.size.X / 2 + 2)
	local fb = p.position + away * (p.size.Z / 2 + S.PAD_MARGIN - 1) + side * (p.size.X / 2 - 12)
	bambooFence(Vector3.new(fa.X, fy, fa.Z), Vector3.new(fb.X, fy, fb.Z), fy)
	-- two palms and a rock near each plot
	for k = 1, 2 do
		local pp = p.position + side * (k == 1 and 1 or -1) * (p.size.X / 2 + S.PAD_MARGIN + 6) + away * rng:NextNumber(-6, 6)
		local py = groundAt(pp.X, pp.Z, p.base)
		palm(Vector3.new(pp.X, py - 0.5, pp.Z), rng:NextNumber(13, 19))
	end
	local rp = p.position + away * (p.size.Z / 2 + S.PAD_MARGIN + 3) - side * (p.size.X / 2 + 5)
	rock(Vector3.new(rp.X, groundAt(rp.X, rp.Z, p.base) + 0.5, rp.Z), rng:NextNumber(2, 3.5))
	-- lanterns along the path to the plaza (every 18 studs, left side)
	local toPlaza = Vector3.new(plazaC.X - p.position.X, 0, plazaC.Z - p.position.Z)
	local dist = toPlaza.Magnitude
	local u = toPlaza.Unit
	local left = Vector3.new(-u.Z, 0, u.X)
	for d = p.size.Z / 2 + S.PAD_MARGIN + 6, dist - S.PLAZA_RADIUS, 18 do
		local lp = p.position + u * d + left * (S.PATH_WIDTH / 2 + 1.5)
		lantern(Vector3.new(lp.X, groundAt(lp.X, lp.Z, p.base), lp.Z), false)
	end
end

-- plaza: ring of 8 tall lanterns + 4 rocks + 6 palms
for k = 1, 8 do
	local a = k / 8 * math.pi * 2
	local lp = plazaC + Vector3.new(math.cos(a), 0, math.sin(a)) * (S.PLAZA_RADIUS - 4)
	lantern(Vector3.new(lp.X, groundAt(lp.X, lp.Z, L.plotLevel), lp.Z), true)
end
for k = 1, 6 do
	local a = (k + 0.5) / 6 * math.pi * 2
	local pp = plazaC + Vector3.new(math.cos(a), 0, math.sin(a)) * (S.PLAZA_RADIUS + 8)
	palm(Vector3.new(pp.X, groundAt(pp.X, pp.Z, L.plotLevel) - 0.5, pp.Z), rng:NextNumber(15, 21), 0.18)
end

-- scattered palms, rocks along the beach ring
for k = 1, 28 do
	local a = rng:NextNumber(0, math.pi * 2)
	local r = L.radius * rng:NextNumber(0.66, 0.84)
	local pp = Vector3.new(L.center.X + math.cos(a) * r, 0, L.center.Z + math.sin(a) * r)
	local gy, mat = groundAt(pp.X, pp.Z, L.plotLevel)
	if mat ~= Enum.Material.Water and gy > L.seaLevel + 1 then
		if rng:NextNumber() < 0.7 then
			palm(Vector3.new(pp.X, gy - 0.5, pp.Z), rng:NextNumber(12, 20))
		else
			rock(Vector3.new(pp.X, gy + 0.6, pp.Z), rng:NextNumber(2, 5))
		end
	end
end

-- pier: from the beach in pierDirection out to sea
local dir = L.pierDirection
local start
for d = S.PLAZA_RADIUS, L.radius * 1.3, 4 do
	local q = plazaC + dir * d
	local gy = groundAt(q.X, q.Z, L.seaLevel)
	if gy < L.seaLevel + 0.8 then
		start = Vector3.new(q.X, gy, q.Z) - dir * 10
		break
	end
end
if start then
	pier(start, dir, S.PIER_LENGTH, S.PIER_WIDTH, L.seaLevel)
else
	warn("[PropBuilder] could not find the shoreline for the pier; set WorldConfig.SETTINGS.PIER_DIRECTION")
end

ChangeHistoryService:SetWaypoint("Props built")
print(("[PropBuilder] done: %d parts in workspace.WorldProps (%d models)"):format(partCount, #root:GetChildren()))
