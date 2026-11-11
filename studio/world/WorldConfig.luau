--[[
	WorldConfig  (ModuleScript)
	Location: ReplicatedStorage > World > WorldConfig
	Paste FIRST. Every world script requires this.

	Finds the existing Plot1..Plot8, the spawn and the plaza in YOUR place and exposes the numbers the
	terrain, props and performance scripts need. Nothing here moves or edits your plots, spawn or
	gameplay scripts. Change the SETTINGS block if you want a bigger island or a different sea level.

	Plot discovery order (first match wins):
	  workspace.Plots.Plot1 ... workspace.Plot1 ... any descendant named "Plot1" (Model or BasePart)
	Plaza = the SpawnLocation (first one found) or, if none, the centre of all plots.
]]

local WorldConfig = {}

WorldConfig.SETTINGS = {
	PLOT_COUNT = 8,
	SEA_LEVEL_OFFSET = -7, -- sea surface Y relative to the lowest plot base (negative = below the plots)
	BEACH_WIDTH = 34, -- studs of sand between grass and water
	ISLAND_MARGIN = 95, -- extra island radius beyond the farthest plot
	PAD_MARGIN = 10, -- flat ground around each plot's footprint
	PLAZA_RADIUS = 36, -- flat round plaza around the spawn
	PATH_WIDTH = 9, -- packed-dirt paths plot <-> plaza
	HILL_HEIGHT = 26, -- max hill height above the plot level
	SEA_DEPTH = 46, -- depth of the sea far from shore
	PIER_LENGTH = 70,
	PIER_WIDTH = 10,
	PIER_DIRECTION = nil, -- Vector3 unit direction from the plaza toward the sea; nil = away from the plots' centroid
	VOXEL_RES = 4, -- Terrain voxel size (keep 4)
}

local function pivotOf(instance)
	if instance:IsA("Model") then
		local cf, size = instance:GetBoundingBox()
		return cf, size
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	return nil, nil
end

function WorldConfig.FindPlot(index)
	local name = "Plot" .. index
	local plots = workspace:FindFirstChild("Plots")
	local found = (plots and plots:FindFirstChild(name)) or workspace:FindFirstChild(name)
		or workspace:FindFirstChild(name, true)
	if found and (found:IsA("Model") or found:IsA("BasePart")) then
		return found
	end
	return nil
end

-- { {index, instance, cframe, size, base (Y of the bottom), footprint (Vector3 xz extent)} ... }
function WorldConfig.GetPlots()
	local list = {}
	for i = 1, WorldConfig.SETTINGS.PLOT_COUNT do
		local plot = WorldConfig.FindPlot(i)
		if plot then
			local cf, size = pivotOf(plot)
			table.insert(list, { index = i, instance = plot, cframe = cf, size = size, base = cf.Position.Y - size.Y / 2,
				position = cf.Position })
		end
	end
	return list
end

function WorldConfig.GetSpawn()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") then
			return inst
		end
	end
	return nil
end

--[[
	Everything derived:
	{ plots, spawn, center (Vector3 on the plot level), plotLevel (Y), seaLevel (Y), radius, pierDirection,
	  plazaCenter }
]]
function WorldConfig.Layout()
	local S = WorldConfig.SETTINGS
	local plots = WorldConfig.GetPlots()
	local spawn = WorldConfig.GetSpawn()
	if #plots == 0 then
		warn("[WorldConfig] No Plot1..Plot8 found. Using a default ring of 8 plots around the origin so the scripts still run.")
		for i = 1, S.PLOT_COUNT do
			local a = (i - 1) / S.PLOT_COUNT * math.pi * 2
			local pos = Vector3.new(math.cos(a) * 110, 2, math.sin(a) * 110)
			table.insert(plots, { index = i, instance = nil, cframe = CFrame.new(pos), size = Vector3.new(40, 4, 40),
				base = 0, position = pos })
		end
	end
	local sum, lowest, farthest = Vector3.zero, math.huge, 0
	for _, p in ipairs(plots) do
		sum += p.position
		lowest = math.min(lowest, p.base)
	end
	local centroid = sum / #plots
	local plazaCenter = spawn and spawn.Position or centroid
	local plotLevel = lowest
	local center = Vector3.new(plazaCenter.X, plotLevel, plazaCenter.Z)
	for _, p in ipairs(plots) do
		local d = (Vector3.new(p.position.X, 0, p.position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
		farthest = math.max(farthest, d + math.max(p.size.X, p.size.Z) / 2)
	end
	local pierDir = S.PIER_DIRECTION
	if pierDir == nil then
		local away = Vector3.new(plazaCenter.X - centroid.X, 0, plazaCenter.Z - centroid.Z)
		pierDir = away.Magnitude > 1 and away.Unit or Vector3.new(0, 0, -1)
	end
	return {
		plots = plots,
		spawn = spawn,
		center = center,
		plazaCenter = Vector3.new(plazaCenter.X, plotLevel, plazaCenter.Z),
		plotLevel = plotLevel,
		seaLevel = plotLevel + S.SEA_LEVEL_OFFSET,
		radius = farthest + S.ISLAND_MARGIN,
		pierDirection = pierDir,
	}
end

return WorldConfig
