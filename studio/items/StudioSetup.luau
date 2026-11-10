--[[
	StudioSetup: run ONCE in Roblox Studio's Command Bar (View > Command Bar), in edit mode.
	Paste this whole file into the Command Bar and press Enter.

	It creates this structure (and skips anything that already exists, so running it twice is safe):

	ReplicatedStorage
	└─ Items
	   ├─ Modules        RarityConfig, FishData, NetData, TankData, LockData, BoostData,
	   │                 CosmeticData, ShopData, ItemRegistry, EconomyBalance, AssetMap
	   ├─ Models         MeshPart templates, one folder per category (filled by AssetMap.BuildMeshTemplates)
	   │  └─ Fish, Net, Tank, Lock, Boost, BangkaSkin, Hat
	   └─ Materials      optional SurfaceAppearance objects named FishAtlas and PropsAtlas
	ServerStorage
	└─ Items
	   └─ ServerModules  LootRoller   (server only: clients can't see ServerStorage)

	Every missing ModuleScript is created with a placeholder. Open it and paste in the matching file
	from studio/items/ (for example FishData.luau into Modules > FishData).
	Using Rojo instead? Map studio/items/*.luau into these same folders and skip the pasting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local created = 0

local function ensure(parent, className, name)
	local child = parent:FindFirstChild(name)
	if child == nil then
		child = Instance.new(className)
		child.Name = name
		child.Parent = parent
		created += 1
	elseif child.ClassName ~= className then
		warn(("StudioSetup: %s.%s exists but is a %s (expected %s); left it alone"):format(
			parent:GetFullName(), name, child.ClassName, className))
	end
	return child
end

local function ensureModule(parent, name)
	local existed = parent:FindFirstChild(name) ~= nil
	local module = ensure(parent, "ModuleScript", name)
	if not existed and module:IsA("ModuleScript") then
		-- Setting Source works from the Command Bar (plugin permissions)
		pcall(function()
			module.Source = ("-- Paste the contents of studio/items/%s.luau here.\nreturn {}\n"):format(name)
		end)
	end
	return module
end

-- ReplicatedStorage side (shared, read-only data that clients may read for UI)
local items = ensure(ReplicatedStorage, "Folder", "Items")
local modules = ensure(items, "Folder", "Modules")
local models = ensure(items, "Folder", "Models")
ensure(items, "Folder", "Materials")
for _, category in ipairs({ "Fish", "Net", "Tank", "Lock", "Boost", "BangkaSkin", "Hat" }) do
	ensure(models, "Folder", category)
end
for _, name in ipairs({
	"RarityConfig", "FishData", "NetData", "TankData", "LockData", "BoostData",
	"CosmeticData", "ShopData", "ItemRegistry", "EconomyBalance", "AssetMap",
}) do
	ensureModule(modules, name)
end

-- ServerStorage side (server-only logic)
local serverItems = ensure(ServerStorage, "Folder", "Items")
local serverModules = ensure(serverItems, "Folder", "ServerModules")
ensureModule(serverModules, "LootRoller")

print(("StudioSetup: done, created %d new objects. Next: paste the module code, then follow ITEMS_MANIFEST.md."):format(created))
