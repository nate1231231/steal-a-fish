--[[
	RodClient  (LocalScript)
	Location: StarterPack > FishingRod > RodClient   (inside the Tool built by RodBuilder)
	Also copy it into ServerStorage.Tools.FishingRod.

	Cast animation + line + bobber, wired into your EXISTING cast code without touching the server:
	  1. Click/tap (Tool.Activated): the rod whips back then forward (Tool.Grip tween), the bobber flies
	     in an arc to a water point up to CastRange studs ahead (raycast for Terrain water, else a point
	     in front of the player), the Beam line follows it, the bobber bobs on the water.
	  2. At the moment of release it fires YOUR cast RemoteEvent (attribute CastRemotePath on the tool,
	     default ReplicatedStorage/Remotes/Cast) with NO arguments. The server does everything it already
	     does (cooldown, roll, saving). Nothing on the server changes.
	  3. When the server replies, the line reels in with a tug. "Reply" = any of:
	       * ReplicatedStorage.Items.Remotes.FishPopup fired to this client (MutationService)
	       * the cast RemoteEvent itself fired back to this client (if your server does that)
	       * nothing after REEL_TIMEOUT seconds -> it reels in anyway
	  4. Local cooldown matches the server's (EconomyBalance.CastSeconds for the equipped net, read
	     from the player's "EquippedNet" attribute if you set one; else the Basic Net's 10 s).
	     The server still enforces the real cooldown; this just stops the animation from spamming.
	Shift-lock, mobile taps and gamepad all work because it only uses Tool.Activated.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local tool = script.Parent
tool:WaitForChild("Handle") -- the tool is unusable until the grip has replicated
local bobber = tool:WaitForChild("Bobber")
local tipPart = tool:WaitForChild("Shaft4")
local lineStart = tipPart:WaitForChild("LineStart")
local beam = tipPart:WaitForChild("Line")
local player = Players.LocalPlayer

local REEL_TIMEOUT = 25
local CAST_RANGE = tool:GetAttribute("CastRange") or 34
local GRIP_IDLE = tool.Grip
local GRIP_BACK = GRIP_IDLE * CFrame.Angles(math.rad(70), 0, 0)
local GRIP_FORWARD = GRIP_IDLE * CFrame.Angles(math.rad(-35), 0, 0)

-- ===================================================================== server hooks (read-only)
local function findByPath(path)
	local node = game
	for name in string.gmatch(path, "[^/]+") do
		node = node:FindFirstChild(name)
		if node == nil then
			return nil
		end
	end
	return node
end

local castRemote = findByPath(tool:GetAttribute("CastRemotePath") or "ReplicatedStorage/Remotes/Cast")
if castRemote == nil then
	warn("[RodClient] cast RemoteEvent not found at " .. tostring(tool:GetAttribute("CastRemotePath")) .. "; the rod will animate but not cast")
end
local popupRemote = ReplicatedStorage:FindFirstChild("Items") and ReplicatedStorage.Items:FindFirstChild("Remotes")
	and ReplicatedStorage.Items.Remotes:FindFirstChild("FishPopup")

local function cooldownSeconds()
	local fixed = tool:GetAttribute("Cooldown")
	if fixed and fixed > 0 then
		return fixed
	end
	local ok, seconds = pcall(function()
		local modules = ReplicatedStorage.Items.Modules
		local EconomyBalance = require(modules.EconomyBalance)
		return EconomyBalance.CastSeconds(player:GetAttribute("EquippedNet") or "net_basic")
	end)
	return ok and seconds or 10
end

-- ===================================================================== state
local state = "Idle" -- Idle | Casting | Waiting | Reeling
local lastCast = 0
local caught = Instance.new("BindableEvent")
if popupRemote then
	popupRemote.OnClientEvent:Connect(function(kind)
		if kind == "Catch" then
			caught:Fire()
		end
	end)
end
if castRemote and castRemote:IsA("RemoteEvent") then
	castRemote.OnClientEvent:Connect(function()
		caught:Fire()
	end)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function waterPointAhead()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	rayParams.FilterDescendantsInstances = { character, tool }
	local forward = root.CFrame.LookVector
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	-- walk forward along the look direction and drop rays until we hit water
	for d = CAST_RANGE, 8, -4 do
		local p = origin + forward * d
		local hit = workspace:Raycast(p + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), rayParams)
		if hit and hit.Instance == workspace.Terrain and hit.Material == Enum.Material.Water then
			return hit.Position + Vector3.new(0, 0.25, 0)
		end
	end
	-- no water in front: land the bobber on whatever is ahead
	local hit = workspace:Raycast(origin + forward * (CAST_RANGE * 0.6) + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), rayParams)
	return hit and hit.Position + Vector3.new(0, 0.3, 0) or origin + forward * CAST_RANGE * 0.6
end

local function parkBobber()
	beam.Enabled = false
	bobber.Anchored = true
	bobber.CFrame = lineStart.WorldCFrame * CFrame.new(0, -0.3, 0)
end

local function tweenGrip(target, seconds, style)
	local tween = TweenService:Create(tool, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Grip = target })
	tween:Play()
	return tween
end

local function flyBobber(target, seconds)
	local start = lineStart.WorldPosition
	local t = 0
	beam.Enabled = true
	beam.CurveSize0, beam.CurveSize1 = 2, 1
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t = math.min(t + dt / seconds, 1)
		local p = start:Lerp(target, t)
		local arc = math.sin(t * math.pi) * (start - target).Magnitude * 0.35
		bobber.CFrame = CFrame.new(p + Vector3.new(0, arc, 0))
		if t >= 1 then
			conn:Disconnect()
		end
	end)
	task.wait(seconds)
	beam.CurveSize0, beam.CurveSize1 = 0.6, 0
end

local function bobOnWater(target, until_)
	local t0 = os.clock()
	while os.clock() < until_ and state == "Waiting" do
		local y = math.sin((os.clock() - t0) * 2.2) * 0.18
		bobber.CFrame = CFrame.new(target + Vector3.new(0, y, 0)) * CFrame.Angles(math.sin(os.clock() * 1.7) * 0.15, 0, 0)
		RunService.RenderStepped:Wait()
	end
end

local function reelIn(gotFish)
	state = "Reeling"
	local spool = tool:FindFirstChild("Spool")
	if gotFish then -- tug under the water then whip up
		local base = bobber.CFrame
		for _ = 1, 3 do
			bobber.CFrame = base * CFrame.new(0, -0.6, 0)
			task.wait(0.08)
			bobber.CFrame = base
			task.wait(0.08)
		end
		tweenGrip(GRIP_BACK, 0.18, Enum.EasingStyle.Back)
	end
	local start = bobber.Position
	local seconds = gotFish and 0.45 or 0.7
	local t = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t = math.min(t + dt / seconds, 1)
		local tip = lineStart.WorldPosition
		local p = start:Lerp(tip, t * t)
		bobber.CFrame = CFrame.new(p + Vector3.new(0, math.sin(t * math.pi) * (gotFish and 4 or 1.5), 0))
		if spool then
			spool.CFrame = spool.CFrame * CFrame.Angles(0, dt * 25, 0)
		end
		if t >= 1 then
			conn:Disconnect()
		end
	end)
	task.wait(seconds)
	parkBobber()
	tweenGrip(GRIP_IDLE, 0.3)
	state = "Idle"
end

-- ===================================================================== cast
local function cast()
	if state ~= "Idle" then
		return
	end
	local now = os.clock()
	if now - lastCast < cooldownSeconds() * 0.95 then
		tweenGrip(GRIP_IDLE * CFrame.Angles(math.rad(8), 0, 0), 0.08)
		task.delay(0.08, function()
			tweenGrip(GRIP_IDLE, 0.12)
		end)
		return
	end
	local target = waterPointAhead()
	if not target then
		return
	end
	state = "Casting"
	lastCast = now
	tweenGrip(GRIP_BACK, 0.22, Enum.EasingStyle.Sine).Completed:Wait()
	tweenGrip(GRIP_FORWARD, 0.14, Enum.EasingStyle.Quad)
	task.wait(0.08)
	bobber.Anchored = true
	local caughtFlag = false
	local connection = caught.Event:Connect(function()
		caughtFlag = true
	end)
	if castRemote then
		if castRemote:IsA("RemoteEvent") then
			castRemote:FireServer() -- no arguments: the server decides everything
		elseif castRemote:IsA("RemoteFunction") then
			task.spawn(function()
				pcall(castRemote.InvokeServer, castRemote)
				caughtFlag = true
			end)
		end
	end
	flyBobber(target, 0.55)
	tweenGrip(GRIP_IDLE * CFrame.Angles(math.rad(-15), 0, 0), 0.3)
	state = "Waiting"
	local deadline = os.clock() + REEL_TIMEOUT
	task.spawn(bobOnWater, target, deadline)
	while os.clock() < deadline and not caughtFlag and state == "Waiting" do
		task.wait(0.05)
	end
	connection:Disconnect()
	if state == "Waiting" then
		reelIn(caughtFlag)
	end
end

tool.Activated:Connect(cast)
tool.Equipped:Connect(function()
	tool.Grip = GRIP_IDLE
	parkBobber()
	state = "Idle"
end)
tool.Unequipped:Connect(function()
	state = "Idle"
	parkBobber()
end)
parkBobber()
