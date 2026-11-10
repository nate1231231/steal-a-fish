--[[
	EventPanel  (ModuleScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient > EventPanel

	Countdown panel on the LEFT side, under the cash HUD.
	  Calm (next event more than 15 min away):  "🌊 Calm seas · Next event soon"   (no timer)
	  Countdown (final 15 minutes):             "⛈️ Next: Thunderstorm · Starts in 14:59"
	  Active:                                   "⛈️ Thunderstorm · ACTIVE 7:42 left" (pulsing border)

	Placement: if any GuiObject named "CashHUD" exists in PlayerGui, the panel snaps 8 px under it.
	Otherwise it reserves CASH_HUD_HEIGHT px at the top-left for your future cash display.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Items"):WaitForChild("Modules")
local EventSchedule = require(Modules:WaitForChild("EventSchedule"))
local UIKit = require(script.Parent.UIKit)

local EventPanel = {}
EventPanel.__index = EventPanel

EventPanel.MARGIN = 10
EventPanel.CASH_HUD_HEIGHT = 56 -- unscaled height reserved for the cash HUD above the panel
EventPanel.WIDTH, EventPanel.HEIGHT = 214, 58
local CALM_COLOR = Color3.fromRGB(90, 150, 200)

function EventPanel.new(screenGui)
	local self = setmetatable({}, EventPanel)
	self.mode = nil
	self.scale = 1

	local frame = UIKit.Frame({
		Name = "EventPanel",
		AnchorPoint = Vector2.new(0, 0),
		Size = UDim2.fromOffset(EventPanel.WIDTH, EventPanel.HEIGHT),
		BackgroundTransparency = 0.12,
	})
	UIKit.Corner(frame, 14)
	self.stroke = UIKit.Stroke(frame, CALM_COLOR, 2.5, 0)
	self.gradient = Instance.new("UIGradient")
	self.gradient.Rotation = 0
	self.gradient.Parent = frame

	local iconHolder = UIKit.Frame({ Name = "IconHolder", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = CALM_COLOR })
	UIKit.Corner(iconHolder, 21)
	iconHolder.Parent = frame
	self.iconHolder = iconHolder

	self.title = UIKit.Label({ Name = "Title", Position = UDim2.fromOffset(58, 7), Size = UDim2.fromOffset(148, 22),
		Font = UIKit.FONT_TITLE, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = "Calm seas" })
	self.title.Parent = frame
	self.subtitle = UIKit.Label({ Name = "Subtitle", Position = UDim2.fromOffset(58, 30), Size = UDim2.fromOffset(148, 18),
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = "Next event soon",
		TextColor3 = Color3.fromRGB(205, 215, 230) })
	self.subtitle.Parent = frame

	local barBack = UIKit.Frame({ Name = "Bar", Position = UDim2.new(0, 58, 1, -8), Size = UDim2.fromOffset(146, 4),
		BackgroundColor3 = Color3.fromRGB(60, 66, 80) })
	UIKit.Corner(barBack, 2)
	barBack.Parent = frame
	self.barFill = UIKit.Frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = CALM_COLOR })
	UIKit.Corner(self.barFill, 2)
	self.barFill.Parent = barBack

	self.frame = frame
	frame.Parent = screenGui
	self.screenGui = screenGui
	UIKit.AttachScale(frame, EventPanel.WIDTH + EventPanel.MARGIN, function(scale)
		self.scale = scale
		self:Reposition()
	end)
	self:WatchCashHud()
	UIKit.EventIcon(iconHolder, nil, 42)
	return self
end

-- Finds a GuiObject called "CashHUD" anywhere in PlayerGui and keeps the panel under it
function EventPanel:WatchCashHud()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function find()
		local found = playerGui:FindFirstChild("CashHUD", true)
		if found and found:IsA("ScreenGui") then
			found = found:FindFirstChildWhichIsA("GuiObject")
		end
		if found ~= self.cashHud then
			self.cashHud = found
			if found then
				found:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					self:Reposition()
				end)
				found:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
					self:Reposition()
				end)
			end
			self:Reposition()
		end
	end
	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "CashHUD" then
			task.defer(find)
		end
	end)
	find()
end

function EventPanel:Reposition()
	local top: number
	if self.cashHud and self.cashHud.Parent then
		local bottom: number = self.cashHud.AbsolutePosition.Y + self.cashHud.AbsoluteSize.Y
		top = bottom - self.screenGui.AbsolutePosition.Y + 8
	else
		top = EventPanel.MARGIN + EventPanel.CASH_HUD_HEIGHT * self.scale + 8
	end
	self.frame.Position = UDim2.fromOffset(EventPanel.MARGIN, math.max(top :: number, EventPanel.MARGIN))
end

function EventPanel:SetTheme(color, mutation)
	UIKit.Tween(self.stroke, 0.4, { Color = color })
	UIKit.Tween(self.iconHolder, 0.4, { BackgroundColor3 = color })
	UIKit.Tween(self.barFill, 0.4, { BackgroundColor3 = color })
	self.gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.6))
	UIKit.EventIcon(self.iconHolder, mutation, 42)
end

function EventPanel:SetPulse(on)
	if self.pulse then
		self.pulse:Cancel()
		self.pulse = nil
		self.stroke.Transparency = 0
	end
	if on then
		self.pulse = UIKit.Tween(self.stroke, 0.8, { Transparency = 0.65 }, Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut, -1, true)
	end
end

--[[
	view = { mode = "Calm" | "Countdown" | "Active", mutation = MutationData entry, seconds = number, progress = 0..1 }
]]
function EventPanel:Update(view)
	local mutation = view.mutation
	local key = view.mode .. ":" .. (mutation and mutation.id or "")
	if key ~= self.mode then
		self.mode = key
		local color = (view.mode ~= "Calm" and mutation) and mutation.color or CALM_COLOR
		self:SetTheme(color, view.mode ~= "Calm" and mutation or nil)
		self:SetPulse(view.mode == "Active")
		local scale = self.frame:FindFirstChildOfClass("UIScale")
		if scale then -- little "pop" when the state changes
			local target = scale.Scale
			scale.Scale = target * 0.9
			UIKit.Tween(scale, 0.35, { Scale = target }, Enum.EasingStyle.Back)
		end
	end
	if view.mode == "Active" then
		self.title.Text = mutation.eventName
		self.subtitle.Text = "ACTIVE · " .. EventSchedule.FormatCountdown(view.seconds) .. " left"
		self.subtitle.TextColor3 = mutation.accent
	elseif view.mode == "Countdown" then
		self.title.Text = "Next: " .. mutation.eventName
		self.subtitle.Text = "Starts in " .. EventSchedule.FormatCountdown(view.seconds)
		self.subtitle.TextColor3 = view.seconds <= 60 and Color3.fromRGB(255, 120, 110) or Color3.fromRGB(205, 215, 230)
	else
		self.title.Text = "Calm seas"
		self.subtitle.Text = "Next event soon"
		self.subtitle.TextColor3 = Color3.fromRGB(205, 215, 230)
	end
	self.barFill.Size = UDim2.fromScale(math.clamp(view.progress or 0, 0, 1), 1)
end

return EventPanel
