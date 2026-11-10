--[[
	UIKit  (ModuleScript)
	Put in: StarterPlayer > StarterPlayerScripts > MutationClient > UIKit
	(a child of the MutationClient LocalScript)

	Small helpers so every mutation UI is built the same way, phone first:
	  * ScreenGuis use ScreenInsets = CoreUISafeInsets (stays clear of notches and the Roblox top bar)
	  * every panel gets a UIScale that follows the screen size (1.0 on a phone, up to 1.6 on desktop)
	  * TweenService shortcuts
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.FONT_TITLE = Enum.Font.FredokaOne
UIKit.FONT_BODY = Enum.Font.BuilderSansBold
UIKit.DARK = Color3.fromRGB(18, 22, 32)
UIKit.WHITE = Color3.new(1, 1, 1)

-- Design size is a landscape phone (about 800 x 400 points). Scale = shortest screen side / 400.
UIKit.BASE_SHORT_SIDE = 400
UIKit.MIN_SCALE = 0.85
UIKit.MAX_SCALE = 1.6

function UIKit.CreateScreenGui(name, displayOrder)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder or 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local ok = pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	if not ok then
		gui.IgnoreGuiInset = false -- older clients: at least stay below the top bar
	end
	gui.Parent = playerGui
	return gui
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(800, 400)
end

function UIKit.GetScale()
	local size = viewportSize()
	return math.clamp(math.min(size.X, size.Y) / UIKit.BASE_SHORT_SIDE, UIKit.MIN_SCALE, UIKit.MAX_SCALE)
end

--[[
	Adds a UIScale to `guiObject` and keeps it updated when the screen changes.
	designWidth (optional): the object's unscaled width; the scale is reduced so it never takes
	more than 92% of the screen width (portrait phones). onChanged(scale) is called after updates.
]]
function UIKit.AttachScale(guiObject, designWidth, onChanged)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = guiObject
	local function update()
		local scale = UIKit.GetScale()
		if designWidth then
			scale = math.min(scale, viewportSize().X * 0.92 / designWidth)
		end
		uiScale.Scale = scale
		if onChanged then
			onChanged(scale)
		end
	end
	local cameraConnection
	local function hookCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	hookCamera()
	return uiScale
end

function UIKit.Corner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

function UIKit.Stroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or UIKit.WHITE
	stroke.Thickness = thickness or 2
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = parent:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIKit.Padding(parent, pixels)
	local padding = Instance.new("UIPadding")
	local p = UDim.new(0, pixels)
	padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = p, p, p, p
	padding.Parent = parent
	return padding
end

function UIKit.Frame(props)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = UIKit.DARK
	for key, value in pairs(props or {}) do
		frame[key] = value
	end
	return frame
end

-- Text with a dark outline so it reads on any background
function UIKit.Label(props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = UIKit.FONT_BODY
	label.TextColor3 = UIKit.WHITE
	label.TextSize = 16
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local outline = props and props.Outline
	for key, value in pairs(props or {}) do
		if key ~= "Outline" then
			label[key] = value
		end
	end
	if outline ~= false then
		UIKit.Stroke(label, Color3.fromRGB(10, 10, 16), outline or 1.5, 0.15)
	end
	return label
end

function UIKit.Tween(instance, seconds, goal, style, direction, repeatCount, reverses)
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out, repeatCount or 0, reverses or false), goal)
	tween:Play()
	return tween
end

-- Icon for an event: uploaded image if iconAssetId > 0, otherwise its emoji
function UIKit.EventIcon(parent, mutation, size)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "EventIcon" then
			child:Destroy()
		end
	end
	local icon
	if mutation and (mutation.iconAssetId or 0) > 0 then
		icon = Instance.new("ImageLabel")
		icon.Image = "rbxassetid://" .. tostring(mutation.iconAssetId)
		icon.BackgroundTransparency = 1
	else
		icon = UIKit.Label({ Text = mutation and mutation.emoji or "🌊", TextSize = size * 0.62, Outline = false,
			Font = UIKit.FONT_TITLE, TextTruncate = Enum.TextTruncate.None })
	end
	icon.Name = "EventIcon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.Parent = parent
	return icon
end

function UIKit.FormatMultiplier(value)
	return "x" .. tostring(math.floor(value * 100 + 0.5) / 100)
end

return UIKit
