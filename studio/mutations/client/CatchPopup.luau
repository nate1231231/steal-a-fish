--[[
	CatchPopup  (ModuleScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient > CatchPopup

	Popup after a catch or a steal: fish name with mutation prefixes, star grade, every mutation
	(new ones flagged NEW), and its value. Celebration grows with rarity (FishDisplay.CelebrationTier):
	  Normal     pop-in card
	  Great      + glow ring                                 (4-star fish, any mutation)
	  Epic       + spinning rays + screen flash              (5 stars, x3.5+ mutation, Legendary fish)
	  Legendary  + confetti, bigger card, longer hold        (x5+ mutation, Mythic fish)
	Lite devices get fewer confetti pieces and static rays.

	Data comes ONLY from the server's FishPopup RemoteEvent; this module just draws it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")
local FishDisplay = require(Modules:WaitForChild("FishDisplay"))
local RarityConfig = require(Modules:WaitForChild("RarityConfig"))
local UIKit = require(script.Parent.UIKit)
local DeviceProfile = require(script.Parent.DeviceProfile)

local CatchPopup = {}
CatchPopup.__index = CatchPopup

local WIDTH = 330
local HOLD = { Normal = 2.2, Great = 2.8, Epic = 3.4, Legendary = 4.4 }
local HEADER = {
	Catch = { Normal = "CAUGHT!", Great = "GREAT CATCH!", Epic = "EPIC CATCH!", Legendary = "LEGENDARY CATCH!" },
	Steal = { Normal = "STOLEN!", Great = "GREAT STEAL!", Epic = "EPIC STEAL!", Legendary = "LEGENDARY STEAL!" },
}
local GOLD = Color3.fromRGB(255, 205, 60)

function CatchPopup.new(screenGui)
	local self = setmetatable({ queue = {}, running = false, gui = screenGui }, CatchPopup)
	self.flash = UIKit.Frame({ Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20 })
	self.flash.Parent = screenGui
	return self
end

-- kind = "Catch" | "Steal" | "Lost"; record = FishSchema v2 table; gained = new mutation ids
function CatchPopup:Show(kind, record, gained, otherName)
	if type(record) ~= "table" then
		return
	end
	table.insert(self.queue, { kind = kind, record = record, gained = gained or {}, otherName = otherName })
	while #self.queue > 5 do
		table.remove(self.queue, 1)
	end
	if not self.running then
		self.running = true
		task.spawn(function()
			while #self.queue > 0 do
				local fast = #self.queue > 2 -- catching quickly: shorten holds
				self:Play(table.remove(self.queue, 1), fast)
			end
			self.running = false
		end)
	end
end

local function chip(parent, mutation, order)
	local frame = UIKit.Frame({ Name = mutation.id, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = mutation.color, LayoutOrder = order })
	UIKit.Corner(frame, 12)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	padding.Parent = frame
	local text = mutation.emoji .. " " .. mutation.prefix .. " " .. UIKit.FormatMultiplier(mutation.multiplier)
	if mutation.isNew then
		text = "NEW " .. text
		UIKit.Stroke(frame, Color3.new(1, 1, 1), 2, 0)
	end
	local label = UIKit.Label({ Text = text, TextSize = 14, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None })
	label.Parent = frame
	frame.Parent = parent
	return frame
end

function CatchPopup:Confetti(card, colors, count)
	for i = 1, count do
		local piece = UIKit.Frame({
			Size = UDim2.fromOffset(math.random(6, 11), math.random(10, 16)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.random(-60, 60), 0, 10),
			BackgroundColor3 = colors[(i % #colors) + 1],
			Rotation = math.random(0, 360),
			ZIndex = 15,
		})
		piece.Parent = card
		local goal = UDim2.new(0.5, math.random(-260, 260), 0, math.random(180, 420))
		UIKit.Tween(piece, math.random(14, 22) / 10, { Position = goal, Rotation = piece.Rotation + math.random(-540, 540),
			BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
end

function CatchPopup:Play(item, fast)
	local record, kind = item.record, item.kind
	local info = FishDisplay.Describe(record, item.gained)
	local tier = kind == "Lost" and "Normal" or info.tier
	local rank = FishDisplay.TierRank(tier)
	local lite = DeviceProfile.IsLite()
	local primary = info.primary
	local themeColor = primary and primary.color or RarityConfig.GetColor(info.rarity)

	local rows = math.max(1, math.ceil(#info.mutations / 2))
	local height = 150 + (#info.mutations > 0 and rows * 30 or 0)
	local card = UIKit.Frame({ Name = "CatchPopup", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(WIDTH, height), BackgroundTransparency = 0.05, ZIndex = 10 })
	UIKit.Corner(card, 18)
	UIKit.Stroke(card, rank >= 3 and GOLD or themeColor, rank >= 3 and 4 or 3, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(themeColor:Lerp(UIKit.DARK, 0.55), UIKit.DARK)
	gradient.Parent = card

	-- effects behind the card
	local effects = {}
	if rank >= 2 then
		local glow = UIKit.Frame({ Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 60, 1, 60), BackgroundColor3 = themeColor, BackgroundTransparency = 0.55, ZIndex = 8 })
		UIKit.Corner(glow, 40)
		glow.Parent = card
		table.insert(effects, UIKit.Tween(glow, 0.9, { BackgroundTransparency = 0.8 }, Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut, -1, true))
	end
	if rank >= 3 then
		local rays = UIKit.Frame({ Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 7 })
		for r = 1, 8 do
			local ray = UIKit.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(16, 560), Rotation = r * 22.5, BackgroundColor3 = r % 2 == 0 and GOLD or themeColor,
				BackgroundTransparency = 0.55, ZIndex = 7 })
			ray.Parent = rays
		end
		rays.Parent = card
		if not lite then
			table.insert(effects, UIKit.Tween(rays, 8, { Rotation = 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1))
		end
		self.flash.BackgroundColor3 = themeColor
		self.flash.BackgroundTransparency = 0.45
		UIKit.Tween(self.flash, 0.6, { BackgroundTransparency = 1 })
	end

	-- header
	local headerText
	if kind == "Lost" then
		headerText = (item.otherName and (item.otherName .. " stole your fish!")) or "Your fish was stolen!"
	else
		headerText = (HEADER[kind] or HEADER.Catch)[tier]
	end
	local header = UIKit.Label({ Text = headerText, Font = UIKit.FONT_TITLE, TextSize = rank >= 4 and 30 or 26,
		Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 32), ZIndex = 11, Outline = 2.5,
		TextColor3 = kind == "Lost" and Color3.fromRGB(255, 110, 100) or (rank >= 3 and GOLD or UIKit.WHITE) })
	header.Parent = card

	local name = UIKit.Label({ Text = info.name, Font = UIKit.FONT_TITLE, TextSize = 22, Position = UDim2.fromOffset(10, 42),
		Size = UDim2.new(1, -20, 0, 26), ZIndex = 11, TextColor3 = primary and primary.accent or UIKit.WHITE })
	name.Parent = card
	if primary and primary.tint.style == "rainbow" then
		name.TextColor3 = UIKit.WHITE
		local rainbow = Instance.new("UIGradient")
		local keys = {}
		for k = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 0.8, 1)))
		end
		rainbow.Color = ColorSequence.new(keys)
		rainbow.Parent = name
		local spin = 0
		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			if not name.Parent then
				connection:Disconnect()
				return
			end
			spin = (spin + dt * 0.6) % 2
			rainbow.Offset = Vector2.new(spin - 1, 0)
		end)
	end

	local stars = UIKit.Label({ Text = info.starText, TextSize = 28, Font = UIKit.FONT_TITLE, Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 30), ZIndex = 11, TextColor3 = info.starColor, TextTruncate = Enum.TextTruncate.None })
	stars.Parent = card

	local chipHolder = UIKit.Frame({ Name = "Mutations", Position = UDim2.fromOffset(10, 104), Size = UDim2.new(1, -20, 0, rows * 30),
		BackgroundTransparency = 1, ZIndex = 11 })
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	pcall(function()
		layout.Wraps = true
	end)
	layout.Parent = chipHolder
	chipHolder.Parent = card
	for index, mutation in ipairs(info.mutations) do
		local c = chip(chipHolder, mutation, index)
		if mutation.isNew then
			local scale = Instance.new("UIScale")
			scale.Scale = 0.2
			scale.Parent = c
			task.delay(0.25 + index * 0.08, function()
				UIKit.Tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
	end

	local valueText = ("%s · %s/s · sells %s"):format(UIKit.FormatMultiplier(info.totalMultiplier),
		FishDisplay.Abbreviate(info.incomePerSecond), FishDisplay.Abbreviate(info.sellValue))
	if info.mutationCapped then
		valueText ..= " (cap)"
	end
	local value = UIKit.Label({ Text = valueText, TextSize = 16, Position = UDim2.new(0, 10, 1, -36), Size = UDim2.new(1, -20, 0, 22),
		ZIndex = 11, TextColor3 = Color3.fromRGB(150, 255, 150) })
	value.Parent = card

	-- pop in
	local uiScale = UIKit.AttachScale(card, WIDTH + 40)
	local target = uiScale.Scale * (rank >= 4 and 1.12 or 1)
	uiScale.Scale = 0.1
	card.Parent = self.gui
	UIKit.Tween(uiScale, 0.4, { Scale = target }, Enum.EasingStyle.Back)
	if rank >= 4 then
		local colors = { GOLD, themeColor, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 90, 160), Color3.fromRGB(90, 220, 255) }
		self:Confetti(card, colors, lite and 10 or 28)
	end

	local hold = HOLD[tier] or 2.2
	task.wait(fast and math.min(hold, 1.6) or hold)
	for _, tween in ipairs(effects) do
		tween:Cancel()
	end
	local out = UIKit.Tween(uiScale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	out.Completed:Wait()
	card:Destroy()
end

return CatchPopup
