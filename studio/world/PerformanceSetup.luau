--[[
	PerformanceSetup  (COMMAND BAR script, run ONCE in edit mode, LAST)
	Location: paste into View > Command Bar and press Enter.

	Phone-first settings:
	  * StreamingEnabled with a 96 / 480 stud radius and Opportunistic streaming
	  * Plot1..Plot8, the spawn and anything in workspace.Plots marked ModelStreamingMode = Persistent
	    so plot gameplay never streams out (and your scripts can keep using WaitForChild on them)
	  * WorldProps: everything anchored; parts smaller than 6 studs on every axis get CastShadow,
	    CanQuery and CanTouch off; MeshParts/Unions get CollisionFidelity = Box
	  * Terrain decoration off, PointLights capped at 16 studs, no shadows on lights
	  * Workspace physics / lighting knobs (see below)
	Prints a before/after summary.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===================================================================== streaming
workspace.StreamingEnabled = true
workspace.StreamingMinRadius = 96
workspace.StreamingTargetRadius = 480
pcall(function()
	workspace.StreamOutBehavior = Enum.StreamOutBehavior.Opportunistic
end)
pcall(function()
	workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.MinimumRadiusPause
end)
pcall(function()
	workspace.ModelStreamingBehavior = Enum.ModelStreamingBehavior.Improved
end)

local persistent = 0
local function makePersistent(inst)
	if inst and inst:IsA("Model") then
		inst.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		persistent += 1
	elseif inst and inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Model") then
		inst.Parent.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		persistent += 1
	end
end
local plotsFolder = workspace:FindFirstChild("Plots")
if plotsFolder then
	for _, child in ipairs(plotsFolder:GetChildren()) do
		makePersistent(child)
	end
end
for i = 1, 8 do
	makePersistent(workspace:FindFirstChild("Plot" .. i) or workspace:FindFirstChild("Plot" .. i, true))
end
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("SpawnLocation") then
		makePersistent(inst)
	end
end
local pier = workspace:FindFirstChild("WorldProps") and workspace.WorldProps:FindFirstChild("Pier")
if pier then
	pier.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
end

-- ===================================================================== props
local anchored, shadowsOff, collisionBox, lights = 0, 0, 0, 0
local props = workspace:FindFirstChild("WorldProps")
if props then
	for _, inst in ipairs(props:GetDescendants()) do
		if inst:IsA("BasePart") then
			if not inst.Anchored then
				inst.Anchored = true
				anchored += 1
			end
			local s = inst.Size
			if s.X < 6 and s.Y < 6 and s.Z < 6 then
				if inst.CastShadow then
					inst.CastShadow = false
					shadowsOff += 1
				end
				inst.CanQuery = false
				inst.CanTouch = false
			end
			if inst:IsA("MeshPart") or inst:IsA("UnionOperation") then
				pcall(function()
					inst.CollisionFidelity = Enum.CollisionFidelity.Box
					inst.RenderFidelity = Enum.RenderFidelity.Automatic
				end)
				collisionBox += 1
			end
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") then
			inst.Shadows = false
			inst.Range = math.min(inst.Range, 16)
			lights += 1
		end
	end
end

-- item mesh templates (if AssetMap.BuildMeshTemplates ran): box collisions, no shadows on fish
local models = ReplicatedStorage:FindFirstChild("Items") and ReplicatedStorage.Items:FindFirstChild("Models")
if models then
	for _, inst in ipairs(models:GetDescendants()) do
		if inst:IsA("MeshPart") then
			pcall(function()
				inst.CollisionFidelity = Enum.CollisionFidelity.Box
			end)
			if inst.Parent and inst.Parent.Name == "Fish" then
				inst.CastShadow = false
			end
		end
	end
end

-- ===================================================================== terrain + lighting knobs
workspace.Terrain.Decoration = false
pcall(function()
	workspace.Terrain.WaterWaveSize = 0.18
end)
Lighting.ShadowSoftness = 0.35
local dof = Lighting:FindFirstChild("SAF_DepthOfField")
if dof then
	dof.FarIntensity = 0.12 -- cheap; set Enabled = false if low-end phones still struggle
end
pcall(function()
	workspace.FallenPartsDestroyHeight = -200
end)
pcall(function()
	workspace.SignalBehavior = Enum.SignalBehavior.Deferred
end)

print(("[PerformanceSetup] streaming on (96/480), %d persistent models, %d parts anchored, %d shadows off, %d box collisions, %d lights trimmed")
	:format(persistent, anchored, shadowsOff, collisionBox, lights))
