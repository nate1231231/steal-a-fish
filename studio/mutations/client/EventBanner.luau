--[[
	EventBanner  (ModuleScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient > EventBanner

	Announcement banner at the upper middle of the screen (12% from the top, below the Roblox
	top bar and clear of the countdown panel). It slides in, holds, then slides out. Banners queue
	so they never overlap.
	  Start:    "Thunderstorm is here!"  /  "Mutated fish are worth x2"      (holds 4 s)
	  Heads-up: "Thunderstorm in 15 minutes!" and "... in 1 minute!"        (holds 2.5 s)
	  End:      "Thunderstorm has passed"                                   (holds 2.5 s)
]]

local UIKit = require(script.Parent.UIKit)

local EventBanner = {}
EventBanner.__index = EventBanner

EventBanner.TOP = 0.12 -- 12% from the top of the safe area
EventBanner.WIDTH, EventBanner.HEIGHT = 430, 76
local HIDDEN = UDim2.new(0.5, 0, -0.3, 0)
local SHOWN = UDim2.new(0.5, 0, EventBanner.TOP, 0)

function EventBanner.new(screenGui)
	local self = setmetatable({ queue = {}, running = false }, EventBanner)
	local frame = UIKit.Frame({
		Name = "EventBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = HIDDEN,
		Size = UDim2.fromOffset(EventBanner.WIDTH, EventBanner.HEIGHT),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
	})
	UIKit.Corner(frame, 18)
	self.stroke = UIKit.Stroke(frame, Color3.new(1, 1, 1), 3, 0)
	self.gradient = Instance.new("UIGradient")
	self.gradient.Rotation = 90
	self.gradient.Parent = frame

	local iconHolder = UIKit.Frame({ Name = "IconHolder", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6 })
	UIKit.Corner(iconHolder, 28)
	iconHolder.Parent = frame
	self.iconHolder = iconHolder

	self.title = UIKit.Label({ Name = "Title", Position = UDim2.fromOffset(78, 9), Size = UDim2.new(1, -90, 0, 32),
		Font = UIKit.FONT_TITLE, TextSize = 27, TextXAlignment = Enum.TextXAlignment.Left, Outline = 2.5 })
	self.title.Parent = frame
	self.subtitle = UIKit.Label({ Name = "Subtitle", Position = UDim2.fromOffset(78, 43), Size = UDim2.new(1, -90, 0, 22),
		TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Outline = 1.8 })
	self.subtitle.Parent = frame

	frame.Parent = screenGui
	self.frame = frame
	UIKit.AttachScale(frame, EventBanner.WIDTH)
	return self
end

--[[
	info = { mutation = MutationData entry, title = string, subtitle = string, hold = seconds, kind = "Start" | "HeadsUp" | "End" }
	"Start" banners jump ahead of queued heads-ups.
]]
function EventBanner:Show(info)
	if info.kind == "Start" then
		table.insert(self.queue, 1, info)
	else
		table.insert(self.queue, info)
	end
	while #self.queue > 4 do
		table.remove(self.queue) -- never build up a long backlog
	end
	if not self.running then
		self.running = true
		task.spawn(function()
			while #self.queue > 0 do
				self:Play(table.remove(self.queue, 1))
			end
			self.running = false
		end)
	end
end

function EventBanner:Play(info)
	local mutation = info.mutation
	local color = mutation and mutation.color or Color3.fromRGB(90, 150, 200)
	local accent = mutation and mutation.accent or Color3.new(1, 1, 1)
	self.gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15), color:Lerp(Color3.new(0, 0, 0), 0.35))
	self.stroke.Color = accent
	self.title.Text = info.title
	self.subtitle.Text = info.subtitle or ""
	self.subtitle.TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.5)
	UIKit.EventIcon(self.iconHolder, mutation, 56)

	local frame = self.frame
	frame.Position = HIDDEN
	frame.Visible = true
	UIKit.Tween(frame, 0.5, { Position = SHOWN }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.wait(0.5 + (info.hold or 4))
	local out = UIKit.Tween(frame, 0.35, { Position = HIDDEN }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	out.Completed:Wait()
	frame.Visible = false
end

return EventBanner
