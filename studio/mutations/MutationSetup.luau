--[[
	MutationSetup: run ONCE in Roblox Studio's Command Bar (View > Command Bar), in edit mode,
	AFTER studio/items/StudioSetup.luau. Paste this whole file and press Enter.

	Creates (skipping anything that already exists, so running it twice is safe):

	ReplicatedStorage.Items.Modules        StarConfig, MutationData, EventSchedule, FishDisplay
	ServerStorage.Items.ServerModules      EventAuthority, FishSchema, MutationRoller, MutationService
	ServerScriptService.Mutations          EventServer (Script)
	StarterPlayer.StarterPlayerScripts     MutationClient (LocalScript)
	    └─ UIKit, DeviceProfile, EventPanel, EventBanner, CatchPopup, FishVisuals, EventAtmosphere

	Every new script gets a placeholder. Open it and paste the matching file from studio/mutations/
	(the path is written in the placeholder). ReplicatedStorage.Items.EventState and
	ReplicatedStorage.Items.Remotes.FishPopup are created by the server at runtime, not here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local created = 0

local function ensure(parent, className, name, sourcePath)
	local child = parent:FindFirstChild(name)
	if child == nil then
		child = Instance.new(className)
		child.Name = name
		if sourcePath then
			pcall(function()
				child.Source = ("-- Paste the contents of studio/mutations/%s here.\n%s"):format(
					sourcePath, className == "ModuleScript" and "return {}\n" or "")
			end)
		end
		child.Parent = parent
		created += 1
	elseif child.ClassName ~= className then
		warn(("MutationSetup: %s.%s is a %s (expected %s); left it alone"):format(parent:GetFullName(), name,
			child.ClassName, className))
	end
	return child
end

local items = ensure(ReplicatedStorage, "Folder", "Items")
local modules = ensure(items, "Folder", "Modules")
for _, name in ipairs({ "StarConfig", "MutationData", "EventSchedule", "FishDisplay" }) do
	ensure(modules, "ModuleScript", name, "shared/" .. name .. ".luau")
end

local serverModules = ensure(ensure(ServerStorage, "Folder", "Items"), "Folder", "ServerModules")
for _, name in ipairs({ "EventAuthority", "FishSchema", "MutationRoller", "MutationService" }) do
	ensure(serverModules, "ModuleScript", name, "server/" .. name .. ".luau")
end

local serverFolder = ensure(ServerScriptService, "Folder", "Mutations")
ensure(serverFolder, "Script", "EventServer", "server/EventServer.server.luau")

local playerScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
local client = ensure(playerScripts, "LocalScript", "MutationClient", "client/MutationClient.client.luau")
for _, name in ipairs({ "UIKit", "DeviceProfile", "EventPanel", "EventBanner", "CatchPopup", "FishVisuals",
	"EventAtmosphere" }) do
	ensure(client, "ModuleScript", name, "client/" .. name .. ".luau")
end

print(("MutationSetup: done, created %d objects. Paste the code, then follow MUTATION_MANIFEST.md."):format(created))
